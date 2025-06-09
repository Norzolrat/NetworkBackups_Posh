param (
    [string]$OutputPath = "/app/credentials.xml",
    [string]$SecretUserPath = "/run/secrets/device_user",
    [string]$SecretPasswordPath = "/run/secrets/device_password"
)

function Get-CredentialFromEnvOrSecrets {
    param (
        [string]$SecretUserPath,
        [string]$SecretPasswordPath
    )

    # 1. Lire user
    if (Test-Path $SecretUserPath) {
        Write-Host "→ Lecture de l'identifiant depuis le secret : $SecretUserPath"
        $username = Get-Content $SecretUserPath
    } elseif ($env:DEVICE_USER) {
        Write-Host "→ Lecture de l'identifiant depuis la variable d'environnement DEVICE_USER"
        $username = $env:DEVICE_USER
    } else {
        throw "❌ Aucun identifiant trouvé (ni secret ni variable d’environnement)"
    }

    # 2. Lire mot de passe
    if (Test-Path $SecretPasswordPath) {
        Write-Host "→ Lecture du mot de passe depuis le secret : $SecretPasswordPath"
        $password = Get-Content $SecretPasswordPath
    } elseif ($env:DEVICE_PASSWORD) {
        Write-Host "→ Lecture du mot de passe depuis la variable d'environnement DEVICE_PASSWORD"
        $password = $env:DEVICE_PASSWORD
    } else {
        throw "❌ Aucun mot de passe trouvé (ni secret ni variable d’environnement)"
    }

    # Write-Host "DEBUG :: Valeur brute du mot de passe : '$password'"

    # 3. Convertir en SecureString
    $secure = ConvertTo-SecureString $password -AsPlainText -Force

    # 4. Retourner PSCredential
    return New-Object System.Management.Automation.PSCredential($username, $secure)
}

function Generate-CredentialFileIfNeeded {
    param (
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        Write-Host "🔐 Fichier de credentials non trouvé. Génération à: $Path" -ForegroundColor Yellow
        $cred = Get-CredentialFromEnvOrSecrets -SecretUserPath $SecretUserPath -SecretPasswordPath $SecretPasswordPath
        $cred | Export-Clixml -Path $Path
        Write-Host "✅ Fichier de credentials généré avec succès : $Path" -ForegroundColor Green
    } else {
        Write-Host "✔️ Le fichier de credentials existe déjà : $Path" -ForegroundColor Cyan
    }
}

# Exécution
Generate-CredentialFileIfNeeded -Path $OutputPath

