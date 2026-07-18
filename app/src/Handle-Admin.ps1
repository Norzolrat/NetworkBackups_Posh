function Handle-AdminDashboard {
    param(
        $session
    )

    return @"
<div class='card-grid'>
    <a class='card action-card' href='/admin/devices'>
        <svg xmlns='http://www.w3.org/2000/svg' width='22' height='22' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><line x1='8' y1='6' x2='21' y2='6'></line><line x1='8' y1='12' x2='21' y2='12'></line><line x1='8' y1='18' x2='21' y2='18'></line><line x1='3' y1='6' x2='3.01' y2='6'></line><line x1='3' y1='12' x2='3.01' y2='12'></line><line x1='3' y1='18' x2='3.01' y2='18'></line></svg>
        <h3>Équipements</h3>
        <p>Visualiser et éditer devices.json (une sauvegarde .bak est faite avant chaque écriture).</p>
    </a>
    <a class='card action-card' href='/admin/connectors'>
        <svg xmlns='http://www.w3.org/2000/svg' width='22' height='22' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0l3 3L22 7l-3-3m-3.5 3.5L19 4'></path></svg>
        <h3>Connecteurs</h3>
        <p>Gérer les identifiants et clés SSH utilisés pour se connecter aux équipements.</p>
    </a>
    <a class='card action-card' href='/admin/logs'>
        <svg xmlns='http://www.w3.org/2000/svg' width='22' height='22' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z'></path><polyline points='14 2 14 8 20 8'></polyline><line x1='16' y1='13' x2='8' y2='13'></line><line x1='16' y1='17' x2='8' y2='17'></line></svg>
        <h3>Journaux</h3>
        <p>Consulter les dernières lignes de backup.log (détail complet des runs cron et manuels).</p>
    </a>
    <a class='card action-card' href='/conf'>
        <svg xmlns='http://www.w3.org/2000/svg' width='22' height='22' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><rect x='2' y='2' width='20' height='8' rx='2' ry='2'></rect><rect x='2' y='14' width='20' height='8' rx='2' ry='2'></rect><line x1='6' y1='6' x2='6.01' y2='6'></line><line x1='6' y1='18' x2='6.01' y2='18'></line></svg>
        <h3>Configurations</h3>
        <p>Parcourir les configurations sauvegardées et leurs révisions SVN.</p>
    </a>
    <div class='card action-card'>
        <svg xmlns='http://www.w3.org/2000/svg' width='22' height='22' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><polygon points='13 2 3 14 12 14 11 22 21 10 12 10 13 2'></polygon></svg>
        <h3>Backup manuel</h3>
        <p>Lance Backup-Network.ps1 en arrière-plan, détail dans les journaux.</p>
        <form method='POST' action='/admin/backup'>
            <input type='hidden' name='csrf' value='$($session.Csrf)'>
            <button type='submit' class='btn btn-primary'>Lancer un backup</button>
        </form>
    </div>
</div>
<p class='hint'>Cette page sera enrichie plus tard (statistiques, état du cron, alertes...).</p>
"@
}

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
    <div>
        <a class='btn btn-secondary btn-sm' href='/admin/logs'>Rafraîchir</a>
        <a class='btn btn-secondary btn-sm' href='/admin'>← Vue d'ensemble</a>
    </div>
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

    Start-Process -FilePath "/bin/sh" -ArgumentList '-c "pwsh /app/Backup-Network.ps1 -Verbose >> /var/log/backup.log 2>&1"' | Out-Null

    return @"
<div class='notice notice-success'>Backup lancé en arrière-plan, consultez les <a href='/admin/logs'>journaux</a> dans quelques instants.</div>
<a class='btn btn-secondary' href='/admin'>← Vue d'ensemble</a>
"@
}
