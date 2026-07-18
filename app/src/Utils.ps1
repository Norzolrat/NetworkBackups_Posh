# Fonction pour charger et intégrer le CSS
function Get-StyleContent {
    param(
        [string]$cssPath = (Join-Path $PSScriptRoot ".." "assets" "styles" "style.css")
    )

    try {
        if (Test-Path $cssPath) {
            $cssContent = Get-Content -Path $cssPath -Raw
            return "<style>$cssContent</style>"
        } else {
            Write-Warning "Fichier CSS non trouvé: $cssPath"
            return "<style>/* CSS file not found */</style>"
        }
    } catch {
        Write-Error "Erreur lors du chargement du CSS: $($_.Exception.Message)"
        return "<style>/* Error loading CSS */</style>"
    }
}

# Fonction pour charger et intégrer le JS
function Get-ScriptContent {
    param(
        [string]$jsPath = (Join-Path $PSScriptRoot ".." "assets" "scripts" "app.js")
    )

    try {
        if (Test-Path $jsPath) {
            $jsContent = Get-Content -Path $jsPath -Raw
            return "<script>$jsContent</script>"
        } else {
            Write-Warning "Fichier JS non trouvé: $jsPath"
            return "<script>/* JS file not found */</script>"
        }
    } catch {
        Write-Error "Erreur lors du chargement du JS: $($_.Exception.Message)"
        return "<script>/* Error loading JS */</script>"
    }
}

function Get-ImageContent {
    param(
        [string]$imagePath = (Join-Path $PSScriptRoot ".." "assets" "img" "logo.png"),
        [string]$altText = "Logo"
    )

    try {
        if (Test-Path $imagePath) {
            $imageBytes = [System.IO.File]::ReadAllBytes($imagePath)
            $base64Image = [System.Convert]::ToBase64String($imageBytes)
            $mimeType = "image/png"
            return "<img src='data:$mimeType;base64,$base64Image' alt='$altText'/>"
        } else {
            Write-Warning "Fichier image non trouvé: $imagePath"
            return "<!-- Image file not found -->"
        }
    } catch {
        Write-Error "Erreur lors du chargement de l'image: $($_.Exception.Message)"
        return "<!-- Error loading image -->"
    }
}


# Fonction pour générer la balise favicon (icône inlinée en base64)
function Get-FaviconContent {
    param(
        [string]$icoPath = (Join-Path $PSScriptRoot ".." "assets" "img" "favicon.ico")
    )

    try {
        if (Test-Path $icoPath) {
            $iconBytes = [System.IO.File]::ReadAllBytes($icoPath)
            $base64Icon = [System.Convert]::ToBase64String($iconBytes)
            return "<link rel='icon' type='image/x-icon' href='data:image/x-icon;base64,$base64Icon'>"
        } else {
            Write-Warning "Fichier favicon non trouvé: $icoPath"
            return ""
        }
    } catch {
        Write-Error "Erreur lors du chargement du favicon: $($_.Exception.Message)"
        return ""
    }
}


# Fonction pour parser une chaîne "clé=valeur&clé=valeur" (query string ou corps de formulaire)
function ConvertFrom-QueryString {
    param(
        [string]$queryString
    )

    $parameters = @{}
    if ($queryString) {
        $queryString.Split('&') | ForEach-Object {
            $keyValue = $_.Split('=')
            if ($keyValue.Length -eq 2) {
                $parameters[$keyValue[0]] = [System.Web.HttpUtility]::UrlDecode($keyValue[1])
            }
        }
    }
    return $parameters
}

# Fonction pour récupérer les paramettres de l'url
function Get-UrlParameters {
    param(
        [string]$rawUrl
    )

    if ($rawUrl -match "\?(.+)$") {
        return ConvertFrom-QueryString -queryString $matches[1]
    }
    return @{}
}

# Fonction pour récupérer les paramètres d'un corps de formulaire POST (application/x-www-form-urlencoded)
function Get-PostParameters {
    param(
        $request
    )

    $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
    try {
        $bodyContent = $reader.ReadToEnd()
    } finally {
        $reader.Dispose()
    }
    return ConvertFrom-QueryString -queryString $bodyContent
}

# Fonction pour extraire le chemin de base de l'URL
function Get-UrlPath {
    param(
        [string]$rawUrl
    )
    
    $path = $rawUrl.Split('?')[0]
    return $path.TrimEnd('/')
}

# Gestionnaires de routes spécifiques
function Handle-Default {
    param(
        $baseUrl
        )
    return "<script>window.location.href = '$baseUrl/conf';</script>"
}
