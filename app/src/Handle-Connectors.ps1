# Gestion des connecteurs d'authentification : couples identifiant/mot de passe ou clés SSH.
# Stockage sur le même modèle que credentials.xml : Export-Clixml dans /app/secrets/connectors.xml
# (fichier en 600, dossier montable en volume), avec tous les secrets — mots de passe, clés
# privées, passphrases — en SecureString. Aucune clé n'est écrite en clair sur le disque :
# Backup-Network.ps1 la matérialise en tmpfs uniquement le temps de la connexion.
# Les secrets ne sont jamais renvoyés au navigateur.

$script:SecretsDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".." "secrets"))
$script:ConnectorsPath = Join-Path $script:SecretsDir "connectors.xml"
$script:LegacyConnectorsPath = Join-Path $script:SecretsDir "connectors.json"
$script:LegacyKeysDir = Join-Path $script:SecretsDir "keys"

function Initialize-SecretsDir {
    if (-not (Test-Path $script:SecretsDir)) {
        New-Item -ItemType Directory -Path $script:SecretsDir -Force | Out-Null
    }
    chmod 700 $script:SecretsDir
}

function ConvertTo-SecureSecret {
    param([string]$plain)

    if (-not $plain) { return $null }
    return (ConvertTo-SecureString $plain -AsPlainText -Force)
}

# Migration du format v1 (connectors.json + clés en fichiers, secrets en clair) vers connectors.xml
function Convert-LegacyConnectorStore {
    if (-not (Test-Path $script:LegacyConnectorsPath)) { return }

    Write-Warning "Migration des connecteurs vers le stockage clixml (SecureString)..."
    $legacy = $null
    try {
        $legacy = (Get-Content $script:LegacyConnectorsPath -Raw | ConvertFrom-Json).connectors
    } catch {
        Write-Warning "connectors.json illisible, migration ignorée : $($_.Exception.Message)"
        return
    }

    $migrated = @()
    foreach ($connector in $legacy) {
        if ($connector.Type -eq 'sshkey') {
            $keyContent = if ($connector.KeyFile -and (Test-Path $connector.KeyFile)) {
                Get-Content $connector.KeyFile -Raw
            } else { $null }
            if (-not $keyContent) {
                Write-Warning "Clé du connecteur '$($connector.Name)' introuvable, connecteur ignoré"
                continue
            }
            $migrated += [pscustomobject]@{
                Name       = $connector.Name
                Type       = 'sshkey'
                Username   = $connector.Username
                KeyContent = ConvertTo-SecureSecret $keyContent
                Passphrase = ConvertTo-SecureSecret $connector.Passphrase
            }
        } else {
            $migrated += [pscustomobject]@{
                Name     = $connector.Name
                Type     = 'password'
                Username = $connector.Username
                Password = ConvertTo-SecureSecret $connector.Password
            }
        }
    }

    Save-ConnectorStore -connectors $migrated
    Remove-Item $script:LegacyConnectorsPath -Force
    if (Test-Path $script:LegacyKeysDir) { Remove-Item $script:LegacyKeysDir -Recurse -Force }
    Write-Warning "Migration terminée : $(@($migrated).Count) connecteur(s) dans connectors.xml"
}

function Import-ConnectorStore {
    if (-not (Test-Path $script:ConnectorsPath) -and (Test-Path $script:LegacyConnectorsPath)) {
        Convert-LegacyConnectorStore
    }

    if (-not (Test-Path $script:ConnectorsPath)) { return }

    $imported = $null
    try {
        $imported = Import-Clixml -Path $script:ConnectorsPath
    } catch {
        Write-Warning "connectors.xml illisible : $($_.Exception.Message)"
        return
    }

    # Format courant : objet racine unique avec une propriété 'connectors' (comme credentials.xml).
    # Compat : anciens fichiers dont la racine est directement le tableau — Import-Clixml peut alors
    # renvoyer la collection comme UN seul objet (selon la version de PowerShell), d'où le dépliage explicite.
    if ($imported -and $imported.PSObject.Properties.Name -contains 'connectors') {
        foreach ($item in $imported.connectors) { $item }
    } else {
        foreach ($item in @($imported)) {
            if ($item -is [System.Collections.ICollection]) {
                foreach ($sub in $item) { $sub }
            } else {
                $item
            }
        }
    }
}

function Save-ConnectorStore {
    param($connectors)

    Initialize-SecretsDir
    # Objet racine unique : évite les ambiguïtés de sérialisation des tableaux entre versions de PowerShell
    $wrapper = [pscustomobject]@{ connectors = @($connectors) }
    Export-Clixml -Path $script:ConnectorsPath -InputObject $wrapper -Depth 5
    chmod 600 $script:ConnectorsPath
}

function Get-ConnectorNames {
    return @(Import-ConnectorStore | ForEach-Object { $_.Name })
}

