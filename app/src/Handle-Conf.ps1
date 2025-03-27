## Imports des modules nécessaires
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
        [string]$currentRevision
    )

    return @"
<div class=\"revision-section\" style=\"margin: 20px 0; padding: 15px; background: #f5f5f5; border-radius: 5px;\">
    <div class=\"revision-controls\" style=\"margin-bottom: 15px;\">
        <label for=\"revisionSelect\">Consulter la révision :</label>
        <select id=\"revisionSelect\" style=\"margin: 0 10px; padding: 5px;\">
            <option value=\"\">Sélectionner une révision</option>
            <option value=\"$($currentRevision - 3)\">$($currentRevision - 3)</option>
            <option value=\"$($currentRevision - 2)\">$($currentRevision - 2)</option>
            <option value=\"$($currentRevision - 1)\">$($currentRevision - 1)</option>
            <option value=\"$currentRevision\" selected>$currentRevision (actuelle)</option>
        </select>
        <button onclick=\"showRevision(this)\" style=\"padding: 5px 10px; margin-right: 10px;\">Voir le contenu</button>
    </div>
    <div id=\"revisionContent\" style=\"display: none; margin-top: 15px;\">
        <h3 id=\"revisionTitle\" style=\"margin-bottom: 10px;\"></h3>
        <pre id=\"revisionData\" style=\"background: white; padding: 15px; border: 1px solid #ddd; border-radius: 3px;\"></pre>
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

function filterConfigs() {
    let value = document.getElementById("filterSelect").value;
    let allTabs = document.querySelectorAll(".tabcontent");
    allTabs.forEach(tab => {
        if (value === "all") {
            tab.style.display = "block";
        } else {
            if (tab.classList.contains(value)) {
                tab.style.display = "block";
            } else {
                tab.style.display = "none";
            }
        }
    });
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
        $currentRev = (svn info $config.Path | Select-String "Last Changed Rev: (\d+)").Matches.Groups[1].Value
        $content = Get-ConfigContent -Rev $config.Revision -File $config.Path

        $siteClass = "site-$($config.Site)"
        $typeClass = "type-$($config.Type)"

        @"
<div id='$($config.Name)' class='tabcontent $siteClass $typeClass'>
    <h2>$($config.Name) (Latest rev : $currentRev)</h2>
    $(Get-RevisionSelector -currentRevision $currentRev)
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
