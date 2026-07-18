function Handle-AdminDevices {
    param(
        [string]$method,
        [hashtable]$postParams,
        $session
    )

    $devicesPath = "$PSScriptRoot/../devices.json"
    $message = ""

    if ($method -eq 'POST') {
        if ($postParams['csrf'] -ne $session.Csrf) {
            return @{ Body = "<div class='notice notice-error'>Requête invalide (CSRF)</div>"; StatusCode = 400 }
        }

        $submittedContent = $postParams['devicesJson']
        $parsed = $null
        $validationError = $null
        try {
            $parsed = $submittedContent | ConvertFrom-Json -ErrorAction Stop
        } catch {
            $validationError = $_.Exception.Message
        }

        if (-not $validationError) {
            if (-not ($parsed.PSObject.Properties.Name -contains 'devices') -or $parsed.devices -isnot [System.Collections.IEnumerable]) {
                $validationError = "propriété 'devices' absente ou invalide"
            } else {
                $knownConnectors = Get-ConnectorNames
                foreach ($device in $parsed.devices) {
                    if (-not $device.Name -or -not $device.IP) {
                        $validationError = "chaque équipement doit avoir au minimum un Name et une IP"
                        break
                    }
                    if (-not $device.Connector) {
                        $validationError = "aucun connecteur défini pour $($device.Name) : le champ Connector est obligatoire"
                        break
                    }
                    if ($knownConnectors -notcontains $device.Connector) {
                        $validationError = "connecteur inconnu pour $($device.Name) : '$($device.Connector)'"
                        break
                    }
                }
            }
        }

        if ($validationError) {
            $message = "<div class='notice notice-error'>Rien n'a été enregistré : $([System.Web.HttpUtility]::HtmlEncode($validationError))</div>"
        } else {
            Copy-Item -Path $devicesPath -Destination "$devicesPath.bak" -Force -ErrorAction SilentlyContinue
            Set-Content -Path $devicesPath -Value $submittedContent -Encoding UTF8
            $message = "<div class='notice notice-success'>devices.json mis à jour (sauvegarde : devices.json.bak)</div>"
        }
    }

    $currentContent = if (Test-Path $devicesPath) { Get-Content -Path $devicesPath -Raw } else { '{ "devices": [] }' }
    # Injection dans un <script> : neutralise '<' pour empêcher toute fermeture prématurée du tag
    $jsonForScript = $currentContent.Replace('<', '\' + 'u003c')

    # Noms des connecteurs disponibles pour le select du formulaire (jamais les secrets).
    # @() force un tableau JSON même avec un seul connecteur (le retour de fonction déroule les tableaux)
    $connectorsJson = ConvertTo-Json -InputObject @(Get-ConnectorNames) -Compress

    return @"
$message
<script type="application/json" id="devicesData">$jsonForScript</script>
<script type="application/json" id="connectorsData">$connectorsJson</script>
<form method='POST' action='/admin/devices' id='devicesForm'>
    <input type='hidden' name='csrf' value='$($session.Csrf)'>
    <input type='hidden' name='devicesJson' id='devicesJson'>
</form>

<div id='deviceManager'>
    <div class='card' id='deviceFormCard'>
        <h2 id='deviceFormTitle'>Ajouter un équipement</h2>
        <div class='form-grid'>
            <div class='form-group'>
                <label for='devName'>Nom</label>
                <input type='text' id='devName' class='input' placeholder='SW_PROD_1'>
            </div>
            <div class='form-group'>
                <label for='devIp'>Adresse IP</label>
                <input type='text' id='devIp' class='input' placeholder='192.168.2.1'>
            </div>
            <div class='form-group'>
                <label for='devSite'>Site</label>
                <select id='devSite' class='select'></select>
                <input type='text' id='devSiteNew' class='input combo-new' placeholder='Nom du nouveau site' style='display:none;'>
            </div>
            <div class='form-group'>
                <label for='devType'>Type</label>
                <select id='devType' class='select'></select>
                <input type='text' id='devTypeNew' class='input combo-new' placeholder='Nom du nouveau type' style='display:none;'>
            </div>
            <div class='form-group'>
                <label for='devConnector'>Connecteur <span class='label-hint'>— obligatoire, géré dans <a href='/admin/connectors'>Connecteurs</a></span></label>
                <select id='devConnector' class='select'></select>
            </div>
        </div>
        <div class='form-group'>
            <label for='devCommands'>Commandes <span class='label-hint'>— une par ligne, \n pour un saut de ligne au sein d'une même commande</span></label>
            <textarea id='devCommands' class='textarea-code textarea-commands' spellcheck='false' placeholder='no page&#10;show running-config'></textarea>
        </div>
        <div id='deviceFormError' class='notice notice-error' style='display:none;'></div>
        <div class='form-actions'>
            <button type='button' class='btn btn-primary' id='deviceFormSubmit' onclick='submitDeviceForm()'>Ajouter</button>
            <button type='button' class='btn btn-secondary' id='deviceFormCancel' onclick='cancelDeviceEdit()' style='display:none;'>Annuler</button>
        </div>
    </div>

    <div class='page-head' id='deviceListHead'>
        <h2>Équipements <span class='badge' id='deviceCount'></span></h2>
    </div>
    <div id='deviceList'></div>

    <details class='json-preview card'>
        <summary>Aperçu du JSON qui sera enregistré</summary>
        <pre id='devicesPreview'></pre>
    </details>

    <div class='save-bar'>
        <span id='dirtyIndicator' class='dirty-indicator' style='visibility:hidden;'>● Modifications non enregistrées</span>
        <button type='button' class='btn btn-primary' onclick='saveDevices()'>Enregistrer les modifications</button>
    </div>
</div>
"@
}

function Handle-AdminLogs {
    $logPath = "/var/log/backup.log"

    $logContent = if (Test-Path $logPath) {
        [System.Web.HttpUtility]::HtmlEncode(((Get-Content -Path $logPath -Tail 200) -join "`n"))
    } else {
        "Aucun log disponible pour le moment."
    }

    return @"
<div class='page-head'>
    <h2>backup.log <span class='badge'>200 dernières lignes</span></h2>
    <a class='btn btn-secondary btn-sm' href='/admin/logs'>Rafraîchir</a>
</div>
<pre class='terminal'>$logContent</pre>
"@
}

function Handle-AdminBackup {
    param(
        [string]$method,
        [hashtable]$postParams,
        $session
    )

    if ($method -ne 'POST' -or $postParams['csrf'] -ne $session.Csrf) {
        return @{ Body = "<div class='notice notice-error'>Requête invalide</div>"; StatusCode = 400 }
    }

    $deviceName = $postParams['device']
    if ($deviceName) {
        # Nom validé contre devices.json + charset sûr : il est ensuite interpolé dans une commande shell
        $knownDevices = @()
        try {
            $knownDevices = @((Get-Content "$PSScriptRoot/../devices.json" -Raw | ConvertFrom-Json).devices | ForEach-Object { $_.Name })
        } catch {}
        if ($knownDevices -notcontains $deviceName -or $deviceName -notmatch '^[A-Za-z0-9._-]{1,64}$') {
            return @{ Body = "<div class='notice notice-error'>Équipement inconnu</div>"; StatusCode = 400 }
        }

        Start-Process -FilePath "/bin/sh" -ArgumentList "-c `"pwsh /app/Backup-Network.ps1 -Verbose -DeviceName '$deviceName' >> /var/log/backup.log 2>&1`"" | Out-Null

        $encName = [System.Web.HttpUtility]::HtmlEncode($deviceName)
        return @"
<div class='notice notice-success'>Backup de <strong>$encName</strong> lancé en arrière-plan, consultez les <a href='/admin/logs'>journaux</a> dans quelques instants.</div>
<a class='btn btn-secondary' href='/conf'>← Retour aux configurations</a>
"@
    }

    # Sans équipement : backup complet (plus proposé dans l'UI, conservé pour compatibilité)
    Start-Process -FilePath "/bin/sh" -ArgumentList '-c "pwsh /app/Backup-Network.ps1 -Verbose >> /var/log/backup.log 2>&1"' | Out-Null

    return @"
<div class='notice notice-success'>Backup complet lancé en arrière-plan, consultez les <a href='/admin/logs'>journaux</a> dans quelques instants.</div>
<a class='btn btn-secondary' href='/conf'>← Retour aux configurations</a>
"@
}
