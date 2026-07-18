# Les paramètres (planification cron, variables web...) peuvent être surchargés
# depuis l'admin (/admin/settings -> settings.json)
. /app/src/Handle-Settings.ps1

# 1. Exécution immédiate du backup (sortie concise en console, dupliquée dans backup.log)
# L'authentification aux équipements passe par les connecteurs (/admin/connectors)
Write-Host "⏳ Exécution du backup initial..."
pwsh /app/Backup-Network.ps1 2>&1 | Tee-Object -FilePath /var/log/backup.log -Append

# 2. Configuration du cron selon les settings (BACKUP_CRON / BACKUP_CRON_ENABLED)
Write-Host "📅 Configuration du cron..."
Update-BackupCrontab

# 3. Démarrer crond (important : en tâche de fond Linux, pas PowerShell)
Write-Host "🔁 Démarrage du service cron..."
Start-Process crond -ArgumentList "-l 2"

# 4. Lancer le script Web principal
Write-Host "🚀 Démarrage de l'application principale..."
pwsh /app/Web.ps1 -prefix (Get-AppSetting 'WEB_PREFIX' 'http') -addr (Get-AppSetting 'WEB_ADDR' '0.0.0.0') -port (Get-AppSetting 'WEB_PORT' '8080')

