# Sauvegarde distante optionnelle des configurations (FTP ou SMB) avec rétention.
# Configuration stockée comme les connecteurs : clixml avec mot de passe en SecureString
# dans /app/secrets/remote.xml (600). Une archive tar.gz des configs est créée en tmpfs
# puis envoyée via curl (FTP) ou smbclient (SMB) ; les identifiants transitent par des
# fichiers éphémères en tmpfs, jamais en argument de commande.
# La rétention (config.Keep) supprime les archives les plus anciennes de la destination.

$script:RemoteConfigPath = Join-Path ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".." "secrets"))) "remote.xml"

function ConvertFrom-RemoteSecureString {
    param([System.Security.SecureString]$secure)

    if (-not $secure) { return '' }
    return [System.Net.NetworkCredential]::new('', $secure).Password
}

function Import-RemoteConfig {
    if (Test-Path $script:RemoteConfigPath) {
        try {
            return Import-Clixml -Path $script:RemoteConfigPath
        } catch {
            Write-Warning "remote.xml illisible : $($_.Exception.Message)"
        }
    }
    return $null
}

function Save-RemoteConfig {
    param($config)

    $dir = Split-Path $script:RemoteConfigPath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        chmod 700 $dir
    }
    Export-Clixml -Path $script:RemoteConfigPath -InputObject $config -Depth 4
    chmod 600 $script:RemoteConfigPath
}

function Remove-RemoteConfig {
    if (Test-Path $script:RemoteConfigPath) {
        Remove-Item $script:RemoteConfigPath -Force
    }
}

# ---------------------------------------------------------------------------
# FTP (curl) — identifiants via fichier de config curl en tmpfs
# ---------------------------------------------------------------------------
function New-CurlConfigFile {
    param($config)

    $password = ConvertFrom-RemoteSecureString $config.Password
    $userValue = ("$($config.Username):$password" -replace '\\', '\\' -replace '"', '\"')
    $tmp = "/dev/shm/nbcurl-$([guid]::NewGuid().ToString('N'))"
    # ftp-skip-pasv-ip : ignore l'IP annoncée en mode passif (serveurs derrière NAT)
    Set-Content -Path $tmp -Value "user = `"$userValue`"`nftp-skip-pasv-ip"
    chmod 600 $tmp
    return $tmp
}

function Get-FtpBaseUrl {
    param($config)

    $path = ([string]$config.Path).Trim('/')
    $url = "ftp://$($config.Host):$($config.Port)/"
    if ($path) { $url += "$path/" }
    return $url
}

function Get-FtpBackupList {
    param($config)

    $curlConfig = New-CurlConfigFile $config
    try {
        $listing = curl -sS --config $curlConfig -l (Get-FtpBaseUrl $config) 2>&1
        if ($LASTEXITCODE -eq 9) {
            # Sous-dossier pas encore créé : il le sera au premier envoi (--ftp-create-dirs)
            Write-Verbose "Listing FTP : dossier inexistant, considéré vide"
            return @()
        }
        if ($LASTEXITCODE -ne 0) { throw "curl (listing FTP) : $listing" }
        return @($listing | Where-Object { $_ -match '^configs-\d{8}-\d{6}\.tar\.gz$' })
    } finally {
        Remove-Item $curlConfig -Force
    }
}

function Send-FtpBackup {
    param($config, [string]$archivePath, [string]$archiveName)

    $curlConfig = New-CurlConfigFile $config
    try {
        $output = curl -sS --config $curlConfig -T $archivePath --ftp-create-dirs "$(Get-FtpBaseUrl $config)$archiveName" 2>&1
        if ($LASTEXITCODE -ne 0) { throw "curl (envoi FTP) : $output" }
    } finally {
        Remove-Item $curlConfig -Force
    }
}

function Remove-OldFtpBackups {
    param($config)

    $keep = [int]$config.Keep
    if ($keep -lt 1) { return }

    $toDelete = @(Get-FtpBackupList $config | Sort-Object -Descending | Select-Object -Skip $keep)
    if (-not $toDelete) { return }

    $curlConfig = New-CurlConfigFile $config
    try {
        foreach ($name in $toDelete) {
            $output = curl -sS --config $curlConfig (Get-FtpBaseUrl $config) -Q "-DELE $name" -o /dev/null 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Rétention FTP : suppression de $name échouée ($output)"
            } else {
                Write-Verbose "Rétention FTP : $name supprimé"
            }
        }
    } finally {
        Remove-Item $curlConfig -Force
    }
}

