function Handle-Diff {
    param(
        $parameters
    )

    $backupPath = (Join-Path $(Split-Path -parent $PSScriptRoot) "NetworkBackups")
    $configsPath = Join-Path $backupPath "configs"

    if (-not (Test-Path $configsPath)) {
        throw "Chemin de configuration inexistant: $configsPath"
    }

    $backLink = "<a class='btn btn-secondary' href='/conf'>← Retour aux configurations</a>"

    if ($parameters.Count -eq 0) {
        return "<div class='notice notice-error'>Aucune configuration demandée</div>$backLink"
    }

    $diff_version = $parameters['rev']
    $device = $parameters['device']

    if ($diff_version -notmatch '^\d+$') {
        return "<div class='notice notice-error'>Révision invalide</div>$backLink"
    }

    $diff_path = Join-Path $configsPath $device
    $resolvedTarget = [System.IO.Path]::GetFullPath($diff_path)
    $resolvedRoot = [System.IO.Path]::GetFullPath($configsPath)

    if (-not $device -or -not (Test-Path $diff_path -PathType Leaf) -or -not $resolvedTarget.StartsWith($resolvedRoot + [System.IO.Path]::DirectorySeparatorChar)) {
        return "<div class='notice notice-error'>Équipement invalide</div>$backLink"
    }

    $diffContent = (svn diff -r "$($diff_version):HEAD" $resolvedTarget | Out-String)
    $diffLines = $diffContent -split "`n"
    $styledLines = foreach ($line in $diffLines) {
        $escapedLine = [System.Web.HttpUtility]::HtmlEncode($line)
        switch -regex ($line) {
            '^@@'        { "<div class='diff-line diff-header'>$escapedLine</div>" }
            '^\+\+\+'    { "<div class='diff-line diff-header'>$escapedLine</div>" }
            '^---'       { "<div class='diff-line diff-header'>$escapedLine</div>" }
            '^\+'        { "<div class='diff-line diff-added'>$escapedLine</div>" }
            '^\-'        { "<div class='diff-line diff-removed'>$escapedLine</div>" }
            default      { "<div class='diff-line diff-context'>$escapedLine</div>" }
        }
    }

    $escapedDevice = [System.Web.HttpUtility]::HtmlEncode($device)

    return @"
<div class='page-head'>
    <h2>$escapedDevice <span class='badge'>rév. $diff_version → HEAD</span></h2>
    $backLink
</div>
<div class='card diff-card'>
    $($styledLines -join "`n")
</div>
"@
}
