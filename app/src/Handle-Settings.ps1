# Paramètres applicatifs modifiables depuis l'admin (/admin/settings).
# Stockage : /app/secrets/settings.json (600, volume secrets pour la persistance).
# Priorité de résolution : valeur définie ici > variable d'environnement > défaut.
# Le hash admin (ADMIN_PASSWORD_HASH) est géré par le formulaire de changement de
# mot de passe et n'est jamais affiché.

$script:SettingsPath = Join-Path ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".." "secrets"))) "settings.json"

$script:EditableSettings = @(
    @{ Name = 'ADMIN_USER'; Label = "Identifiant admin";           Restart = $false; Pattern = '^.{1,64}$' }
    @{ Name = 'PUB_URL';    Label = "URL publique (redirections)"; Restart = $false; Pattern = '^https?://\S+$' }
    @{ Name = 'WEB_PREFIX'; Label = "Préfixe web";                 Restart = $true;  Pattern = '^https?$' }
    @{ Name = 'WEB_ADDR';   Label = "Adresse d'écoute";            Restart = $true;  Pattern = '^[0-9A-Za-z:.\-]{1,64}$' }
    @{ Name = 'WEB_PORT';   Label = "Port d'écoute";               Restart = $true;  Pattern = '^\d{2,5}$' }
)

function Import-AppSettings {
    if (Test-Path $script:SettingsPath) {
        try {
            $json = Get-Content $script:SettingsPath -Raw | ConvertFrom-Json
            $settings = @{}
            foreach ($property in $json.PSObject.Properties) { $settings[$property.Name] = $property.Value }
            return $settings
        } catch {
            Write-Warning "settings.json illisible : $($_.Exception.Message)"
        }
    }
    return @{}
}

function Save-AppSettings {
    param([hashtable]$settings)

    $dir = Split-Path $script:SettingsPath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        chmod 700 $dir
    }
    ConvertTo-Json -InputObject ([pscustomobject]$settings) | Set-Content -Path $script:SettingsPath -Encoding UTF8
    chmod 600 $script:SettingsPath
}

function Get-AppSetting {
    param(
        [string]$name,
        [string]$default = $null
    )

    $settings = Import-AppSettings
    if ($settings[$name]) { return [string]$settings[$name] }
    $envValue = [Environment]::GetEnvironmentVariable($name)
    if ($envValue) { return $envValue }
    return $default
}

function Set-AppSetting {
    param(
        [string]$name,
        [string]$value
    )

    $settings = Import-AppSettings
    if ($value) {
        $settings[$name] = $value
    } else {
        $settings.Remove($name)   # champ vide = retour à la variable d'environnement
    }
    Save-AppSettings -settings $settings
}

# Réécrit la ligne de sauvegarde planifiée dans le crontab selon les settings
# (BACKUP_CRON / BACKUP_CRON_ENABLED). Les autres lignes du crontab sont préservées.
function Update-BackupCrontab {
    param([switch]$RestartCrond)

    $cronFile = "/etc/crontabs/root"
    $expression = Get-AppSetting 'BACKUP_CRON' '0 * * * *'
    $enabled = (Get-AppSetting 'BACKUP_CRON_ENABLED' 'true') -ne 'false'

    $lines = @()
    if (Test-Path $cronFile) {
        $lines = @(Get-Content $cronFile | Where-Object { $_ -notmatch 'Backup-Network\.ps1' -and $_.Trim() })
    }
    if ($enabled) {
        $lines += "$expression pwsh /app/Backup-Network.ps1 -Verbose >> /var/log/backup.log 2>&1"
    }
    Set-Content -Path $cronFile -Value ($lines -join "`n")

    # busybox crond ne relit pas de façon fiable un fichier modifié en place : on le redémarre
    if ($RestartCrond) {
        Start-Process -FilePath "/bin/sh" -ArgumentList '-c "pkill crond; sleep 1; crond -l 2"' | Out-Null
    }
}

function Update-BackupCronSettings {
    param([hashtable]$postParams)

    $enabled = $postParams['cronEnabled'] -eq 'on'
    $expression = ($postParams['cronExpression'] ?? '').Trim()

    if ($enabled) {
        $fields = $expression -split '\s+'
        if ($fields.Count -ne 5 -or ($fields | Where-Object { $_ -notmatch '^[\d*,/-]+$' })) {
            return "<div class='notice notice-error'>Expression cron invalide : 5 champs attendus (minute heure jour mois jour-semaine), caractères autorisés : chiffres, *, virgule, /, tiret.</div>"
        }
        Set-AppSetting -name 'BACKUP_CRON' -value $expression
        Set-AppSetting -name 'BACKUP_CRON_ENABLED' -value 'true'
    } else {
        Set-AppSetting -name 'BACKUP_CRON_ENABLED' -value 'false'
    }

    Update-BackupCrontab -RestartCrond

    $state = if ($enabled) { "planifiées (« $expression »)" } else { "désactivées" }
    return "<div class='notice notice-success'>Sauvegardes automatiques $state.</div>"
}

