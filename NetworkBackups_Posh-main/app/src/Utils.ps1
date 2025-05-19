# Fonction pour charger et intégrer le CSS
function Get-StyleContent {
    param(
        [string]$cssPath = "$PSScriptRoot\..\assets\styles\style.css"
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

function Get-ImageContent {
    param(
        [string]$imagePath = "$PSScriptRoot\..\assets\img\logo.png",
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


# Fonction pour récupérer les paramettres de l'url
function Get-UrlParameters {
    param(
        [string]$rawUrl
    )
    
    $parameters = @{}
    if ($rawUrl -match "\?(.+)$") {
        $queryString = $matches[1]
        $queryString.Split('&') | ForEach-Object {
            $keyValue = $_.Split('=')
            if ($keyValue.Length -eq 2) {
                $parameters[$keyValue[0]] = [System.Web.HttpUtility]::UrlDecode($keyValue[1])
            }
        }
    }
    return $parameters
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
