function Handle-Diff {
    param(
        $parameters
    )

    $backupPath = (Join-Path $(Split-Path -parent $PSScriptRoot) "NetworkBackups")
    $configsPath = Join-Path $backupPath "configs"

    if (-not (Test-Path $configsPath)) {
        throw "Chemin de configuration inexistant: $configsPath"
    }

    if ($parameters.Count -eq 0) {
         return @"
    <h1>Aucune configuration trouvée</h1><br><button onclick='window.location.href="/conf"' style='padding: 10px 15px; font-size: 14px;'>⬅️ Retour</button>
"@
    }

    $diff_verison = $parameters[1]
    $diff_path = "$($configsPath)/$($parameters[0])"
    Write-Host $parameters.GetType().FullName
    Write-Host $parameters
    Write-Host $diff_verison
    Write-Host $diff_path

    $diffContent = (svn diff -r "$diff_verison":HEAD "$diff_path" | Out-String)

    return @"
<div style='margin-top: 20px;'>
    <h2>Résultat du diff</h2>
    <button onclick='window.location.href="/conf"' style='padding: 10px 15px; font-size: 14px;'>⬅️ Retour</button>
</div>
<pre>$diffContent</pre>

"@
}
