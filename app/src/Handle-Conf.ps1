
<# Imports of modules  to use #>
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

function Get-ConfigDiff {
    param(
        [string]$File,
        [string]$Rev
    )
    if (-not (Test-Path $File)) {
        throw "Chemin de configuration inexistant: $File"
    }
    return $(svn diff -r $Rev:HEAD $File)
}

function Get-RevisionSelector {
    param(
        [string]$currentRevision
    )

    return @"
<div class="revision-section" style="margin: 20px 0; padding: 15px; background: #f5f5f5; border-radius: 5px;">
    <div class="revision-controls" style="margin-bottom: 15px;">
        <label for="revisionSelect">Consulter la révision :</label>
        <select id="revisionSelect" style="margin: 0 10px; padding: 5px;">
            <option value="">Sélectionner une révision</option>
            <option value="$($currentRevision - 3)">$($currentRevision - 3)</option>
            <option value="$($currentRevision - 2)">$($currentRevision - 2)</option>
            <option value="$($currentRevision - 1)">$($currentRevision - 1)</option>
            <option value="$currentRevision" selected>$currentRevision (actuelle)</option>
        </select>
        <button onclick="showRevision(this)" style="padding: 5px 10px; margin-right: 10px;">Voir le contenu</button>
        <!--<button onclick="showDiff()" style="padding: 5px 10px;">Voir les différences</button>-->
    </div>
    <div id="revisionContent" style="display: none; margin-top: 15px;">
        <h3 id="revisionTitle" style="margin-bottom: 10px;"></h3>
        <pre id="revisionData" style="background: white; padding: 15px; border: 1px solid #ddd; border-radius: 3px;"></pre>
    </div>
</div>

<script>
function showRevision(button) {
    let rev_sel = button .closest('.revision-section');
    let parentid = rev_sel.parentElement.id;
    let rev = rev_sel.querySelector('#revisionSelect').value;
    if (!rev) return;
    let url = window.location.href;
    if(url.includes("?")){
        if(url.includes(parentid)) {
            window.location.href = url.replace(new RegExp(parentid + "=\\d+(&|$)"), parentid + "=" + rev + "$1");
        }else {
            window.location.href = url + "&"+parentid+"="+rev;
        }
    }else {
        window.location.href = url + "?"+parentid+"="+rev;
    }
}

function showDiff() {
    // Todo
}
</script>
"@
}

function Handle-Conf {
    param(
        $parameters
        )
    # Chemins
    $backupPath = (Join-Path $(Split-Path -parent $PSScriptRoot) "NetworkBackups")
    $configsPath = Join-Path $backupPath "configs"

    # Vérification du chemin
    if (-not (Test-Path $configsPath)) {
        throw "Chemin de configuration inexistant: $configsPath"
    }

    # Récupération des fichiers
    $configs = @{}
    Get-ChildItem -Path $configsPath -File | ForEach-Object {
        $filePath = $_.FullName
        $fileName = $_.Name
        
        # Récupération de la révision SVN
        $revision = (svn info $filePath | Select-String "Last Changed Rev: (\d+)").Matches.Groups[1].Value
        
        # Ajout des informations dans le hashtable
        $configs[$fileName] = @{
            'Name' = $fileName
            'Path' = $filePath
            'Revision' = $revision
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

    # Génération des boutons d'onglets
    $tabButtons = $configs.Keys | ForEach-Object {
        $config = $configs[$_]
        "<button class='tablinks' onclick='openConfig(event, `"$($config.Name)`")'>$($config.Name)</button>"
    }
    
    # Génération du contenu des onglets
    $tabContents = $configs.Keys | ForEach-Object {
        $config = $configs[$_]
        $currentRev = (svn info $config.Path | Select-String "Last Changed Rev: (\d+)").Matches.Groups[1].Value
        $content = Get-ConfigContent -Rev $config.Revision -File $config.Path

        @"
        <div id='$($config.Name)' class='tabcontent'>
            <h2>$($config.Name) (Latest rev : $currentRev)</h2>
            $(Get-RevisionSelector -currentRevision $currentRev)
            <div class='content' id="cnt_$($config.Name)">
                <pre>$content</pre>
            </div>
        </div>
"@
    }
    
    return @"
    <!--<h1>Configurations</h1>-->
    <div class="tab">
        $tabButtons
    </div>
    $tabContents
    <script>
        function openConfig(evt, configName) {
            // Masquer tous les contenus d'onglets
            const tabcontents = document.getElementsByClassName("tabcontent");
            Array.from(tabcontents).forEach(tab => tab.style.display = "none");
            
            // Retirer la classe active de tous les boutons
            const tablinks = document.getElementsByClassName("tablinks");
            Array.from(tablinks).forEach(link => link.className = link.className.replace(" active", ""));
            
            // Afficher l'onglet sélectionné et activer le bouton
            const selectedTab = document.getElementById(configName);
            if (selectedTab) {
                selectedTab.style.display = "block";
                evt.currentTarget.className += " active";
            }
        }
        
        // Ouvrir le premier onglet par défaut
        const firstTab = document.getElementsByClassName("tablinks")[0];
        if (firstTab) {
            firstTab.click();
        }
        
        // Rafraîchir la page toutes les 60 secondes
        const refreshInterval = 60000; // 60 secondes
        setInterval(() => {
            location.reload();
        }, refreshInterval);
    </script>
"@
}
