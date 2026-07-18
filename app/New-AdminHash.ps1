# Génère le hash Argon2id du mot de passe admin, à placer dans .env :
#   ADMIN_PASSWORD_HASH=<hash>   (sans guillemets dans le fichier .env)
# Usage :
#   docker run --rm -it bckp_posh-alpine pwsh /app/New-AdminHash.ps1
#   docker exec -it <conteneur> pwsh /app/New-AdminHash.ps1
param(
    [string]$Password
)

. "$PSScriptRoot/src/Argon2.ps1"

if (-not $Password) {
    $secure = Read-Host "Mot de passe admin" -AsSecureString
    $Password = [System.Net.NetworkCredential]::new('', $secure).Password
}

if (-not $Password) {
    Write-Error "Mot de passe vide"
    exit 1
}

$hash = New-Argon2Hash -password $Password

# Contrôle de cohérence : le hash généré doit se re-dériver à l'identique
$check = Invoke-Argon2 -password $Password -salt ([System.Text.Encoding]::ASCII.GetString([Convert]::FromBase64String(($hash -split '\$')[4] + ('=' * ((4 - ($hash -split '\$')[4].Length % 4) % 4)))))
if ($check -ne $hash) {
    Write-Error "Auto-vérification du hash échouée"
    exit 1
}

Write-Host ""
Write-Host "Ligne à ajouter dans votre fichier .env (remplace ADMIN_PASSWORD) :" -ForegroundColor Green
Write-Host "ADMIN_PASSWORD_HASH=$hash"
Write-Host ""
Write-Host "⚠️ En shell (export/docker -e), entourez la valeur de quotes simples à cause des '$'." -ForegroundColor Yellow
