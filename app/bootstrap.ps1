# 1. Génération automatique des credentials
. /app/Credentials.ps1
Generate-CredentialFileIfNeeded -Path "/app/credentials.xml"

# 2. Exécution immédiate du backup
Write-Host "⏳ Exécution du backup initial..."
pwsh /app/Backup-Network.ps1

# 3. Configuration du cron (backup toutes les heures)
Write-Host "📅 Configuration du cron..."
$cronFile = "/etc/crontabs/root"
$cronLine = "0 * * * * pwsh /app/Backup-Network.ps1 >> /var/log/backup.log 2>&1"

if (-not (Test-Path $cronFile)) {
    New-Item -Path $cronFile -ItemType File -Force | Out-Null
}

if (-not (Get-Content $cronFile | Select-String "Backup-Network.ps1")) {
    Add-Content $cronFile $cronLine
}

# 4. Démarrer crond (important : en tâche de fond Linux, pas PowerShell)
Write-Host "🔁 Démarrage du service cron..."
Start-Process crond -ArgumentList "-l 2"

# 5. Lancer le script Web principal
Write-Host "🚀 Démarrage de l'application principale..."
. /app/Web.ps1

