function Handle-Diff {
    param(
        $parameters
    )

    $backupPath = (Join-Path $(Split-Path -parent $PSScriptRoot) "NetworkBackups")
    $configsPath = Join-Path $backupPath "configs"

    if (-not (Test-Path $configsPath)) {
        throw "Chemin de configuration inexistant: $configsPath"
    }

    $diffContent = (svn diff -r 1:HEAD /app/NetworkBackups/configs/SW_PROD_1 | Out-String)


    # if ($configs.Count -eq 0) {
    #     return "<h1>Aucune configuration trouvée</h1>"
    # }

    Write-Host $parameters



    return @"
<div style='margin-top: 20px;'>
    <h2>Résultat du diff</h2>
    <button onclick='window.location.href="/conf"' style='padding: 10px 15px; font-size: 14px;'>⬅️ Retour</button>
</div>
<pre>$diffContent</pre>

"@
}
