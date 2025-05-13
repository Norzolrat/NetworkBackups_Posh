# Import des modules requis
Import-Module Posh-SSH

# Chemins des fichiers de configuration
$configPath = "$PSScriptRoot\devices.json"
$credentialPath = "$PSScriptRoot\credentials.xml" 
$backupPath = "$PSScriptRoot\NetworkBackups"

# Fonction pour créer le fichier de credentials de manière interactive
function New-CredentialFile {
    param (
        [string]$Path
    )

    Write-Host "Création du fichier de credentials..." -ForegroundColor Yellow

    $username = Read-Host "Entrez l'identifiant pour tous les équipements"
    $password = Read-Host "Entrez le mot de passe" -AsSecureString

    $credential = New-Object System.Management.Automation.PSCredential($username, $password)

    # Exporter les credentials
    $credential | Export-Clixml -Path $Path
    Write-Host "`nFichier de credentials créé avec succès: $Path" -ForegroundColor Green

    return $credential
}

# Import des configurations
function Import-DeviceConfig {
    if (Test-Path $configPath) {
        $devices = Get-Content $configPath | ConvertFrom-Json
        return $devices.devices
    } else {
        throw "Fichier de configuration non trouvé: $configPath"
    }
}

# Import des credentials avec création si nécessaire
function Import-DeviceCredentials {
    if (-not (Test-Path $credentialPath)) {
        Write-Host "Fichier de credentials non trouvé: $credentialPath" -ForegroundColor Yellow
        $createNew = Read-Host "Voulez-vous créer un nouveau fichier de credentials? (O/N)"

        if ($createNew -eq "O") {
            return New-CredentialFile -Path $credentialPath
        } else {
            throw "Le fichier de credentials est nécessaire pour continuer."
        }
    } else {
        return Import-Clixml -Path $credentialPath
    }
}

# Création du repo SVN

function Initialize-SVNRepo {
    param (
        [string]$Path
    )

    $repoPath = Join-Path $Path ".repo"
    $configsPath = Join-Path $Path "configs"

    # Créer le dépôt dans un dossier caché
    svnadmin create $repoPath

    # Générer l’URL locale du dépôt
    $fullRepoPath = (Resolve-Path $repoPath).Path
    $svnUrl = "file:///" + ($fullRepoPath -replace "\\", "/")

    Write-Host "SVN URL: $svnUrl"

    # Faire le checkout vers configs
    svn checkout $svnUrl $configsPath
}


# Création des dossiers nécessaires
function Initialize-BackupEnvironment {
    if (-not (Test-Path $backupPath)) {
        New-Item -ItemType Directory -Path $backupPath
        Initialize-SVNRepo -Path $backupPath
        Write-Host "Dossier de backup créé: $backupPath" -ForegroundColor Green
    }elseif (-not (Test-Path (Join-Path $backupPath "configs"))) {
        Initialize-SVNRepo -Path $backupPath
    }
}

# Rajout des ellement dans le repos SVN
function Add-NewFiles {
    param (
        [string]$Path
    )
    
    $startingLocation = Get-Location
    Set-Location $Path
    Write-Debug "Working on $Path"
    $newFiles = svn status | Where-Object { $_ -match '^\?' }
    if ($newFiles) {
        $newFiles | ForEach-Object { 
            $file = $_.Substring(8).Trim()
            svn add $file
            Write-Debug "$file"
        }
    }
    svn commit -m "Ajout automatique des configs"
    svn update
    Write-Host "Ajout automatique des configs"
    Set-Location $startingLocation
}

function Clean-TheConf {
    param (
        [string]$command,
        [string]$conf
    )

    $checkCommand = ($command -split "`n")[-1].Trim()

    $lines = $conf -split "`n"
    $cleanedLines = @()
    $startCollecting = $false

    foreach ($line in $lines) {
        if (-not $startCollecting -and $line -match [regex]::Escape($checkCommand)) {
            $startCollecting = $true
            continue
        }

        if ($startCollecting) {
            $cleanedLines += $line
        }
    }

    # if ($cleanedLines.Count -gt 0) {
    #     $null = $cleanedLines.RemoveAt($cleanedLines.Count - 1)
    # }

    $cleanConf = $cleanedLines -join "`n"
    $cleanConf = $cleanConf -replace '(\r?\n){3,}', "`n`n"

    return $cleanConf.Trim()
}

