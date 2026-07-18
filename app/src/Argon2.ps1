# Hachage et vérification Argon2 du mot de passe admin, via le binaire `argon2`
# (implémentation de référence, paquet Alpine "argon2").
# Le mot de passe transite uniquement par stdin (jamais en argument de commande),
# le sel est généré en ASCII imprimable pour pouvoir être repassé au CLI lors de la vérification.
# Note : Test-Argon2Hash s'appuie sur Test-ConstantTimeEquals (défini dans Handle-Auth.ps1).

# Paramètres par défaut (argon2id, 64 MiB, 3 itérations, parallélisme 4, hash 32 octets)
$script:Argon2TimeCost = 3
$script:Argon2MemoryKiB = 65536
$script:Argon2Parallelism = 4
$script:Argon2HashLength = 32

function Invoke-Argon2 {
    param(
        [string]$password,
        [string]$salt,
        [string]$typeFlag = '-id',
        [int]$timeCost = $script:Argon2TimeCost,
        [int]$memoryKiB = $script:Argon2MemoryKiB,
        [int]$parallelism = $script:Argon2Parallelism,
        [int]$hashLength = $script:Argon2HashLength,
        [string]$versionFlag = '13'
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'argon2'
    foreach ($arg in @($salt, $typeFlag, '-t', $timeCost, '-k', $memoryKiB, '-p', $parallelism, '-l', $hashLength, '-v', $versionFlag, '-e')) {
        $psi.ArgumentList.Add([string]$arg)
    }
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false

    $process = [System.Diagnostics.Process]::Start($psi)
    $process.StandardInput.Write($password)
    $process.StandardInput.Close()
    $encoded = $process.StandardOutput.ReadToEnd().Trim()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($process.ExitCode -ne 0 -or -not $encoded) {
        throw "argon2 a échoué : $stderr"
    }
    return $encoded
}

function New-Argon2Hash {
    param([string]$password)

    if (-not $password) {
        throw "Mot de passe vide"
    }

    # Sel aléatoire en ASCII imprimable : indispensable pour que la vérification
    # puisse le repasser en argument au CLI (le biais du modulo est sans enjeu pour un sel)
    $saltChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    $bytes = [byte[]]::new(16)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $salt = -join ($bytes | ForEach-Object { $saltChars[$_ % $saltChars.Length] })

    return Invoke-Argon2 -password $password -salt $salt
}

function Test-Argon2Hash {
    param(
        [string]$password,
        [string]$encodedHash
    )

    if (-not $password -or -not $encodedHash) { return $false }

    if ($encodedHash -notmatch '^\$argon2(id|i|d)\$v=(\d+)\$m=(\d+),t=(\d+),p=(\d+)\$([A-Za-z0-9+/]+={0,2})\$([A-Za-z0-9+/]+={0,2})$') {
        Write-Warning "ADMIN_PASSWORD_HASH n'est pas un hash Argon2 encodé valide"
        return $false
    }
    $type = $Matches[1]
    $version = [int]$Matches[2]
    $memoryKiB = [int]$Matches[3]
    $timeCost = [int]$Matches[4]
    $parallelism = [int]$Matches[5]
    $saltB64 = $Matches[6]
    $hashB64 = $Matches[7]

    $saltBytes = [Convert]::FromBase64String($saltB64 + ('=' * ((4 - $saltB64.Length % 4) % 4)))
    $saltText = [System.Text.Encoding]::ASCII.GetString($saltBytes)
    if ($saltText -notmatch '^[\x21-\x7E]+$') {
        Write-Warning "Sel du hash non repassable au CLI argon2 : régénérez le hash avec New-AdminHash.ps1"
        return $false
    }
    $hashBytes = [Convert]::FromBase64String($hashB64 + ('=' * ((4 - $hashB64.Length % 4) % 4)))
    $versionFlag = if ($version -eq 16) { '10' } else { '13' }

    try {
        $candidate = Invoke-Argon2 -password $password -salt $saltText -typeFlag "-$type" -timeCost $timeCost -memoryKiB $memoryKiB -parallelism $parallelism -hashLength $hashBytes.Length -versionFlag $versionFlag
    } catch {
        Write-Warning "Vérification Argon2 impossible : $($_.Exception.Message)"
        return $false
    }

    return (Test-ConstantTimeEquals $candidate $encodedHash)
}
