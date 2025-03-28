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

    $diff_verison = $parameters['rev']
    $diff_path = "$($configsPath)/$($parameters['device'])"
    $diffContent = (svn diff -r "$($diff_verison):HEAD" $diff_path | Out-String)
 $diffLines = $diffRaw -split "`n"

    $styled = @"<style>
.diff-line     { font-family: monospace; white-space: pre-wrap; padding: 2px 10px; }
.diff-context  { background-color: #f8f9fa; }
.diff-added    { background-color: #d4edda; color: #155724; }
.diff-removed  { background-color: #f8d7da; color: #721c24; }
.diff-header   { background-color: #e2e3e5; font-weight: bold; }
</style>"@

    $styledLines = foreach ($line in $diffLines) {
        $escaped = [System.Web.HttpUtility]::HtmlEncode($line)
        switch -regex ($line) {
            '^@@'        { "<div class='diff-line diff-header'>$escaped</div>" }
            '^\+\+\+'    { "<div class='diff-line diff-header'>$escaped</div>" }
            '^---'       { "<div class='diff-line diff-header'>$escaped</div>" }
            '^\+'        { "<div class='diff-line diff-added'>$escaped</div>" }
            '^\-'        { "<div class='diff-line diff-removed'>$escaped</div>" }
            default      { "<div class='diff-line diff-context'>$escaped</div>" }
        }
    }

    return @"
$styled
<div style='margin-top: 20px;'>
    <h2>Résultat du diff pour <code>$($parameters['device'])</code> (r$diff_version → HEAD)</h2>
    <button onclick=\"window.location.href='/conf'\" style=\"padding: 10px 15px; font-size: 14px;\">⬅️ Retour</button>
    <div style='border:1px solid #ccc; border-radius:5px; overflow-x:auto; margin-top: 20px;'>
        $($styledLines -join "`n")
    </div>
</div>
"@
}
