# 1. Exécution immédiate du backup (sortie concise en console, dupliquée dans backup.log)
# L'authentification aux équipements passe par les connecteurs (/admin/connectors)
Write-Host "⏳ Exécution du backup initial..."
pwsh /app/Backup-Network.ps1 2>&1 | Tee-Object -FilePath /var/log/backup.log -Append

# 2. Configuration du cron (backup toutes les heures, détail complet via -Verbose dans backup.log)
Write-Host "📅 Configuration du cron..."
$cronFile = "/etc/crontabs/root"
$cronLine = "0 * * * * pwsh /app/Backup-Network.ps1 -Verbose >> /var/log/backup.log 2>&1"

if (-not (Test-Path $cronFile)) {
    New-Item -Path $cronFile -ItemType File -Force | Out-Null
}

if (-not (Get-Content $cronFile | Select-String "Backup-Network.ps1")) {
    Add-Content $cronFile $cronLine
}

# 3. Démarrer crond (important : en tâche de fond Linux, pas PowerShell)
Write-Host "🔁 Démarrage du service cron..."
Start-Process crond -ArgumentList "-l 2"

# 4. Lancer le script Web principal
# Les variables peuvent être surchargées depuis l'admin (/admin/settings -> settings.json)
. /app/src/Handle-Settings.ps1
Write-Host "🚀 Démarrage de l'application principale..."
pwsh /app/Web.ps1 -prefix (Get-AppSetting 'WEB_PREFIX' 'http') -addr (Get-AppSetting 'WEB_ADDR' '0.0.0.0') -port (Get-AppSetting 'WEB_PORT' '8080')