# Équipements référençant chaque connecteur (information + garde-fou de suppression)
function Get-ConnectorUsage {
    $usage = @{}
    $devicesPath = "$PSScriptRoot/../devices.json"
    if (Test-Path $devicesPath) {
        try {
            $devices = (Get-Content $devicesPath -Raw | ConvertFrom-Json).devices
            foreach ($device in $devices) {
                if ($device.Connector) {
                    if (-not $usage.ContainsKey($device.Connector)) { $usage[$device.Connector] = @() }
                    $usage[$device.Connector] += $device.Name
                }
            }
        } catch {
            Write-Warning "devices.json illisible pour le calcul d'usage des connecteurs"
        }
    }
    return $usage
}

function Save-Connector {
    param([hashtable]$postParams)

    $name = ($postParams['name'] ?? '').Trim()
    $type = $postParams['type']
    $username = ($postParams['username'] ?? '').Trim()
    $password = $postParams['password']
    $keyContent = $postParams['key']
    $passphrase = $postParams['passphrase']

    if ($name -notmatch '^[A-Za-z0-9._-]{1,50}$') {
        return "<div class='notice notice-error'>Nom invalide : lettres, chiffres, points, tirets et underscores uniquement (50 caractères max).</div>"
    }
    if ($type -notin @('password', 'sshkey')) {
        return "<div class='notice notice-error'>Type d'authentification invalide.</div>"
    }
    if (-not $username) {
        return "<div class='notice notice-error'>L'identifiant est obligatoire.</div>"
    }

    $connectors = @(Import-ConnectorStore)
    $existing = $connectors | Where-Object { $_.Name -eq $name } | Select-Object -First 1

    if ($type -eq 'password') {
        if ($password) {
            $securePassword = ConvertTo-SecureSecret $password
        } elseif ($existing -and $existing.Type -eq 'password' -and $existing.Password) {
            $securePassword = $existing.Password   # champ vide lors d'une modification = mot de passe conservé
        } else {
            return "<div class='notice notice-error'>Le mot de passe est obligatoire.</div>"
        }
        $connector = [pscustomobject]@{ Name = $name; Type = 'password'; Username = $username; Password = $securePassword }
    } else {
        if ($keyContent) {
            if ($keyContent -notmatch '-----BEGIN [A-Z ]*PRIVATE KEY-----') {
                return "<div class='notice notice-error'>La clé fournie ne ressemble pas à une clé privée (bloc BEGIN ... PRIVATE KEY attendu).</div>"
            }
            $normalized = ($keyContent -replace "`r`n", "`n").TrimEnd() + "`n"
            $secureKey = ConvertTo-SecureSecret $normalized
        } elseif ($existing -and $existing.Type -eq 'sshkey' -and $existing.KeyContent) {
            $secureKey = $existing.KeyContent      # champ vide lors d'une modification = clé conservée
        } else {
            return "<div class='notice notice-error'>La clé privée est obligatoire.</div>"
        }
        $connector = [pscustomobject]@{ Name = $name; Type = 'sshkey'; Username = $username; KeyContent = $secureKey; Passphrase = (ConvertTo-SecureSecret $passphrase) }
    }

    $connectors = @($connectors | Where-Object { $_.Name -ne $name }) + $connector
    Save-ConnectorStore -connectors $connectors

    $verb = if ($existing) { "mis à jour" } else { "créé" }
    return "<div class='notice notice-success'>Connecteur « $name » $verb.</div>"
}

function Remove-Connector {
    param([string]$name)

    if ($name -notmatch '^[A-Za-z0-9._-]{1,50}$') {
        return "<div class='notice notice-error'>Nom de connecteur invalide.</div>"
    }

    $usage = Get-ConnectorUsage
    if ($usage[$name]) {
        return "<div class='notice notice-error'>Impossible de supprimer « $name » : utilisé par $($usage[$name] -join ', '). Modifiez d'abord ces équipements.</div>"
    }

    $connectors = @(Import-ConnectorStore)
    $before = @($connectors).Count
    $connectors = @($connectors | Where-Object { $_.Name -ne $name })
    if (@($connectors).Count -eq $before) {
        return "<div class='notice notice-error'>Connecteur « $name » introuvable.</div>"
    }
    Save-ConnectorStore -connectors $connectors

    return "<div class='notice notice-success'>Connecteur « $name » supprimé.</div>"
}

