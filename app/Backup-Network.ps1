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

    # Générer l'URL locale du dépôt
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

# Rajout des éléments dans le repos SVN
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

    $cleanConf = $cleanedLines -join "`n"
    $cleanConf = $cleanConf -replace '(\r?\n){3,}', "`n`n"

    return $cleanConf.Trim()
}

# Fonction pour attendre que le prompt soit prêt
function Wait-ForPrompt {
    param (
        $sshStream,
        [string]$promptPattern = '[\$#>]\s*$',
        [int]$maxWaitSeconds = 90
    )
    
    $startTime = Get-Date
    $buffer = ""
    
    while (((Get-Date) - $startTime).TotalSeconds -lt $maxWaitSeconds) {
        Start-Sleep -Milliseconds 500
        $newData = $sshStream.Read()
        
        if ($newData) {
            $buffer += $newData
            # Vérifier si on a un prompt
            if ($buffer -match $promptPattern) {
                Write-Debug "Prompt détecté: $($matches[0])"
                return $true
            }
        }
    }
    
    Write-Warning "Timeout en attendant le prompt après $maxWaitSeconds secondes"
    return $false
}

# Fonction pour lire complètement la sortie d'une commande avec gestion de pagination
function Read-CommandOutput {
    param (
        $sshStream,
        [string]$command,
        [int]$maxWaitSeconds = 300,
        [string]$endPattern = '[\$#>]\s*$',
        [string[]]$morePatterns = @('--More--', '--- More ---', '-- More --', 'Press any key to continue', '\[42D +\[42D', '\[K--More--\[K', '\[7m--More--\[27m')
    )
    
    $output = ""
    $startTime = Get-Date
    $lastDataTime = Get-Date
    $stableDataTimeout = 20
    $iterationCount = 0
    $paginationCount = 0
    
    Write-Host "    Lecture de la sortie pour: $command" -ForegroundColor Cyan
    
    while (((Get-Date) - $startTime).TotalSeconds -lt $maxWaitSeconds) {
        $newData = $sshStream.Read()
        
        if ($newData) {
            $output += $newData
            $lastDataTime = Get-Date
            $iterationCount++
            
            # Afficher un point de progression toutes les 100 itérations
            if ($iterationCount % 100 -eq 0) {
                Write-Host "." -NoNewline -ForegroundColor Cyan
            }
            
            # Vérifier s'il y a une pagination en cours
            $foundMorePattern = $false
            foreach ($morePattern in $morePatterns) {
                if ($output -match $morePattern) {
                    $paginationCount++
                    Write-Host "`n    Pagination détectée #$paginationCount ($morePattern), envoi d'espace..." -ForegroundColor Yellow
                    $sshStream.WriteLine(" ")
                    Start-Sleep -Milliseconds 1000
                    $foundMorePattern = $true
                    
                    # Nettoyer le pattern de pagination de la sortie
                    $output = $output -replace [regex]::Escape($morePattern), ''
                    break
                }
            }
            
            # Si on a trouvé une pagination, continuer la boucle
            if ($foundMorePattern) {
                continue
            }
            
            # Vérifier si on a atteint la fin (prompt) seulement si pas de pagination
            if ($output -match $endPattern) {
                # Vérifier que ce n'est pas un faux positif au milieu de la sortie
                $lines = $output -split "`n"
                $lastLines = $lines[-10..-1] | Where-Object { $_.Trim() }
                
                $foundPromptAtEnd = $false
                foreach ($line in $lastLines) {
                    if ($line -match $endPattern -and $line.Trim().Length -lt 100) {
                        $foundPromptAtEnd = $true
                        break
                    }
                }
                
                if ($foundPromptAtEnd) {
                    Write-Host "`n    Fin de commande détectée (après $paginationCount paginations)" -ForegroundColor Green
                    break
                }
            }
        } else {
            # Pas de nouvelles données, vérifier le timeout
            if (((Get-Date) - $lastDataTime).TotalSeconds -gt $stableDataTimeout) {
                Write-Host "`n    Timeout de stabilité atteint après $paginationCount paginations" -ForegroundColor Yellow
                break
            }
        }
        
        Start-Sleep -Milliseconds 200
    }
    
    if (((Get-Date) - $startTime).TotalSeconds -ge $maxWaitSeconds) {
        Write-Warning "`nTimeout global atteint pour la commande: $command (après $paginationCount paginations)"
    }
    
    Write-Host "`n    Taille de sortie récupérée: $($output.Length) caractères avec $paginationCount paginations" -ForegroundColor Cyan
    
    # Compter approximativement le nombre d'interfaces pour validation
    $interfaceCount = ($output | Select-String -Pattern "interface.*Ethernet" -AllMatches).Matches.Count
    if ($interfaceCount -gt 0) {
        Write-Host "    Nombre d'interfaces détectées: $interfaceCount" -ForegroundColor Cyan
    }
    
    return $output
}