# Fonction pour obtenir la configuration selon le type d'équipement et les commandes
function Get-DeviceConfig {
    param (
        $device,
        $sshStream
    )

    $output = @()
    Start-Sleep -Seconds 4  # Attendre que la connexion soit stable

    foreach ($command in $device.Commands) {
        try {
            Write-Host "  Exécution de la commande: $command" -ForegroundColor Cyan
            
            $sshStream.WriteLine($command)
            Start-Sleep -Seconds 3  # Attendre que la commande soit exécutée
            $result = $sshStream.Read()

            if ($result) {
                # Nettoyer les séquences ANSI et autres caractères de contrôle
                $cleanResult = $result
                
                # Liste complète des patterns à nettoyer
                $patternsToClean = @(
                    '\x1B\[[0-9;]*[a-zA-Z]',      # Séquences ANSI standards
                    '\x1B\][0-9;]*\x07',          # Séquences OSC
                    '\x1B\[[\d;]*[A-Za-z]',       # Autres séquences de contrôle
                    '\[\d+;\d+[A-Za-z]',          # Format comme [24;1H
                    '\[\?25[hl]',                 # [?25h et [?25l
                    '\[\?[0-9]+[hl]',             # [?6l, [?7h, etc.
                    '\[K',                        # Séquence d'effacement de ligne
                    '\[\?[0-9]+[a-zA-Z]',         # Toute séquence commençant par [? et finissant par une lettre
                    '\[\\\d*[a-zA-Z]',            # Autres séquences de contrôle
                    '\[[0-9;]*[a-zA-Z]',          # Séquences numériques génériques
                    '\x1B\[[\x30-\x3F]*[\x20-\x2F]*[\x40-\x7E]', # Séquences d'échappement complexes
                    '[^\x20-\x7E\n]'             # Tous les caractères non-imprimables sauf les sauts de ligne
                )

                # Appliquer chaque pattern de nettoyage
                foreach ($pattern in $patternsToClean) {
                    $cleanResult = $cleanResult -replace $pattern, ''
                }

                # Normaliser les sauts de ligne
                $cleanResult = $cleanResult -replace '(\r\n|\r|\n)', "`n"
                
                # Filtrer les lignes vides en début et fin et les lignes qui ne contiennent que des espaces
                $cleanResult = ($cleanResult -split "`n" | Where-Object { $_.Trim() }) -join "`n"

                # Filtrer les lignes vides, les lignes avec uniquement des espaces
                # ET les lignes contenant "Last login" ou un format de date typique
                $cleanResult = ($cleanResult -split "`n" | Where-Object {
                    $_.Trim() -and
                    ($_ -notmatch 'Last login') -and
                    ($_ -notmatch '^\s*\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}') # ex: Mon May 13 10:32:45
                }) -join "`n"

                $cleanResult = Clean-TheConf -command $command -conf $cleanResult
                
                if ($cleanResult) {
                    $output += $cleanResult
                    $output += "`n"
                }
            } else {
                Write-Warning "Pas de sortie pour la commande '$command' sur $($device.Name)"
            }
        }
        catch {
            Write-Error "Erreur lors de l'exécution de la commande '$command' sur $($device.Name): $_"
            continue
        }
    }

    return $output
}

# Fonction principale de backup
function Backup-NetworkDevices {
    Initialize-BackupEnvironment

    try {
        $devices = Import-DeviceConfig
        $credential = Import-DeviceCredentials

        foreach ($device in $devices) {
            try {
                Write-Host "`nTraitement de $($device.Name) ($($device.IP))..." -ForegroundColor Yellow

                # Vérifier si des commandes sont définies
                if (-not $device.Commands -or $device.Commands.Count -eq 0) {
                    Write-Warning "Aucune commande définie pour $($device.Name), passage au suivant"
                    continue
                }

                # Établir la connexion SSH
                $sshSession = New-SSHSession -ComputerName $device.IP -Credential $credential -AcceptKey -Force
                
                if ($sshSession) {
                    # Créer un nouveau stream SSH
                    $sshStream = New-SSHShellStream -Index ($sshSession.SessionId)

                    # Récupérer la configuration
                    $config = Get-DeviceConfig -device $device -sshStream $sshStream

                    if ($config) {
                        # Créer le fichier de backup
                        $fileName = "$($device.Name)"
                        $configPath = Join-Path $backupPath "configs"
                        $filePath = Join-Path $configPath $fileName

                        $config | Out-File -FilePath $filePath -Encoding UTF8

                        Write-Host "Backup réussi pour $($device.Name)" -ForegroundColor Green
                    } else {
                        throw "Aucune donnée de configuration récupérée"
                    }
                }
            }
            catch {
                Write-Error "Erreur lors du backup de $($device.Name): $_"
            }
            finally {
                if ($sshStream) {
                    $sshStream.Dispose()
                }
                if ($sshSession) {
                    Remove-SSHSession -SessionId $sshSession.SessionId
                }
            }
        }
        Add-NewFiles -Path (Join-Path $backupPath "configs")
    }
    catch {
        Write-Error "Erreur lors de l'importation des configurations: $_"
    }
}

# Exécuter le backup
Backup-NetworkDevices