function Update-AdminPassword {
    param(
        [hashtable]$postParams,
        [string]$sessionToken
    )

    $current = $postParams['currentPassword']
    $new = $postParams['newPassword']
    $confirm = $postParams['confirmPassword']

    $currentHash = Get-AppSetting 'ADMIN_PASSWORD_HASH'
    $currentOk = if ($currentHash) {
        Test-Argon2Hash -password $current -encodedHash $currentHash
    } elseif ($env:ADMIN_PASSWORD) {
        Test-ConstantTimeEquals $current $env:ADMIN_PASSWORD
    } else {
        $false
    }

    if (-not $currentOk) {
        return "<div class='notice notice-error'>Mot de passe actuel incorrect.</div>"
    }
    if (-not $new -or $new.Length -lt 8) {
        return "<div class='notice notice-error'>Le nouveau mot de passe doit faire au moins 8 caractères.</div>"
    }
    if ($new -ne $confirm) {
        return "<div class='notice notice-error'>La confirmation ne correspond pas au nouveau mot de passe.</div>"
    }

    # Auto-vérification avant enregistrement : ne jamais stocker un hash qui ne
    # validerait pas le mot de passe qu'il est censé représenter
    $newHash = New-Argon2Hash -password $new
    if (-not (Test-Argon2Hash -password $new -encodedHash $newHash)) {
        return "<div class='notice notice-error'>Auto-vérification du hash échouée, mot de passe inchangé. Réessayez.</div>"
    }

    Set-AppSetting -name 'ADMIN_PASSWORD_HASH' -value $newHash
    Remove-OtherSessions -keepToken $sessionToken

    return "<div class='notice notice-success'>Mot de passe admin mis à jour (hash Argon2id enregistré, les autres sessions ont été déconnectées).</div>"
}

function Update-AppVariables {
    param([hashtable]$postParams)

    # Validation complète avant toute écriture
    foreach ($setting in $script:EditableSettings) {
        $value = ($postParams[$setting.Name] ?? '').Trim()
        if ($value -and $value -notmatch $setting.Pattern) {
            return "<div class='notice notice-error'>Valeur invalide pour $($setting.Name).</div>"
        }
    }

    $restartNeeded = $false
    foreach ($setting in $script:EditableSettings) {
        $value = ($postParams[$setting.Name] ?? '').Trim()
        $existing = [string](Import-AppSettings)[$setting.Name]
        if ($value -ne $existing) {
            Set-AppSetting -name $setting.Name -value $value
            if ($setting.Restart) { $restartNeeded = $true }
        }
    }

    $restartHtml = if ($restartNeeded) { " Les changements marqués ↻ seront appliqués au prochain redémarrage du conteneur." } else { "" }
    return "<div class='notice notice-success'>Variables enregistrées.$restartHtml</div>"
}

