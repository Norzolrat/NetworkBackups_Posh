param(
    [string]$prefix = "http",
    [string]$addr = "localhost", 
    [string]$port = "8080"
)

<# Imports of modules  to use #>
. "/app/src/Handle-Conf"
. "/app/src/Handle-Diff"
. "/app/src/Argon2"
. "/app/src/Handle-Auth"
. "/app/src/Handle-Admin"
. "/app/src/Handle-Connectors"
. "/app/src/Utils"

# Titre de page affiché dans la barre supérieure et l'onglet navigateur
function Get-PageTitle {
    param([string]$path)

    switch ($path) {
        "/conf"          { "Configurations" }
        "/diff"          { "Différences" }
        "/admin"         { "Administration" }
        "/admin/devices" { "Équipements" }
        "/admin/connectors" { "Connecteurs" }
        "/admin/logs"    { "Journaux de backup" }
        "/admin/backup"  { "Backup manuel" }
        "/login"         { "Connexion" }
        default          { "NetBackup" }
    }
}

# Entrée de la sidebar, marquée active selon la route courante
function Get-NavItem {
    param(
        [string]$href,
        [string]$label,
        [string]$icon,
        [string]$currentPath
    )

    # /diff fait partie du parcours "Configurations"
    $active = if ($currentPath -eq $href -or ($href -eq '/conf' -and $currentPath -eq '/diff')) { " active" } else { "" }
    return "<a href='$href' class='nav-item$active'>$icon<span>$label</span></a>"
}

# Fonction Création HTML
function Get-Html{
    param(
        [string]$cssPath = "$PSScriptRoot/assets/styles/style.css",
        [string]$jsPath = "$PSScriptRoot/assets/scripts/app.js",
        [string]$imgPath = "$PSScriptRoot/assets/img/banner.png",
        [string]$icoPath = "$PSScriptRoot/assets/img/favicon.ico",
        [string]$body,
        [string]$path = "",
        [bool]$authenticated = $false
    )
    $styleTag = Get-StyleContent -cssPath $cssPath
    $scriptTag = Get-ScriptContent -jsPath $jsPath
    $imageTag = Get-ImageContent -imagePath $imgPath -altText "NetBackup POSH"
    $faviconTag = Get-FaviconContent -icoPath $icoPath
    $pageTitle = Get-PageTitle -path $path

    if ($authenticated) {
        $icons = @{
            Configs  = "<svg xmlns='http://www.w3.org/2000/svg' width='18' height='18' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><rect x='2' y='2' width='20' height='8' rx='2' ry='2'></rect><rect x='2' y='14' width='20' height='8' rx='2' ry='2'></rect><line x1='6' y1='6' x2='6.01' y2='6'></line><line x1='6' y1='18' x2='6.01' y2='18'></line></svg>"
            Overview = "<svg xmlns='http://www.w3.org/2000/svg' width='18' height='18' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><rect x='3' y='3' width='7' height='7'></rect><rect x='14' y='3' width='7' height='7'></rect><rect x='14' y='14' width='7' height='7'></rect><rect x='3' y='14' width='7' height='7'></rect></svg>"
            Devices  = "<svg xmlns='http://www.w3.org/2000/svg' width='18' height='18' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><line x1='8' y1='6' x2='21' y2='6'></line><line x1='8' y1='12' x2='21' y2='12'></line><line x1='8' y1='18' x2='21' y2='18'></line><line x1='3' y1='6' x2='3.01' y2='6'></line><line x1='3' y1='12' x2='3.01' y2='12'></line><line x1='3' y1='18' x2='3.01' y2='18'></line></svg>"
            Logs     = "<svg xmlns='http://www.w3.org/2000/svg' width='18' height='18' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z'></path><polyline points='14 2 14 8 20 8'></polyline><line x1='16' y1='13' x2='8' y2='13'></line><line x1='16' y1='17' x2='8' y2='17'></line></svg>"
            Key      = "<svg xmlns='http://www.w3.org/2000/svg' width='18' height='18' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0l3 3L22 7l-3-3m-3.5 3.5L19 4'></path></svg>"
            Logout   = "<svg xmlns='http://www.w3.org/2000/svg' width='18' height='18' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4'></path><polyline points='16 17 21 12 16 7'></polyline><line x1='21' y1='12' x2='9' y2='12'></line></svg>"
        }

        $layout = @"
<div class="app">
    <aside class="sidebar">
        <div class="sidebar-brand">
            $imageTag
        </div>
        <nav class="sidebar-nav">
            <p class="nav-label">Sauvegardes</p>
            $(Get-NavItem -href '/conf' -label 'Configurations' -icon $icons.Configs -currentPath $path)
            <p class="nav-label">Administration</p>
            $(Get-NavItem -href '/admin' -label "Vue d'ensemble" -icon $icons.Overview -currentPath $path)
            $(Get-NavItem -href '/admin/devices' -label 'Équipements' -icon $icons.Devices -currentPath $path)
            $(Get-NavItem -href '/admin/connectors' -label 'Connecteurs' -icon $icons.Key -currentPath $path)
            $(Get-NavItem -href '/admin/logs' -label 'Journaux' -icon $icons.Logs -currentPath $path)
        </nav>
        <div class="sidebar-footer">
            <a href="/logout" class="nav-item logout">$($icons.Logout)<span>Déconnexion</span></a>
        </div>
    </aside>
    <div class="main">
        <header class="topbar">
            <h1>$pageTitle</h1>
            <a href="/logout" class="btn btn-secondary btn-sm">Déconnexion</a>
        </header>
        <main class="content">
            $body
        </main>
    </div>
</div>
"@
    } else {
        $layout = @"
<div class="auth-wrap">
    <div class="auth-logo">$imageTag</div>
    $body
</div>
"@
    }

    return @"
    <!DOCTYPE html>
    <html lang="fr">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>$pageTitle · NetBackup</title>
        $faviconTag
        $styleTag
    </head>
    <body>
        $layout
        $scriptTag
    </body>
    </html>
"@
}