# ---------------------------------------------------------------------------
# SMB (smbclient) — identifiants via fichier d'authentification en tmpfs
# ---------------------------------------------------------------------------
function New-SmbAuthFile {
    param($config)

    $password = ConvertFrom-RemoteSecureString $config.Password
    $content = "username = $($config.Username)`npassword = $password"
    if ($config.Domain) { $content += "`ndomain = $($config.Domain)" }
    $tmp = "/dev/shm/nbsmb-$([guid]::NewGuid().ToString('N'))"
    Set-Content -Path $tmp -Value $content
    chmod 600 $tmp
    return $tmp
}

function Invoke-SmbCommand {
    param($config, [string]$command)

    $authFile = New-SmbAuthFile $config
    try {
        $fullCommand = if ($config.Path) { "cd $($config.Path); $command" } else { $command }
        $output = smbclient "//$($config.Host)/$($config.Share)" -A $authFile -c $fullCommand 2>&1
        if ($LASTEXITCODE -ne 0) { throw "smbclient : $($output -join ' ')" }
        return $output
    } finally {
        Remove-Item $authFile -Force
    }
}

function Get-SmbBackupList {
    param($config)

    $output = Invoke-SmbCommand $config "ls"
    return @($output | ForEach-Object {
        if ($_ -match '(configs-\d{8}-\d{6}\.tar\.gz)') { $Matches[1] }
    })
}

function Send-SmbBackup {
    param($config, [string]$archivePath, [string]$archiveName)

    Invoke-SmbCommand $config "put $archivePath $archiveName" | Out-Null
}

function Remove-OldSmbBackups {
    param($config)

    $keep = [int]$config.Keep
    if ($keep -lt 1) { return }

    $toDelete = @(Get-SmbBackupList $config | Sort-Object -Descending | Select-Object -Skip $keep)
    if (-not $toDelete) { return }

    $deleteCommand = ($toDelete | ForEach-Object { "del $_" }) -join '; '
    Invoke-SmbCommand $config $deleteCommand | Out-Null
    $toDelete | ForEach-Object { Write-Verbose "Rétention SMB : $_ supprimé" }
}

# ---------------------------------------------------------------------------
# Points d'entrée
# ---------------------------------------------------------------------------
function Test-RemoteBackup {
    $config = Import-RemoteConfig
    if (-not $config -or $config.Type -notin @('ftp', 'smb')) {
        return "Aucune sauvegarde distante configurée."
    }

    $count = if ($config.Type -eq 'ftp') { @(Get-FtpBackupList $config).Count } else { @(Get-SmbBackupList $config).Count }
    return "Connexion $($config.Type.ToUpper()) réussie — $count archive(s) sur la destination."
}

# Appelé en fin de run de Backup-Network.ps1 : archive + envoi + rétention.
# Silencieux si aucune destination n'est configurée ; les erreurs ne font pas échouer le backup.
function Invoke-RemoteBackup {
    param([string]$configsPath)

    $config = Import-RemoteConfig
    if (-not $config -or $config.Type -notin @('ftp', 'smb')) { return }

    $archiveName = "configs-$(Get-Date -Format 'yyyyMMdd-HHmmss').tar.gz"
    $tempRoot = if (Test-Path '/dev/shm') { '/dev/shm' } else { [System.IO.Path]::GetTempPath() }
    $archivePath = Join-Path $tempRoot $archiveName

    tar -czf $archivePath -C $configsPath --exclude .svn . 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $archivePath)) {
        Write-Warning "Sauvegarde distante : impossible de créer l'archive"
        return
    }

    try {
        if ($config.Type -eq 'ftp') {
            Send-FtpBackup $config $archivePath $archiveName
            Remove-OldFtpBackups $config
        } else {
            Send-SmbBackup $config $archivePath $archiveName
            Remove-OldSmbBackups $config
        }
        Write-Host "Sauvegarde distante ($($config.Type.ToUpper())) : $archiveName envoyée (rétention : $($config.Keep) archives)"
    } catch {
        Write-Warning "Sauvegarde distante échouée : $_"
    } finally {
        Remove-Item $archivePath -Force -ErrorAction SilentlyContinue
    }
}
