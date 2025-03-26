<# Imports of modules  to use #>
. "/app/src/Handle-Conf"
. "/app/src/Utils"


# Fonction Création HTML
function Get-Html{
    param(
        [string]$cssPath = "$PSScriptRoot\styles\style.css",
        [string]$body
    )
    $styleTag = Get-StyleContent -cssPath $cssPath
        
    return @"
    <!DOCTYPE html>
    <html lang="fr">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>NetBackup Powershell</title>
        $styleTag
    </head>
    <body>
        $body
    </body>
    </html>
"@
}

# Fonction Démarrage Server
function Start-ConfigServer {
    param(
        [string]$prefix = "http",
        [string]$addr = "0.0.0.0",
        [string]$port = "8080"
    )
   
    $http = [System.Net.HttpListener]::new()
    #$http.Prefixes.Add("$($prefix)://$($addr):$($port)/")
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
                
                # Récupérer le chemin et les paramètres
                $path = Get-UrlPath -rawUrl $context.Request.RawUrl
                $parameters = Get-UrlParameters -rawUrl $context.Request.RawUrl
                
                # Router vers la fonction appropriée
                $body = switch ($path) {
                    "/conf" { Handle-Conf -parameters $parameters }
                    default { Handle-Default -baseUrl "$($prefix)://$($addr):$($port)" }
                }

                $html = Get-Html -body $body
               
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
Start-ConfigServer