# Fonction Démarrage Server
function Start-ConfigServer {
    param(
        [string]$prefix = "http",
        [string]$addr = "localhost",
        [string]$port = "8080",
        [string]$publicUrl = $env:PUB_URL
    )
   
    $baseUrl = if ($publicUrl) { $publicUrl } else { "$($prefix)://$($addr):$($port)" }

    $http = [System.Net.HttpListener]::new()
    $http.Prefixes.Add("$($prefix)://+:$($port)/")
   
    try {
        $http.Start()
        Write-Host "Serveur démarré sur $($prefix)://$($addr):$($port)/"
       
        while ($http.IsListening) {
            $context = $http.GetContext()
           
            try {
                $response = $context.Response
                $response.ContentType = "text/html; charset=utf-8"
                $response.Headers.Add("Content-Type", "text/html; charset=utf-8")

                $request = $context.Request
                $method = $request.HttpMethod

                # Récupérer le chemin et les paramètres
                $path = Get-UrlPath -rawUrl $request.RawUrl
                $parameters = Get-UrlParameters -rawUrl $request.RawUrl
                $postParams = if ($method -eq 'POST') { Get-PostParameters -request $request } else { @{} }

                $clientIp = $request.RemoteEndPoint.Address.ToString()

                # Résoudre la session à partir du cookie
                $sessionCookie = $request.Cookies['session']
                $session = if ($sessionCookie) { Test-Session -token $sessionCookie.Value } else { $null }

                # Garde d'authentification : tout est protégé sauf /login
                if (-not $session -and $path -ne '/login') {
                    $response.StatusCode = 302
                    $response.Headers.Add("Location", "/login")
                    $response.Close()
                    continue
                }

                # Router vers la fonction appropriée
                $result = switch ($path) {
                    "/login"         { Handle-Login -method $method -postParams $postParams -clientIp $clientIp }
                    "/logout"        { Handle-Logout -token $sessionCookie.Value }
                    "/conf"          { Handle-Conf -parameters $parameters }
                    "/diff"          { Handle-Diff -parameters $parameters }
                    "/admin"         { Handle-AdminDashboard -session $session }
                    "/admin/devices" { Handle-AdminDevices -method $method -postParams $postParams -session $session }
                    "/admin/connectors" { Handle-AdminConnectors -method $method -postParams $postParams -session $session }
                    "/admin/logs"    { Handle-AdminLogs }
                    "/admin/backup"  { Handle-AdminBackup -method $method -postParams $postParams -session $session }
                    default          { Handle-Default -baseUrl $baseUrl }
                }

                if ($result -is [hashtable]) {
                    if ($result.Cookie) { $response.AppendCookie($result.Cookie) }
                    if ($result.Redirect) {
                        $response.StatusCode = 302
                        $response.Headers.Add("Location", $result.Redirect)
                        $response.Close()
                        continue
                    }
                    $body = $result.Body
                    if ($result.StatusCode) { $response.StatusCode = $result.StatusCode }
                } else {
                    $body = $result
                }

                $html = Get-Html -body $body -path $path -authenticated ([bool]$session)

                $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
                $response.ContentLength64 = $buffer.Length

                try {
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                }
                catch [System.Net.HttpListenerException] {
                    Write-Warning "Connexion client perdue"
                    continue
                }
                finally {
                    if ($response) {
                        $response.Close()
                    }
                }
            }
            catch {
                Write-Error $_.Exception.Message
                if ($response) {
                    $response.StatusCode = 500
                    $response.Close()
                }
            }
        }
    }
    finally {
        $http.Stop()
        $http.Close()
    }
}

# Démarrer le serveur
Start-ConfigServer -prefix $prefix -addr $addr -port $port
