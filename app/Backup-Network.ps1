# Lancer avec -Verbose pour obtenir le déroulé détaillé (connexions, lectures SSH, tailles...)
[CmdletBinding()]
param()

# Import des modules requis
Import-Module Posh-SSH

# Chemins des fichiers de configuration
$configPath = "$PSScriptRoot\devices.json"
$backupPath = "$PSScriptRoot\NetworkBackups"
$connectorsPath = "$PSScriptRoot/secrets/connectors.xml"
$legacyConnectorsPath = "$PSScriptRoot/secrets/connectors.json"

# Marqueurs de pagination des équipements réseau, utilisés à la fois pour la
# détection en direct (Read-CommandOutput) et pour le nettoyage a posteriori (Get-DeviceConfig)
$script:MorePatterns = @('--More--', '--- More ---', '-- More --', 'Press any key to continue', '\[42D +\[42D', '\[K--More--\[K', '\[7m--More--\[27m')

# Import des configurations
function Import-DeviceConfig {
    if (Test-Path $configPath) {
        $devices = Get-Content $configPath | ConvertFrom-Json
        return $devices.devices
    } else {
        throw "Fichier de configuration non trouvé: $configPath"
    }
}

# Import des connecteurs d'authentification (table vide si le fichier est absent).
# Format courant : connectors.xml (clixml, secrets en SecureString, comme credentials.xml).
# Repli : connectors.json v1 non migré (la migration s'effectue au premier affichage de l'admin).
function Import-Connectors {
    $connectors = @{}
    $entries = @()

    if (Test-Path $connectorsPath) {
        try {
            $imported = Import-Clixml -Path $connectorsPath
            # Format courant : objet racine avec propriété 'connectors'. Compat : racine tableau,
            # qu'Import-Clixml peut renvoyer comme UN seul objet collection selon la version de PowerShell.
            if ($imported -and $imported.PSObject.Properties.Name -contains 'connectors') {
                foreach ($item in $imported.connectors) { $entries += $item }
            } else {
                foreach ($item in @($imported)) {
                    if ($item -is [System.Collections.ICollection]) {
                        foreach ($sub in $item) { $entries += $sub }
                    } else {
                        $entries += $item
                    }
                }
            }
        } catch {
            Write-Warning "connectors.xml illisible, connecteurs ignorés : $($_.Exception.Message)"
        }
    } elseif (Test-Path $legacyConnectorsPath) {
        Write-Warning "connectors.json au format hérité : ouvrez l'admin web pour migrer vers connectors.xml"
        try {
            $entries = @((Get-Content $legacyConnectorsPath -Raw | ConvertFrom-Json).connectors)
        } catch {
            Write-Warning "connectors.json illisible, connecteurs ignorés : $($_.Exception.Message)"
        }
    }

    foreach ($connector in $entries) {
        $connectors[$connector.Name] = $connector
    }
    return $connectors
}

# Récupère la valeur en clair d'un SecureString (le temps d'un usage ponctuel)
function ConvertFrom-SecureStringToPlain {
    param([System.Security.SecureString]$secure)

    return [System.Net.NetworkCredential]::new('', $secure).Password
}

# Convertit un secret de connecteur (SecureString depuis clixml, ou chaîne du format hérité)
function ConvertTo-SecretSecureString {
    param($secret)

    if ($secret -is [System.Security.SecureString]) { return $secret }
    if ($secret) { return (ConvertTo-SecureString $secret -AsPlainText -Force) }
    return (New-Object System.Security.SecureString)
}

