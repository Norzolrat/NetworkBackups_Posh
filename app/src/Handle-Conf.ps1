. "/app/src/Utils"

function Get-ConfigContent {
    param(
        [string]$File,
        [string]$Rev
    )
    if (-not (Test-Path $File)) {
        throw "Chemin de configuration inexistant: $File"
    }
    $content = $(svn cat -r $Rev $File | Out-String)
    return $content
}

function Get-RevisionSelector {
    param(
        [int]$currentRevision,
        [int]$maxTryCount = 100,
        [int]$revisionCount = 10,
        [string]$fileName
    )

    $filePath = "/app/NetworkBackups/configs/" + $fileName

    $revisionOptions = @()
    $minRevision = [Math]::Max(1, $currentRevision - $maxTryCount)

    $i = $currentRevision
    $nbRevShown = 0

    while ($i -ge $minRevision -and $revisionCount -ge $nbRevShown) {
        $nbRevShown++
        $rev_date = $(svn log -r $i $filePath | Select-String -Pattern "\| ([\d-]+ [\d:]+)" | ForEach-Object { $_.Matches.Groups[1].Value })
        if ($rev_date) {
            $suffix = if ($i -eq $currentRevision) { "  (actuelle)" } else { "" }
            $revisionOptions += "<option value='$i'>$rev_date$suffix</option>"
        }
        $i--
    }

    return @"
<div class='revision-section'>
    <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <circle cx="12" cy="12" r="10"></circle>
        <polyline points="12 6 12 12 16 14"></polyline>
    </svg>
    <label for='revisionSelect'>Révision</label>
    <select id='revisionSelect' class='select select-sm' onchange='showRevision(this)'>
        <option value=''>Version actuelle</option>
        $($revisionOptions -join "`n")
    </select>
    <span class='rev-status' style='display:none;'></span>
    <button class='btn btn-secondary btn-sm' onclick='diffRevision(this)'>Voir les différences</button>
    <button class='btn btn-secondary btn-sm' onclick='downloadConfig(this)' title='Télécharger la configuration affichée'>
        <svg xmlns='http://www.w3.org/2000/svg' width='14' height='14' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4'></path><polyline points='7 10 12 15 17 10'></polyline><line x1='12' y1='15' x2='12' y2='3'></line></svg>
        Télécharger
    </button>
</div>
"@
}

# API texte brut : contenu d'une configuration à une révision donnée (HEAD si omise).
# Consommé en fetch() par la page /conf pour changer de révision sans recharger.
function Handle-ConfContent {
    param(
        $parameters
    )

    $backupPath = (Join-Path $(Split-Path -parent $PSScriptRoot) "NetworkBackups")
    $configsPath = Join-Path $backupPath "configs"

    $device = $parameters['device']
    $rev = $parameters['rev']

    if ($rev -and $rev -notmatch '^\d+$') {
        return @{ Raw = "Révision invalide"; StatusCode = 400 }
    }

    $filePath = Join-Path $configsPath $device
    $resolvedTarget = [System.IO.Path]::GetFullPath($filePath)
    $resolvedRoot = [System.IO.Path]::GetFullPath($configsPath)

    if (-not $device -or -not (Test-Path $filePath -PathType Leaf) -or -not $resolvedTarget.StartsWith($resolvedRoot + [System.IO.Path]::DirectorySeparatorChar)) {
        return @{ Raw = "Équipement invalide"; StatusCode = 400 }
    }

    $revArg = if ($rev) { $rev } else { 'HEAD' }
    $result = @{ Raw = (Get-ConfigContent -Rev $revArg -File $resolvedTarget) }

    # Mode téléchargement : le navigateur enregistre le fichier au lieu de l'afficher
    if ($parameters['download']) {
        $suffix = if ($rev) { "-r$rev" } else { "" }
        $result.FileName = "$device$suffix.txt"
    }
    return $result
}