# Fonction pour obtenir la configuration selon le type d'equipement et les commandes
function Get-DeviceConfig {
    param (
        $device,
        $sshStream
    )

    $output = @()
    
    # Attendre que la connexion soit stable
    Write-Host "  Attente de stabilisation de la connexion..." -ForegroundColor Cyan
    if (-not (Wait-ForPrompt -sshStream $sshStream -maxWaitSeconds 90)) {
        throw "Impossible d'établir une connexion stable"
    }

    foreach ($command in $device.Commands) {
        try {
            Write-Host "  Exécution de la commande: $command" -ForegroundColor Cyan
            
            # Traiter les commandes multi-lignes (séparées par \n)
            $commandParts = $command -split "`n"
            
            foreach ($part in $commandParts) {
                if ($part.Trim()) {
                    Write-Host "    Envoi de: $($part.Trim())" -ForegroundColor Gray
                    $sshStream.WriteLine($part.Trim())
                    Start-Sleep -Seconds 2
                }
            }
            
            # Attendre un peu que la commande soit envoyée
            Start-Sleep -Seconds 5
            
            # Lire la sortie complète avec timeout étendu et gestion de pagination
            $result = Read-CommandOutput -sshStream $sshStream -command $command -maxWaitSeconds 300
            
            if ($result) {
                # Nettoyer les séquences ANSI et autres caractères de contrôle
                $cleanResult = $result
                
                # Liste complète des patterns à nettoyer (y compris les patterns de pagination)
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
                    '--More--',                   # Patterns de pagination
                    '--- More ---',
                    '-- More --',
                    'Press any key to continue',
                    '\[42D +\[42D',
                    '\[K--More--\[K',
                    '\[7m--More--\[27m',
                    '[^\x20-\x7E\n\r\t]'         # Tous les caractères non-imprimables sauf les sauts de ligne, retours chariot et tabulations
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
                    
                    # Validation - compter les interfaces pour diagnostic
                    $interfaceCount = ($cleanResult | Select-String -Pattern "interface.*Ethernet" -AllMatches).Matches.Count
                    if ($interfaceCount -gt 0) {
                        Write-Host "  Validation: $interfaceCount interfaces trouvées" -ForegroundColor Cyan
                        
                        # Pour un cluster de 4 switches avec 48 ports chacun
                        if ($device.Type -eq "comware" -and $interfaceCount -gt 100) {
                            Write-Host "  ✅ Configuration semble complète" -ForegroundColor Green
                        } elseif ($device.Type -eq "comware" -and $interfaceCount -lt 50) {
                            Write-Warning "  ⚠️  Nombre d'interfaces suspicieusement bas pour un cluster."
                        }
                    }
                    
                    Write-Host "  Commande exécutée avec succès. Taille: $($cleanResult.Length) caractères" -ForegroundColor Green
                } else {
                    Write-Warning "Contenu vide après nettoyage pour la commande '$command'"
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
            $sshSession = $null
            $sshStream = $null
            
            try {
                Write-Host "`nTraitement de $($device.Name) ($($device.IP))..." -ForegroundColor Yellow

                # Vérifier si des commandes sont définies
                if (-not $device.Commands -or $device.Commands.Count -eq 0) {
                    Write-Warning "Aucune commande définie pour $($device.Name), passage au suivant"
                    continue
                }

                # Établir la connexion SSH avec timeout étendu
                Write-Host "  Établissement de la connexion SSH..." -ForegroundColor Cyan
                $sshSession = New-SSHSession -ComputerName $device.IP -Credential $credential -AcceptKey -Force -ConnectionTimeout 90
                
                if ($sshSession) {
                    Write-Host "  Connexion SSH établie (SessionId: $($sshSession.SessionId))" -ForegroundColor Green
                    
                    # Créer un nouveau stream SSH avec buffer plus grand
                    $sshStream = New-SSHShellStream -Index ($sshSession.SessionId) -Columns 200 -Rows 50 -TerminalName "xterm"
                    
                    if ($sshStream) {
                        Write-Host "  Stream SSH créé" -ForegroundColor Green
                        
                        # Récupérer la configuration avec gestion améliorée
                        $config = Get-DeviceConfig -device $device -sshStream $sshStream

                        if ($config -and $config.Count -gt 0) {
                            # Créer le fichier de backup
                            $fileName = "$($device.Name)"
                            $configPath = Join-Path $backupPath "configs"
                            $filePath = Join-Path $configPath $fileName

                            # Joindre toutes les parties de la config
                            $finalConfig = $config -join ""
                            
                            # Vérifier que le contenu n'est pas vide
                            if ($finalConfig.Trim().Length -gt 0) {
                                $finalConfig | Out-File -FilePath $filePath -Encoding UTF8
                                Write-Host "  Backup réussi pour $($device.Name) - Taille: $($finalConfig.Length) caractères" -ForegroundColor Green
                            } else {
                                throw "Configuration vide après traitement"
                            }
                        } else {
                            throw "Aucune donnée de configuration récupérée"
                        }
                    } else {
                        throw "Impossible de créer le stream SSH"
                    }
                } else {
                    throw "Impossible d'établir la connexion SSH"
                }
            }
            catch {
                Write-Error "Erreur lors du backup de $($device.Name): $_"
            }
            finally {
                # Nettoyage des ressources dans l'ordre inverse
                if ($sshStream) {
                    try {
                        $sshStream.Close()
                        $sshStream.Dispose()
                        Write-Debug "Stream SSH fermé pour $($device.Name)"
                    }
                    catch {
                        Write-Warning "Erreur lors de la fermeture du stream SSH: $_"
                    }
                }
                
                if ($sshSession) {
                    try {
                        Remove-SSHSession -SessionId $sshSession.SessionId
                        Write-Debug "Session SSH fermée pour $($device.Name)"
                    }
                    catch {
                        Write-Warning "Erreur lors de la fermeture de la session SSH: $_"
                    }
                }
            }
        }
        
        # Ajouter les nouveaux fichiers au repository SVN
        Add-NewFiles -Path (Join-Path $backupPath "configs")
    }
    catch {
        Write-Error "Erreur lors de l'importation des configurations: $_"
    }
}

# Exécuter le backup
Backup-NetworkDevices