# Résout l'authentification d'un équipement via son connecteur (obligatoire)
function Resolve-DeviceAuth {
    param (
        $device,
        [hashtable]$connectors
    )

    if (-not $device.Connector) {
        throw "Aucun connecteur défini pour cet équipement : assignez-en un dans l'admin web (Équipements)"
    }

    $connector = $connectors[$device.Connector]
    if (-not $connector) {
        throw "Connecteur '$($device.Connector)' introuvable dans le magasin de connecteurs"
    }

    if ($connector.Type -eq 'sshkey') {
        $credential = New-Object System.Management.Automation.PSCredential($connector.Username, (ConvertTo-SecretSecureString $connector.Passphrase))

        if ($connector.KeyContent) {
            return @{ Credential = $credential; KeyFile = $null; KeyContent = $connector.KeyContent }
        }
        # Format hérité : clé encore stockée en fichier
        if (-not $connector.KeyFile -or -not (Test-Path $connector.KeyFile)) {
            throw "Clé privée du connecteur '$($connector.Name)' introuvable : $($connector.KeyFile)"
        }
        return @{ Credential = $credential; KeyFile = $connector.KeyFile; KeyContent = $null }
    }

    $credential = New-Object System.Management.Automation.PSCredential($connector.Username, (ConvertTo-SecretSecureString $connector.Password))
    return @{ Credential = $credential; KeyFile = $null; KeyContent = $null }
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
            svn add $file --quiet
            Write-Debug "$file"
        }
    }
    if (svn status) {
        svn commit -m "Ajout automatique des configs" --quiet
        Write-Host "Changements committés dans le dépôt SVN" -ForegroundColor Green
    } else {
        Write-Host "Aucun changement de configuration à committer"
    }
    svn update --quiet
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
        # ❱ et % couvrent les prompts zsh personnalisés (ex: serveurs Linux), en plus des prompts réseau classiques
        [string]$promptPattern = '[#>$❱%]',
        [int]$maxWaitSeconds = 60
    )

    $startTime = Get-Date
    $buffer = ""

    Write-Verbose "Attente du prompt..."

    while (((Get-Date) - $startTime).TotalSeconds -lt $maxWaitSeconds) {
        Start-Sleep -Milliseconds 500
        $newData = $sshStream.Read()

        if ($newData) {
            $buffer += $newData
            Write-Verbose "Reçu: '$newData'"

            # Nettoyer les séquences ANSI du buffer pour la détection
            $cleanBuffer = $buffer -replace '\x1B\[[0-9;]*[a-zA-Z]', ''
            $cleanBuffer = $cleanBuffer -replace '\x1B\[[0-9;]*R', ''  # Pour \x1B[30;120R
            $cleanBuffer = $cleanBuffer -replace '\[[0-9;]*[a-zA-Z]', ''
            $cleanBuffer = $cleanBuffer -replace '\[[0-9;]*R', ''
            $cleanBuffer = $cleanBuffer.Trim()

            # Supprimer les lignes vides
            $cleanBuffer = ($cleanBuffer -split "`n" | Where-Object { $_.Trim() }) -join "`n"

            Write-Verbose "Buffer nettoyé: '$cleanBuffer'"

           # Vérifier si le buffer contient un caractère de prompt
            if ($cleanBuffer -match $promptPattern) {
                Write-Verbose "Prompt détecté - caractère trouvé"
                return $true
            }
        }
    }

    Write-Verbose "Buffer final: '$buffer'"
    Write-Warning "Timeout en attendant le prompt après $maxWaitSeconds secondes"
    return $false
}