function Handle-AdminSettings {
    param(
        [string]$method,
        [hashtable]$postParams,
        $session,
        [string]$sessionToken
    )

    $message = ""

    if ($method -eq 'POST') {
        if ($postParams['csrf'] -ne $session.Csrf) {
            return @{ Body = "<div class='notice notice-error'>Requête invalide (CSRF)</div>"; StatusCode = 400 }
        }

        $message = switch ($postParams['action']) {
            'password' { Update-AdminPassword -postParams $postParams -sessionToken $sessionToken }
            'vars'     { Update-AppVariables -postParams $postParams }
            'cron'     { Update-BackupCronSettings -postParams $postParams }
            default    { "<div class='notice notice-error'>Action inconnue</div>" }
        }
    }

    $overrides = Import-AppSettings

    # État de la planification des sauvegardes
    $cronExpression = Get-AppSetting 'BACKUP_CRON' '0 * * * *'
    $cronEnabled = (Get-AppSetting 'BACKUP_CRON_ENABLED' 'true') -ne 'false'
    $cronChecked = if ($cronEnabled) { "checked" } else { "" }
    $encCronExpression = [System.Web.HttpUtility]::HtmlEncode($cronExpression)

    $cronFile = "/etc/crontabs/root"
    $currentCronLine = if (Test-Path $cronFile) {
        Get-Content $cronFile | Where-Object { $_ -match 'Backup-Network\.ps1' } | Select-Object -First 1
    } else { $null }
    $cronStatus = if ($currentCronLine) {
        "Ligne cron active : <code>$([System.Web.HttpUtility]::HtmlEncode($currentCronLine))</code>"
    } else {
        "Aucune sauvegarde planifiée actuellement."
    }

    $varRows = foreach ($setting in $script:EditableSettings) {
        $override = [string]$overrides[$setting.Name]
        $envValue = [string][Environment]::GetEnvironmentVariable($setting.Name)

        $sourceBadge = if ($override) {
            "<span class='badge'>personnalisé</span>"
        } elseif ($envValue) {
            "<span class='badge badge-muted'>environnement</span>"
        } else {
            "<span class='badge badge-muted'>défaut</span>"
        }
        $restartMark = if ($setting.Restart) { " <span class='label-hint' title='Appliqué au prochain redémarrage du conteneur'>↻</span>" } else { "" }
        $encOverride = [System.Web.HttpUtility]::HtmlEncode($override)
        $encPlaceholder = [System.Web.HttpUtility]::HtmlEncode($envValue)

        @"
<div class='form-group'>
    <label for='set_$($setting.Name)'>$($setting.Label) <span class='label-hint'>($($setting.Name))</span>$restartMark $sourceBadge</label>
    <input type='text' id='set_$($setting.Name)' name='$($setting.Name)' class='input' value='$encOverride' placeholder='$encPlaceholder'>
</div>
"@
    }

    return @"
$message
<div class='card settings-card'>
    <h2>Mot de passe admin</h2>
    <form method='POST' action='/admin/settings'>
        <input type='hidden' name='csrf' value='$($session.Csrf)'>
        <input type='hidden' name='action' value='password'>
        <div class='form-group'>
            <label for='currentPassword'>Mot de passe actuel</label>
            <input type='password' id='currentPassword' name='currentPassword' class='input' autocomplete='current-password' required>
        </div>
        <div class='form-grid'>
            <div class='form-group'>
                <label for='newPassword'>Nouveau mot de passe <span class='label-hint'>— 8 caractères minimum</span></label>
                <input type='password' id='newPassword' name='newPassword' class='input' autocomplete='new-password' minlength='8' required>
            </div>
            <div class='form-group'>
                <label for='confirmPassword'>Confirmation</label>
                <input type='password' id='confirmPassword' name='confirmPassword' class='input' autocomplete='new-password' minlength='8' required>
            </div>
        </div>
        <button type='submit' class='btn btn-primary'>Mettre à jour le mot de passe</button>
    </form>
</div>

<div class='card settings-card' style='margin-top:18px;'>
    <h2>Sauvegardes planifiées</h2>
    <p class='hint' style='margin:6px 0 16px;'>$cronStatus</p>
    <form method='POST' action='/admin/settings'>
        <input type='hidden' name='csrf' value='$($session.Csrf)'>
        <input type='hidden' name='action' value='cron'>
        <label class='checkbox-line'>
            <input type='checkbox' name='cronEnabled' id='cronEnabled' $cronChecked onchange='toggleCronFields()'>
            Activer les sauvegardes automatiques
        </label>
        <div class='form-grid cron-fields'>
            <div class='form-group'>
                <label for='cronPreset'>Fréquence prédéfinie</label>
                <select id='cronPreset' class='select' onchange='applyCronPreset()'>
                    <option value=''>— Choisir —</option>
                    <option value='0 * * * *'>Toutes les heures</option>
                    <option value='0 */2 * * *'>Toutes les 2 heures</option>
                    <option value='0 */6 * * *'>Toutes les 6 heures</option>
                    <option value='0 */12 * * *'>Toutes les 12 heures</option>
                    <option value='0 2 * * *'>Tous les jours à 02h00</option>
                    <option value='0 2 * * 1'>Chaque lundi à 02h00</option>
                </select>
            </div>
            <div class='form-group'>
                <label for='cronExpression'>Expression cron <span class='label-hint'>— minute heure jour mois jour-semaine</span></label>
                <input type='text' id='cronExpression' name='cronExpression' class='input' value='$encCronExpression' placeholder='0 * * * *'>
            </div>
        </div>
        <button type='submit' class='btn btn-primary'>Enregistrer la planification</button>
    </form>
</div>

<div class='card settings-card' style='margin-top:18px;'>
    <h2>Variables</h2>
    <p class='hint' style='margin:6px 0 16px;'>Les valeurs définies ici priment sur les variables d'environnement du conteneur et sont conservées dans
    <code>/app/secrets/settings.json</code>. Champ vide = utiliser la variable d'environnement. ↻ = pris en compte au redémarrage.</p>
    <form method='POST' action='/admin/settings'>
        <input type='hidden' name='csrf' value='$($session.Csrf)'>
        <input type='hidden' name='action' value='vars'>
        $($varRows -join "`n")
        <button type='submit' class='btn btn-primary'>Enregistrer les variables</button>
    </form>
</div>
"@
}