function Handle-AdminConnectors {
    param(
        [string]$method,
        [hashtable]$postParams,
        $session
    )

    $message = ""

    if ($method -eq 'POST') {
        if ($postParams['csrf'] -ne $session.Csrf) {
            return @{ Body = "<div class='notice notice-error'>Requête invalide (CSRF)</div>"; StatusCode = 400 }
        }

        if ($postParams['action'] -eq 'delete') {
            $message = Remove-Connector -name $postParams['name']
        } else {
            $message = Save-Connector -postParams $postParams
        }
    }

    $connectors = @(Import-ConnectorStore)
    $usage = Get-ConnectorUsage

    $rowsHtml = foreach ($connector in $connectors) {
        $encName = [System.Web.HttpUtility]::HtmlEncode($connector.Name)
        $encUser = [System.Web.HttpUtility]::HtmlEncode($connector.Username)

        $typeBadge = if ($connector.Type -eq 'sshkey') {
            "<span class='badge badge-muted'>Clé SSH</span>"
        } else {
            "<span class='badge'>Mot de passe</span>"
        }

        $secretInfo = if ($connector.Type -eq 'sshkey') { "clé privée chiffrée (connectors.xml)" } else { "●●●●●●●●" }

        $usedBadge = if ($usage[$connector.Name]) {
            $encDevices = [System.Web.HttpUtility]::HtmlEncode(($usage[$connector.Name] -join ', '))
            "<span class='badge badge-outline' title='$encDevices'>$(@($usage[$connector.Name]).Count) équipement(s)</span>"
        } else { "" }

        @"
<div class='card device-row'>
    <div class='device-row-main'>
        <div class='device-row-title'>
            <strong>$encName</strong>
            <span class='device-ip'>$encUser</span>
        </div>
        <div class='device-row-badges'>$typeBadge $usedBadge</div>
        <div class='device-row-cmds'>$secretInfo</div>
    </div>
    <div class='device-row-actions'>
        <button type='button' class='btn btn-secondary btn-sm' data-name='$encName' data-type='$($connector.Type)' data-username='$encUser' onclick='editConnector(this)'>Modifier</button>
        <form method='POST' action='/admin/connectors' onsubmit="return confirm('Supprimer le connecteur $encName ?')">
            <input type='hidden' name='csrf' value='$($session.Csrf)'>
            <input type='hidden' name='action' value='delete'>
            <input type='hidden' name='name' value='$encName'>
            <button type='submit' class='btn btn-danger btn-sm'>Supprimer</button>
        </form>
    </div>
</div>
"@
    }

    if (-not $rowsHtml) {
        $rowsHtml = "<div class='card empty-state'>Aucun connecteur pour le moment — ajoutez-en un via le formulaire ci-dessus.</div>"
    }

    return @"
$message
<div class='card' id='connectorFormCard'>
    <h2 id='connectorFormTitle'>Ajouter un connecteur</h2>
    <form method='POST' action='/admin/connectors' id='connectorForm'>
        <input type='hidden' name='csrf' value='$($session.Csrf)'>
        <input type='hidden' name='action' value='save'>
        <div class='form-grid'>
            <div class='form-group'>
                <label for='connName'>Nom</label>
                <input type='text' id='connName' name='name' class='input' placeholder='prod-admin' pattern='[A-Za-z0-9._-]{1,50}' required>
            </div>
            <div class='form-group'>
                <label for='connType'>Type d'authentification</label>
                <select id='connType' name='type' class='select' onchange='toggleConnectorFields()'>
                    <option value='password'>Identifiant + mot de passe</option>
                    <option value='sshkey'>Clé SSH</option>
                </select>
            </div>
            <div class='form-group'>
                <label for='connUsername'>Identifiant</label>
                <input type='text' id='connUsername' name='username' class='input' autocomplete='off' required>
            </div>
            <div class='form-group conn-password'>
                <label for='connPassword'>Mot de passe <span class='label-hint'>— laissez vide pour conserver l'actuel lors d'une modification</span></label>
                <input type='password' id='connPassword' name='password' class='input' autocomplete='new-password'>
            </div>
        </div>
        <div class='form-group conn-sshkey' style='display:none;'>
            <label for='connKey'>Clé privée <span class='label-hint'>— format PEM/OpenSSH ; laissez vide pour conserver l'actuelle lors d'une modification</span></label>
            <textarea id='connKey' name='key' class='textarea-code textarea-commands' spellcheck='false' placeholder='-----BEGIN OPENSSH PRIVATE KEY-----'></textarea>
        </div>
        <div class='form-group conn-sshkey' style='display:none;'>
            <label for='connPassphrase'>Passphrase <span class='label-hint'>— optionnelle</span></label>
            <input type='password' id='connPassphrase' name='passphrase' class='input' autocomplete='new-password'>
        </div>
        <div class='form-actions'>
            <button type='submit' class='btn btn-primary' id='connectorFormSubmit'>Ajouter</button>
            <button type='button' class='btn btn-secondary' id='connectorFormCancel' onclick='resetConnectorForm()' style='display:none;'>Annuler</button>
        </div>
    </form>
</div>

<div class='page-head' id='deviceListHead'>
    <h2>Connecteurs <span class='badge'>$(@($connectors).Count)</span></h2>
</div>
$($rowsHtml -join "`n")

<p class='hint'>Les connecteurs sont stockés comme <code>credentials.xml</code> : secrets en SecureString via clixml dans
<code>/app/secrets/connectors.xml</code> (fichier en 600, montez <code>/app/secrets</code> en volume pour la persistance).
Les clés privées ne sont jamais écrites en clair sur le disque : elles sont matérialisées en tmpfs le temps de la connexion SSH.
Chaque équipement doit référencer un connecteur (champ Connecteur du formulaire Équipements).</p>
"@
}
