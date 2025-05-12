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
        $i--
        $nbRevShown++
        $rev_date = $(svn log -r $i $filePath | Select-String -Pattern "\| ([\d-]+ [\d:]+)" | ForEach-Object { $_.Matches.Groups[1].Value })
        if ($rev_date) {
            if ($i -eq $currentRevision) {
                $revisionOptions += "<option value='$i' selected>$rev_date  (actuelle)</option>"
            } else {
                $revisionOptions += "<option value='$i'>$rev_date</option>"
            }
        }
    }

    return @"
<div class='revision-section' style='padding: 15px; background: rgb(0,40,90,50); border-radius: 5px;'>
    <div class='revision-controls'>
        <svg id="iconRevision" xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <circle cx="12" cy="12" r="10"></circle>
            <polyline points="12 6 12 12 16 14"></polyline>
        </svg>
        <label for='revisionSelect'>Consulter la révision :</label>
        <select id='revisionSelect' style='margin: 0 10px; padding: 5px;'>
            <option value=''>Sélectionner une révision</option>
            $($revisionOptions -join "`n")
        </select>
        <button id="iconBouton" onclick='showRevision(this)'>
    <svg id="iconContenu"
        xmlns="http://www.w3.org/2000/svg" 
        width="16" 
        height="16" 
        viewBox="0 0 24 24" 
        fill="none" 
        stroke="currentColor" 
        stroke-width="2" 
        stroke-linecap="round" 
        stroke-linejoin="round"
    >
        <circle cx="12" cy="12" r="2"></circle>
        <path d="M22 12c-2.667 4.667-6 7-10 7s-7.333-2.333-10-7c2.667-4.667 6-7 10-7s7.333 2.333 10 7"></path>
    </svg>
    Voir le contenu
</button>

        <button id="button" onclick='diffRevision(this)'>Voir les différences</button>
    </div>
    <div id='revisionContent' style='display: none; margin-top: 15px;'>
        <h3 id='revisionTitle' style='margin-bottom: 10px;'></h3>
        <pre id='revisionData' style='background: white; padding: 15px; border: 1px solid #ddd; border-radius: 3px;'></pre>
    </div>
</div>
<script>
function showRevision(button) {
    let rev_sel = button.closest('.revision-section');
    let parentid = rev_sel.parentElement.id;
    let rev = rev_sel.querySelector('#revisionSelect').value;
    if (!rev) return;
    let url = window.location.href;
    if(url.includes("?")){
        if(url.includes(parentid)) {
            window.location.href = url.replace(new RegExp(parentid + "=\\d+(&|$)"), parentid + "=" + rev + "$1");
        } else {
            window.location.href = url + "&"+parentid+"="+rev;
        }
    } else {
        window.location.href = url + "?"+parentid+"="+rev;
    }
}

function diffRevision(button) {
    let rev_sel = button.closest('.revision-section');
    let parentid = rev_sel.parentElement.id;
    let rev = rev_sel.querySelector('#revisionSelect').value;
    if (!rev) return;
    window.location.href = "/diff?device="+parentid+"&rev="+rev;
}

function filterConfigs() {
    let value = document.getElementById("filterSelect").value;
    let allTabs = document.querySelectorAll(".tabcontent");
    let visibleIds = [];

    allTabs.forEach(tab => {
        if (value === "all" || tab.classList.contains(value)) {
            tab.style.display = "block";
            visibleIds.push(tab.id);
        } else {
            tab.style.display = "none";
        }
    });

    let allButtons = document.querySelectorAll(".tablinks");
    allButtons.forEach(button => {
        let configName = button.textContent.trim();
        if (visibleIds.includes(configName)) {
            button.style.display = "inline-block";
        } else {
            button.style.display = "none";
        }
    });

    let activeTab = document.querySelector(".tablinks.active");
    if (!activeTab || activeTab.style.display === "none") {
        let firstVisible = document.querySelector(".tablinks:not([style*='display: none'])");
        if (firstVisible) firstVisible.click();
    }
}
</script>
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

    $filterHtml = @"
<div id="filterBar" >
    <svg id="iconFiltre" xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3"></polygon>
    </svg>
    <label id="filterLabel" for='filterSelect'>Filtrer par :</label>
    <select id='filterSelect' onchange='filterConfigs()'>
        <option value='all'>Tous</option>
        <optgroup label='Sites'>
            <!-- ajouter les bonnes informations -->
            <option value='site-Paris01'>Paris01</option>
            <option value='site-Paris14'>Paris14</option>
        </optgroup>
        <optgroup label='Types'>
            <option value='type-comware'>Comware</option>
            <option value='type-aruba'>Aruba</option>
            <option value='type-arubacx'>ArubaCX</option>
        </optgroup>
    </select>
</div>
"@

    $tabButtons = $configs.Keys | ForEach-Object {
        $config = $configs[$_]
        "<button class='tablinks' onclick='openConfig(event, `"$($config.Name)`")'>$($config.Name)</button>"
    }

    $tabContents = $configs.Keys | ForEach-Object {
        $config = $configs[$_]
        $currentRev = [int](svn info $config.Path | Select-String "Last Changed Rev: (\d+)").Matches.Groups[1].Value
        $content = Get-ConfigContent -Rev $config.Revision -File $config.Path

        $siteClass = "site-$($config.Site)"
        $typeClass = "type-$($config.Type)"

        @"
<div id='$($config.Name)' class='tabcontent $siteClass $typeClass'>
    <div id="logoH">
        <svg 
            xmlns="http://www.w3.org/2000/svg" 
            width="20" 
            height="20" 
            viewBox="0 0 24 24" 
            fill="none" 
            stroke="currentColor" 
            stroke-width="2" 
            stroke-linecap="round" 
            stroke-linejoin="round"
        >
            <rect x="2" y="2" width="20" height="8" rx="2" ry="2"></rect>
            <rect x="2" y="14" width="20" height="8" rx="2" ry="2"></rect>
            <line x1="6" y1="6" x2="6.01" y2="6"></line>
            <line x1="6" y1="18" x2="6.01" y2="18"></line>
        </svg>
        <h2>$($config.Name) (Latest rev : $currentRev)</h2>
    </div>
    
    $(Get-RevisionSelector -currentRevision $currentRev -revisionCount 10 -fileName $config.Name)
    <div class='content' id="cnt_$($config.Name)">
        <pre>$content</pre>
    </div>
</div>
"@
    }

    return @"
<div id="container">
    <div id="filter">
        $filterHtml
    </div>
    <div class='tab'>
        $($tabButtons -join "`n")
    </div>
</div>

$($tabContents -join "`n")

<script>
function openConfig(evt, configName) {
    const tabcontents = document.getElementsByClassName("tabcontent");
    Array.from(tabcontents).forEach(tab => tab.style.display = "none");

    const tablinks = document.getElementsByClassName("tablinks");
    Array.from(tablinks).forEach(link => link.className = link.className.replace(" active", ""));

    const selectedTab = document.getElementById(configName);
    if (selectedTab) {
        selectedTab.style.display = "block";
        evt.currentTarget.className += " active";
    }
}

const firstTab = document.getElementsByClassName("tablinks")[0];
if (firstTab) {
    firstTab.click();
}

setInterval(() => {
    location.reload();
}, 60000);
</script>
"@

}
