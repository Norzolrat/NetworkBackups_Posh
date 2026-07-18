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
            if ($i -eq $currentRevision) {
                $revisionOptions += "<option value='$i' selected>$rev_date  (actuelle)</option>"
            } else {
                $revisionOptions += "<option value='$i'>$rev_date</option>"
            }
        }
        $i--
    }

    return @"
<div class='revision-section card'>
    <div class='revision-controls'>
        <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <circle cx="12" cy="12" r="10"></circle>
            <polyline points="12 6 12 12 16 14"></polyline>
        </svg>
        <label for='revisionSelect'>Révision</label>
        <select id='revisionSelect' class='select'>
            <option value=''>Sélectionner une révision</option>
            $($revisionOptions -join "`n")
        </select>
        <button class='btn btn-primary' onclick='showRevision(this)'>
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <circle cx="12" cy="12" r="2"></circle>
                <path d="M22 12c-2.667 4.667-6 7-10 7s-7.333-2.333-10-7c2.667-4.667 6-7 10-7s7.333 2.333 10 7"></path>
            </svg>
            Voir le contenu
        </button>
        <button class='btn btn-secondary' onclick='diffRevision(this)'>Voir les différences</button>
    </div>
    <div id='revisionContent' style='display: none;'>
        <h3 id='revisionTitle'></h3>
        <pre id='revisionData'></pre>
    </div>
</div>
"@
}


function Get-Filter {
    $devicesData = Get-Content "$PSScriptRoot/../devices.json" | ConvertFrom-Json
    $deviceSites = @{}
    $deviceBrand = @{}
    
    foreach ($device in $devicesData.devices) {
        if (-not $deviceSites.ContainsKey($device.Site)) {
            $deviceSites[$device.Site] = $device.Site
        }
        if (-not $deviceBrand.ContainsKey($device.Type)) {
            $deviceBrand[$device.Type] = $device.Type
        }
    }

    $deviceSitesHTML = ($deviceSites.Keys | Sort-Object | ForEach-Object {
        "<option value='site-$_'>$_</option>"
    }) -join "`n"

    $deviceBrandHTML = ($deviceBrand.Keys | Sort-Object | ForEach-Object {
        "<option value='type-$_'>$_</option>"
    }) -join "`n"

    return @"
<optgroup label='Sites'>
    $deviceSitesHTML
</optgroup>
<optgroup label='Types'>
    $deviceBrandHTML
</optgroup>
"@
}

function Handle-Conf {
    param(
        $parameters
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

    foreach ($key in $parameters.Keys) {
        if ($configs[$key]) {
            if ($($parameters[$key]) -match '^\d+$') {
                if ($($parameters[$key]) -lt $configs[$key]['Revision']) {
                    $configs[$key]['Revision'] = $($parameters[$key])
                }
            }
        }
    }

    $filterOptions = Get-Filter

    $filterHtml = @"
<div class='toolbar card'>
    <div class='filter-group'>
        <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3"></polygon>
        </svg>
        <label for='filterSelect'>Filtrer par</label>
        <select id='filterSelect' class='select' onchange='filterConfigs()'>
            <option value='all'>Tous</option>
            $filterOptions
        </select>
    </div>
</div>
"@

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
        <span class='badge'>Dernière rév. $currentRev</span>
    </div>

    $(Get-RevisionSelector -currentRevision $currentRev -revisionCount 10 -fileName $config.Name)
    <div class='content content-card' id="cnt_$($config.Name)">
        <pre>$content</pre>
    </div>
</div>
"@
    }

    return @"
$filterHtml
<div class='tab'>
    $($tabButtons -join "`n")
</div>

$($tabContents -join "`n")
"@

}