# Fonction pour lire complètement la sortie d'une commande avec gestion de pagination
function Read-CommandOutput {
    param (
        $sshStream,
        [string]$command,
        [int]$maxWaitSeconds = 300,
        [string]$endPattern = '[#>$❱%]\s*$',
        [string[]]$morePatterns = $script:MorePatterns
    )
    
    $output = ""
    $startTime = Get-Date
    $lastDataTime = Get-Date
    $stableDataTimeout = 20
    $iterationCount = 0
    $paginationCount = 0
    
    Write-Verbose "Lecture de la sortie pour: $command"

    while (((Get-Date) - $startTime).TotalSeconds -lt $maxWaitSeconds) {
        $newData = $sshStream.Read()

        if ($newData) {
            $output += $newData
            $lastDataTime = Get-Date
            $iterationCount++

            # Signaler la progression toutes les 100 itérations
            if ($iterationCount % 100 -eq 0) {
                Write-Verbose "Lecture en cours ($iterationCount lectures, $($output.Length) caractères)"
            }

            # Vérifier s'il y a une pagination en cours
            $foundMorePattern = $false
            foreach ($morePattern in $morePatterns) {
                if ($output -match $morePattern) {
                    $paginationCount++
                    Write-Verbose "Pagination détectée #$paginationCount ($morePattern), envoi d'espace..."
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
            
            # Vérifier si on a atteint la fin (prompt) seulement si pas de pagination.
            # La détection se fait sur la fin du buffer débarrassée des séquences ANSI/OSC :
            # certains shells redessinent leur prompt en couleurs, ce qui masque le motif de fin.
            $tail = if ($output.Length -gt 2000) { $output.Substring($output.Length - 2000) } else { $output }
            $cleanTail = $tail -replace '\x1B\][^\x07\x1B]*(\x07|\x1B\\)', ''
            $cleanTail = $cleanTail -replace '\x1B\[[\x30-\x3F]*[\x20-\x2F]*[\x40-\x7E]', ''
            $cleanTail = $cleanTail -replace '\x1B[=>]', ''

            if ($cleanTail -match $endPattern) {
                # Vérifier que ce n'est pas un faux positif au milieu de la sortie.
                # Découpage sur \r ET \n : certains shells ne redessinent leur prompt qu'à coups de \r.
                $lastLines = ($cleanTail -split '[\r\n]+')[-10..-1] | Where-Object { $_.Trim() }

                $foundPromptAtEnd = $false
                foreach ($line in $lastLines) {
                    if ($line -match $endPattern -and $line.Trim().Length -lt 100) {
                        $foundPromptAtEnd = $true
                        break
                    }
                }

                if ($foundPromptAtEnd) {
                    Write-Verbose "Fin de commande détectée (après $paginationCount paginations)"
                    break
                }
            }
        } else {
            # Pas de nouvelles données, vérifier le timeout
            if (((Get-Date) - $lastDataTime).TotalSeconds -gt $stableDataTimeout) {
                Write-Verbose "Timeout de stabilité atteint après $paginationCount paginations"
                break
            }
        }
        
        Start-Sleep -Milliseconds 200
    }
    
    if (((Get-Date) - $startTime).TotalSeconds -ge $maxWaitSeconds) {
        Write-Warning "`nTimeout global atteint pour la commande: $command (après $paginationCount paginations)"
    }
    
    Write-Verbose "Taille de sortie récupérée: $($output.Length) caractères avec $paginationCount paginations"

    # Compter approximativement le nombre d'interfaces pour validation
    $interfaceCount = ($output | Select-String -Pattern "interface.*Ethernet" -AllMatches).Matches.Count
    if ($interfaceCount -gt 0) {
        Write-Verbose "Nombre d'interfaces détectées: $interfaceCount"
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
    Write-Verbose "Attente de stabilisation de la connexion..."
    if (-not (Wait-ForPrompt -sshStream $sshStream -maxWaitSeconds 90)) {
        throw "Impossible d'établir une connexion stable"
    }

    foreach ($command in $device.Commands) {
        try {
            Write-Verbose "Exécution de la commande: $command"

            # Traiter les commandes multi-lignes (séparées par \n)
            $commandParts = $command -split "`n"

            foreach ($part in $commandParts) {
                if ($part.Trim()) {
                    Write-Verbose "Envoi de: $($part.Trim())"
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
                
                # Liste des patterns à nettoyer (y compris les patterns de pagination, partagés via $script:MorePatterns)
                $patternsToClean = @(
                    '\x1B\[[\x30-\x3F]*[\x20-\x2F]*[\x40-\x7E]', # Séquences d'échappement ANSI/CSI complètes (ESC [ ... lettre finale)
                    '\x1B\][^\x07\x1B]*(\x07|\x1B\\)',           # Séquences OSC complètes, titre inclus (ESC ] ... BEL ou ST)
                    '\[\d+;\d+[A-Za-z]',                         # Positionnement dont l'ESC initial a été perdu, ex: [24;1H
                    '\[\?[0-9]+[a-zA-Z]',                        # Toggle dont l'ESC initial a été perdu, ex: [?25h, [?6l
                    '\[\\\d*[a-zA-Z]',                           # Autres séquences de contrôle sans ESC
                    '\[[0-9;]*[a-zA-Z]'                          # Séquences numériques génériques sans ESC, ex: [K
                ) + $script:MorePatterns + @(
                    '[^\x20-\x7E\n\r\t]'                         # Caractères non-imprimables restants
                )

                # Appliquer chaque pattern de nettoyage
                foreach ($pattern in $patternsToClean) {
                    $cleanResult = $cleanResult -replace $pattern, ''
                }

                # Normaliser les sauts de ligne
                $cleanResult = $cleanResult -replace '(\r\n|\r|\n)', "`n"

                # Filtrer les lignes vides/espaces uniquement, ainsi que les lignes
                # de "Last login", de date typique (ex: Mon May 13 10:32:45) et de
                # prompt horodaté (ex: [22:42:18] [~]) qui varient à chaque run
                $cleanResult = ($cleanResult -split "`n" | Where-Object {
                    $_.Trim() -and
                    ($_ -notmatch 'Last login') -and
                    ($_ -notmatch '^\s*\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}') -and
                    ($_ -notmatch '^\s*\[\d{2}:\d{2}:\d{2}\]')
                }) -join "`n"

                $cleanResult = Clean-TheConf -command $command -conf $cleanResult
                
                if ($cleanResult) {
                    $output += $cleanResult
                    $output += "`n"
                    
                    # Validation - compter les interfaces pour diagnostic
                    $interfaceCount = ($cleanResult | Select-String -Pattern "interface.*Ethernet" -AllMatches).Matches.Count
                    if ($interfaceCount -gt 0) {
                        Write-Verbose "Validation: $interfaceCount interfaces trouvées"

                        # Pour un cluster de 4 switches avec 48 ports chacun
                        if ($device.Type -eq "comware" -and $interfaceCount -gt 100) {
                            Write-Verbose "Configuration semble complète"
                        } elseif ($device.Type -eq "comware" -and $interfaceCount -lt 50) {
                            Write-Warning "  ⚠️  Nombre d'interfaces suspicieusement bas pour un cluster."
                        }
                    }

                    Write-Verbose "Commande exécutée avec succès. Taille: $($cleanResult.Length) caractères"
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
        $connectors = Import-Connectors

        $successCount = 0
        $failedDevices = @()

        foreach ($device in $devices) {
            $sshSession = $null
            $sshStream = $null
            $tempKeyFile = $null

            try {
                Write-Host "`nTraitement de $($device.Name) ($($device.IP))..." -ForegroundColor Yellow

                # Vérifier si des commandes sont définies
                if (-not $device.Commands -or $device.Commands.Count -eq 0) {
                    Write-Warning "Aucune commande définie pour $($device.Name), passage au suivant"
                    continue
                }

                # Résoudre l'authentification via le connecteur de l'équipement
                $auth = Resolve-DeviceAuth -device $device -connectors $connectors

                # Établir la connexion SSH avec timeout étendu
                # (le warning "Host key is not being verified" est masqué : conséquence assumée de -AcceptKey -Force)
                Write-Verbose "Établissement de la connexion SSH..."
                if ($auth.KeyFile -or $auth.KeyContent) {
                    $keyFile = $auth.KeyFile
                    if ($auth.KeyContent) {
                        # La clé n'existe qu'en SecureString : matérialisation éphémère en tmpfs
                        # (jamais sur disque), supprimée dans le finally
                        $tempKeyRoot = if (Test-Path '/dev/shm') { '/dev/shm' } else { [System.IO.Path]::GetTempPath() }
                        $tempKeyFile = Join-Path $tempKeyRoot "nbkey-$([guid]::NewGuid().ToString('N'))"
                        Set-Content -Path $tempKeyFile -Value (ConvertFrom-SecureStringToPlain $auth.KeyContent) -NoNewline
                        chmod 600 $tempKeyFile
                        $keyFile = $tempKeyFile
                    }
                    Write-Verbose "Authentification via le connecteur '$($device.Connector)' (clé SSH)"
                    $sshSession = New-SSHSession -ComputerName $device.IP -Credential $auth.Credential -KeyFile $keyFile -AcceptKey -Force -ConnectionTimeout 90 -WarningAction SilentlyContinue
                } else {
                    Write-Verbose "Authentification via le connecteur '$($device.Connector)' (mot de passe)"
                    $sshSession = New-SSHSession -ComputerName $device.IP -Credential $auth.Credential -AcceptKey -Force -ConnectionTimeout 90 -WarningAction SilentlyContinue
                }

                if ($sshSession) {
                    Write-Verbose "Connexion SSH établie (SessionId: $($sshSession.SessionId))"

                    # Créer un nouveau stream SSH avec buffer plus grand
                    $sshStream = New-SSHShellStream -Index ($sshSession.SessionId) -Columns 200 -Rows 50 -TerminalName "xterm"

                    if ($sshStream) {
                        Write-Verbose "Stream SSH créé"

                        # Récupérer la configuration avec gestion améliorée
                        $config = Get-DeviceConfig -device $device -sshStream $sshStream

                        if ($config -and $config.Count -gt 0) {
                            # Créer le fichier de backup
                            $fileName = "$($device.Name)"
                            $configsFolder = Join-Path $backupPath "configs"
                            $filePath = Join-Path $configsFolder $fileName

                            # Joindre toutes les parties de la config
                            $finalConfig = $config -join ""
                            
                            # Vérifier que le contenu n'est pas vide
                            if ($finalConfig.Trim().Length -gt 0) {
                                $finalConfig | Out-File -FilePath $filePath -Encoding UTF8
                                Write-Host "  Backup réussi pour $($device.Name) - Taille: $($finalConfig.Length) caractères" -ForegroundColor Green
                                $successCount++
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
                Write-Host "  ❌ Échec du backup de $($device.Name): $_" -ForegroundColor Red
                $failedDevices += $device.Name
            }
            finally {
                # La clé matérialisée en tmpfs ne doit pas survivre à la connexion
                if ($tempKeyFile -and (Test-Path $tempKeyFile)) {
                    Remove-Item $tempKeyFile -Force
                }

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
                        Remove-SSHSession -SessionId $sshSession.SessionId | Out-Null
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

        $summaryColor = if ($failedDevices) { 'Yellow' } else { 'Green' }
        $failedSuffix = if ($failedDevices) { " ($($failedDevices -join ', '))" } else { "" }
        Write-Host "`nBackup terminé : $successCount réussi(s), $($failedDevices.Count) échec(s)$failedSuffix" -ForegroundColor $summaryColor
    }
    catch {
        Write-Host "❌ Erreur lors de l'importation des configurations: $_" -ForegroundColor Red
    }
}

# Exécuter le backup
Backup-NetworkDevices