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
        [int]$revisionCount = 10
    )

    $revisionOptions = @()
    $minRevision = [Math]::Max(1, $currentRevision - $revisionCount)

    for ($i = $currentRevision; $i -ge $minRevision; $i--) {
        if ($i -eq $currentRevision) {
            $revisionOptions += "<option value='$i' selected>$i (actuelle)</option>"
        } else {
            $revisionOptions += "<option value='$i'>$i</option>"
        }
    }

    return @"
<div class='revision-section' style='margin: 20px 0; padding: 15px; background: #f5f5f5; border-radius: 5px;'>
    <div class='revision-controls' style='margin-bottom: 15px;'>
        <label for='revisionSelect'>Consulter la révision :</label>
        <select id='revisionSelect' style='margin: 0 10px; padding: 5px;'>
            <option value=''>Sélectionner une révision</option>
            $($revisionOptions -join "`n")
        </select>
        <button onclick='showRevision(this)' style='padding: 5px 10px; margin-right: 10px;'>Voir le contenu</button>
        <button onclick='diffRevision(this)' style='padding: 5px 10px; margin-right: 10px;'>Voir les différences</button>
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
    //let rev_sel = button.closest('.revision-section');
    //let parentid = rev_sel.parentElement.id;
    //let rev = rev_sel.querySelector('#revisionSelect').value;
    //if (!rev) return;
    //window.location.href = "/diff?"+parentid"="+rev;
    window.location.href = "/diff";
    console.log("toto");
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
<div style='margin-bottom: 15px;'>
    <label for='filterSelect'>Filtrer par :</label>
    <select id='filterSelect' onchange='filterConfigs()'>
        <option value='all'>Tous</option>
        <optgroup label='Sites'>
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
    <h2>$($config.Name) (Latest rev : $currentRev)</h2>
    $(Get-RevisionSelector -currentRevision $currentRev -revisionCount 10)
    <div class='content' id="cnt_$($config.Name)">
        <pre>$content</pre>
    </div>
</div>
"@
    }

    return @"
$filterHtml
<div class='tab'>
    $tabButtons
</div>
$tabContents
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
