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

    $expectedUser = $env:ADMIN_USER
    $expectedPassword = $env:ADMIN_PASSWORD

    if (-not $expectedUser -or -not $expectedPassword) {
        Write-Warning "ADMIN_USER/ADMIN_PASSWORD non configurés : connexion admin impossible"
        return $false
    }

    return (Test-ConstantTimeEquals $username $expectedUser) -and (Test-ConstantTimeEquals $password $expectedPassword)
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
        [hashtable]$postParams
    )

    if ($method -eq 'POST') {
        $username = $postParams['username']
        $password = $postParams['password']

        if (Test-AdminCredentials -username $username -password $password) {
            $session = New-Session
            $cookie = [System.Net.Cookie]::new('session', $session.Token, '/')
            $cookie.HttpOnly = $true
            $cookie.Secure = ($env:WEB_PREFIX -eq 'https')
            return @{ Redirect = '/admin'; Cookie = $cookie }
        }

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
