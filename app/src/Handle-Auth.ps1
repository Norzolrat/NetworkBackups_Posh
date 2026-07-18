# Sessions en mémoire (le serveur HTTP est mono-thread, pas besoin de verrou)
$script:Sessions = @{}
$script:SessionTtlHours = 8

function New-Session {
    $token = [guid]::NewGuid().ToString('N')
    $script:Sessions[$token] = @{
        Expiry = (Get-Date).AddHours($script:SessionTtlHours)
        Csrf   = [guid]::NewGuid().ToString('N')
    }
    return @{ Token = $token; Csrf = $script:Sessions[$token].Csrf }
}

function Test-Session {
    param(
        [string]$token
    )

    if (-not $token -or -not $script:Sessions.ContainsKey($token)) {
        return $null
    }

    $session = $script:Sessions[$token]
    if ((Get-Date) -gt $session.Expiry) {
        $script:Sessions.Remove($token)
        return $null
    }

    return $session
}

function Remove-Session {
    param(
        [string]$token
    )

    if ($token -and $script:Sessions.ContainsKey($token)) {
        $script:Sessions.Remove($token)
    }
}

# Déconnecte toutes les sessions sauf celle indiquée (utilisé au changement de mot de passe)
function Remove-OtherSessions {
    param(
        [string]$keepToken
    )

    foreach ($token in @($script:Sessions.Keys)) {
        if ($token -ne $keepToken) {
            $script:Sessions.Remove($token)
        }
    }
}

function Test-ConstantTimeEquals {
    param(
        [string]$a,
        [string]$b
    )

    if ($null -eq $a -or $null -eq $b) {
        return $false
    }

    $bytesA = [System.Text.Encoding]::UTF8.GetBytes($a)
    $bytesB = [System.Text.Encoding]::UTF8.GetBytes($b)
    return [System.Security.Cryptography.CryptographicOperations]::FixedTimeEquals($bytesA, $bytesB)
}

function Test-AdminCredentials {
    param(
        [string]$username,
        [string]$password
    )

    $expectedUser = Get-AppSetting 'ADMIN_USER'
    $passwordHash = Get-AppSetting 'ADMIN_PASSWORD_HASH'

    if (-not $expectedUser) {
        Write-Warning "ADMIN_USER non configuré : connexion admin impossible"
        return $false
    }

    # Les deux vérifications sont toujours évaluées (pas de court-circuit),
    # pour ne pas révéler par le temps de réponse si l'identifiant est valide
    $userOk = Test-ConstantTimeEquals $username $expectedUser

    if ($passwordHash) {
        $passwordOk = Test-Argon2Hash -password $password -encodedHash $passwordHash
    } elseif ($env:ADMIN_PASSWORD) {
        Write-Warning "ADMIN_PASSWORD en clair est déprécié : générez un hash avec New-AdminHash.ps1 et utilisez ADMIN_PASSWORD_HASH"
        $passwordOk = Test-ConstantTimeEquals $password $env:ADMIN_PASSWORD
    } else {
        Write-Warning "ADMIN_PASSWORD_HASH non configuré : connexion admin impossible"
        $passwordOk = $false
    }

    return ($userOk -and $passwordOk)
}

# Verrouillage anti-brute-force : après N échecs depuis une même IP, le login
# est bloqué quelques minutes (état en mémoire, serveur mono-thread)
$script:LoginFailures = @{}
$script:LoginMaxAttempts = 5
$script:LoginLockSeconds = 300

function Test-LoginLocked {
    param([string]$clientIp)

    $entry = $script:LoginFailures[$clientIp]
    if (-not $entry) { return $false }

    if ($entry.LockedUntil -and (Get-Date) -lt $entry.LockedUntil) {
        return $true
    }
    if ($entry.LockedUntil -and (Get-Date) -ge $entry.LockedUntil) {
        $script:LoginFailures.Remove($clientIp)   # verrou expiré : on repart de zéro
    }
    return $false
}

function Register-LoginFailure {
    param([string]$clientIp)

    if (-not $script:LoginFailures.ContainsKey($clientIp)) {
        $script:LoginFailures[$clientIp] = @{ Count = 0; LockedUntil = $null }
    }
    $entry = $script:LoginFailures[$clientIp]
    $entry.Count++
    if ($entry.Count -ge $script:LoginMaxAttempts) {
        $entry.LockedUntil = (Get-Date).AddSeconds($script:LoginLockSeconds)
        Write-Warning "Login verrouillé $($script:LoginLockSeconds)s pour $clientIp après $($entry.Count) échecs"
    }
}

function Clear-LoginFailures {
    param([string]$clientIp)

    if ($script:LoginFailures.ContainsKey($clientIp)) {
        $script:LoginFailures.Remove($clientIp)
    }
}

function Get-LoginForm {
    param(
        [string]$errorMessage
    )

    $errorHtml = if ($errorMessage) {
        "<div class='notice notice-error'>$([System.Web.HttpUtility]::HtmlEncode($errorMessage))</div>"
    } else { "" }

    return @"
<div class='auth-card card'>
    <h2>Connexion</h2>
    <p class='auth-sub'>Accédez au panneau NetBackup</p>
    $errorHtml
    <form method='POST' action='/login'>
        <div class='form-group'>
            <label for='username'>Identifiant</label>
            <input type='text' id='username' name='username' class='input' autocomplete='username' autofocus required>
        </div>
        <div class='form-group'>
            <label for='password'>Mot de passe</label>
            <input type='password' id='password' name='password' class='input' autocomplete='current-password' required>
        </div>
        <button type='submit' class='btn btn-primary btn-block'>Se connecter</button>
    </form>
</div>
"@
}

function Handle-Login {
    param(
        [string]$method,
        [hashtable]$postParams,
        [string]$clientIp
    )

    if ($method -eq 'POST') {
        if (Test-LoginLocked -clientIp $clientIp) {
            return Get-LoginForm -errorMessage "Trop de tentatives échouées. Réessayez dans quelques minutes."
        }

        $username = $postParams['username']
        $password = $postParams['password']

        if (Test-AdminCredentials -username $username -password $password) {
            Clear-LoginFailures -clientIp $clientIp
            $session = New-Session
            $cookie = [System.Net.Cookie]::new('session', $session.Token, '/')
            $cookie.HttpOnly = $true
            $cookie.Secure = ((Get-AppSetting 'WEB_PREFIX') -eq 'https')
            return @{ Redirect = '/admin'; Cookie = $cookie }
        }

        Register-LoginFailure -clientIp $clientIp
        return Get-LoginForm -errorMessage "Identifiants invalides"
    }

    return Get-LoginForm
}

function Handle-Logout {
    param(
        [string]$token
    )

    Remove-Session -token $token

    $cookie = [System.Net.Cookie]::new('session', 'deleted', '/')
    $cookie.HttpOnly = $true
    $cookie.Expires = (Get-Date).AddDays(-1)

    return @{ Redirect = '/login'; Cookie = $cookie }
}