# Deux listes déroulantes indépendantes (sites et types), combinées en ET par le JS
function Get-Filter {
    $devicesData = Get-Content "$PSScriptRoot/../devices.json" | ConvertFrom-Json
    $deviceSites = @{}
    $deviceTypes = @{}

    foreach ($device in $devicesData.devices) {
        if ($device.Site) { $deviceSites[$device.Site] = $true }
        if ($device.Type) { $deviceTypes[$device.Type] = $true }
    }

    $siteOptions = ($deviceSites.Keys | Sort-Object | ForEach-Object {
        "<option value='site-$_'>$_</option>"
    }) -join "`n"

    $typeOptions = ($deviceTypes.Keys | Sort-Object | ForEach-Object {
        "<option value='type-$_'>$_</option>"
    }) -join "`n"

    return @"
<select id='filterSite' class='select select-sm' onchange='filterConfigs()'>
    <option value='all'>Tous les sites</option>
    $siteOptions
</select>
<select id='filterType' class='select select-sm' onchange='filterConfigs()'>
    <option value='all'>Tous les types</option>
    $typeOptions
</select>
"@
}

function Handle-Conf {
    param(
        $parameters,
        $session
    )

    $backupPath = (Join-Path $(Split-Path -parent $PSScriptRoot) "NetworkBackups")
    $configsPath = Join-Path $backupPath "configs"

    if (-not (Test-Path $configsPath)) {
        throw "Chemin de configuration inexistant: $configsPath"
    }

    $devicesData = Get-Content "$PSScriptRoot/../devices.json" | ConvertFrom-Json
    $deviceLookup = @{}
    foreach ($device in $devicesData.devices) {
        $deviceLookup[$device.Name] = $device
    }

    $configs = @{}
    Get-ChildItem -Path $configsPath -File | ForEach-Object {
        $filePath = $_.FullName
        $fileName = $_.Name

        $revision = (svn info $filePath | Select-String "Last Changed Rev: (\d+)").Matches.Groups[1].Value

        $configs[$fileName] = @{
            'Name' = $fileName
            'Path' = $filePath
            'Revision' = $revision
            'Site' = $deviceLookup[$fileName].Site
            'Type' = $deviceLookup[$fileName].Type
        }
    }

    if ($configs.Count -eq 0) {
        return "<h1>Aucune configuration trouvée</h1>"
    }

    $filterOptions = Get-Filter

    $tabButtons = $configs.Keys | ForEach-Object {
        $config = $configs[$_]
        "<button class='tablinks' data-target='$($config.Name)' onclick='openConfig(event, `"$($config.Name)`")'>$($config.Name)</button>"
    }

    $tabContents = $configs.Keys | ForEach-Object {
        $config = $configs[$_]
        $currentRev = [int](svn info $config.Path | Select-String "Last Changed Rev: (\d+)").Matches.Groups[1].Value
        $content = [System.Web.HttpUtility]::HtmlEncode((Get-ConfigContent -Rev $config.Revision -File $config.Path))

        $siteClass = "site-$($config.Site)"
        $typeClass = "type-$($config.Type)"

        @"
<div id='$($config.Name)' class='tabcontent $siteClass $typeClass'>
    <div class='device-head'>
        <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <rect x="2" y="2" width="20" height="8" rx="2" ry="2"></rect>
            <rect x="2" y="14" width="20" height="8" rx="2" ry="2"></rect>
            <line x1="6" y1="6" x2="6.01" y2="6"></line>
            <line x1="6" y1="18" x2="6.01" y2="18"></line>
        </svg>
        <h2>$($config.Name)</h2>
        <form method='POST' action='/admin/backup' class='device-backup' onsubmit="return confirm('Lancer un backup de $($config.Name) maintenant ?')">
            <input type='hidden' name='csrf' value='$($session.Csrf)'>
            <input type='hidden' name='device' value='$($config.Name)'>
            <button type='submit' class='btn btn-secondary btn-sm'>
                <svg xmlns='http://www.w3.org/2000/svg' width='14' height='14' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><polygon points='13 2 3 14 12 14 11 22 21 10 12 10 13 2'></polygon></svg>
                Backup manuel
            </button>
        </form>
    </div>

    $(Get-RevisionSelector -currentRevision $currentRev -revisionCount 10 -fileName $config.Name)
    <div class='content' id="cnt_$($config.Name)">
        <pre data-rev='latest'>$content</pre>
    </div>
</div>
"@
    }

    return @"
<div class='tab-row'>
    <div class='filter-inline'>
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3"></polygon>
        </svg>
        $filterOptions
    </div>
    <div class='tab'>
        $($tabButtons -join "`n")
    </div>
</div>

$($tabContents -join "`n")

<div id='noSelection' class='card empty-state' style='display:none;'>Sélectionnez un équipement dans la liste ci-dessus pour afficher sa configuration.</div>
"@

}
