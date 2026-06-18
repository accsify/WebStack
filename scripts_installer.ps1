# ==============================================================================
# Accsify WebStack - Portable Offline Web Development Environment
# Copyright (c) 2026 Accsify. All rights reserved.
# Author: Nacer Baaziz
#
# This file is part of the Accsify WebStack project.
# ==============================================================================

if ($Host.Name -eq "ConsoleHost") {
    $Host.UI.RawUI.WindowTitle = "Accsify WebStack Script Installer"
}

$ProgressPreference = 'SilentlyContinue'

$BaseDir = $PSScriptRoot
if ([string]::IsNullOrEmpty($BaseDir)) {
    $BaseDir = (Get-Item -Path ".").FullName
}
$baseDirForward = $BaseDir.Replace("\", "/")

# --- STATUS HELPERS ---

function Get-Ports {
    $apachePort = 80
    $confPath = "$BaseDir\apache24\conf\httpd.conf"
    if (Test-Path $confPath) {
        $listenLine = Get-Content $confPath | Select-String -Pattern "^Listen\s+(?:.*:)?(\d+)" | Select-Object -First 1
        if ($listenLine -and $listenLine.Matches.Groups[1].Value) {
            $apachePort = $listenLine.Matches.Groups[1].Value
        }
    }
    
    $mysqlPort = 3306
    $myIniPath = "$BaseDir\mysql\my.ini"
    if (Test-Path $myIniPath) {
        $portLine = Get-Content $myIniPath | Select-String -Pattern "^\s*port\s*=\s*(\d+)" | Select-Object -First 1
        if ($portLine -and $portLine.Matches.Groups[1].Value) {
            $mysqlPort = $portLine.Matches.Groups[1].Value
        }
    }
    return @{ Apache = $apachePort; MySQL = $mysqlPort }
}

function Get-NetworkAccessState {
    $confPath = "$BaseDir\apache24\conf\httpd.conf"
    if (Test-Path $confPath) {
        $listenLine = Get-Content $confPath | Select-String -Pattern "^Listen\s+(\S+)" | Select-Object -First 1
        if ($listenLine -and $listenLine.Matches.Groups[1].Value) {
            $value = $listenLine.Matches.Groups[1].Value
            if ($value -match "127\.0\.0\.1") {
                return "Localhost Only (Private)"
            } else {
                return "LAN Network (Public)"
            }
        }
    }
    return "LAN Network (Public)"
}

function Get-LocalIPAddress {
    try {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback|vEthernet|Virtual' -and $_.IPAddress -notmatch '^169\.254\.' } | Select-Object -First 1).IPAddress
        if ([string]::IsNullOrEmpty($ip)) {
            $ip = "127.0.0.1"
        }
    } catch {
        $ip = "127.0.0.1"
    }
    return $ip
}

function Print-SuccessMessage {
    param (
        [string]$platformName,
        [string]$targetPath,
        [string]$relFolder,
        [string]$suffix = "",
        [string]$dbName = "",
        [string]$mysqlPassword = ""
    )
    $ports = Get-Ports
    $netState = Get-NetworkAccessState
    
    Write-Host "`n====================================================================" -ForegroundColor Green
    Write-Host " [+] $platformName Setup completed successfully!" -ForegroundColor Green
    Write-Host "--------------------------------------------------------------------"
    Write-Host " Target Folder:  $targetPath"
    
    $suffixClean = if ($suffix) { $suffix.TrimStart("/") } else { "" }
    
    if ($netState -eq "LAN Network (Public)") {
        $ip = Get-LocalIPAddress
        Write-Host " Local Web URL:  http://localhost:$($ports.Apache)/$relFolder/$suffixClean"
        Write-Host " LAN Access URL: http://$ip`:$($ports.Apache)/$relFolder/$suffixClean" -ForegroundColor Cyan
    } else {
        Write-Host " Web URL:        http://localhost:$($ports.Apache)/$relFolder/$suffixClean"
    }
    
    if ($dbName) {
        Write-Host " Database:       $dbName"
        Write-Host " Username/Pass:  root / $mysqlPassword"
    }
    Write-Host "====================================================================" -ForegroundColor Green
}

function Verify-StackInstalled {
    if (-not (Test-Path "$BaseDir\apache24") -or -not (Test-Path "$BaseDir\php") -or -not (Test-Path "$BaseDir\mysql")) {
        Write-Host "[!] Error: Portability stack is not fully installed. Run setup.cmd Option 1 first." -ForegroundColor Red
        Read-Host "Press Enter to exit..."
        return $false
    }
    return $true
}

function Verify-NodeInstalled {
    if (-not (Get-Command "npm" -ErrorAction SilentlyContinue) -or -not (Get-Command "node" -ErrorAction SilentlyContinue)) {
        Write-Host "[!] Error: Node.js and NPM are required for this installation." -ForegroundColor Red
        Write-Host "Please download and install Node.js from https://nodejs.org/" -ForegroundColor Yellow
        Read-Host "Press Enter to return to menu..."
        return $false
    }
    return $true
}

function Get-NpxOnlineFlag {
    try {
        $ip = [System.Net.Dns]::GetHostAddresses("registry.npmjs.org")
        if ($ip) {
            return "--prefer-offline"
        }
    } catch {}
    Write-Host "[!] Offline mode: npm registry is unreachable. Forcing offline cache use." -ForegroundColor Yellow
    return "--offline"
}

# --- DOWNLOADER & EXTRACTOR HELPERS ---

function Download-File {
    param (
        [string]$url,
        [string]$destination
    )
    Write-Host "Downloading: $url" -ForegroundColor Yellow
    
    $parentDir = Split-Path -Path $destination -Parent
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    
    try {
        Start-BitsTransfer -Source $url -Destination $destination -ErrorAction Stop
        Write-Host "[+] Download completed using BITS Transfer." -ForegroundColor Green
        return
    } catch {
        Write-Host "[*] BITS Transfer not available. Falling back to Invoke-WebRequest..." -ForegroundColor Yellow
    }
    
    $oldProgress = $ProgressPreference
    $ProgressPreference = 'Continue'
    try {
        Invoke-WebRequest -Uri $url -OutFile $destination -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
        Write-Host "[+] Download completed successfully." -ForegroundColor Green
    } catch {
        Write-Host "[!] Download failed: $_" -ForegroundColor Red
        throw $_
    } finally {
        $ProgressPreference = $oldProgress
    }
}

function Extract-Zip {
    param (
        [string]$zipPath,
        [string]$destinationPath
    )
    Write-Host "Extracting archive to $destinationPath..." -ForegroundColor Yellow
    if (-not (Test-Path $destinationPath)) {
        New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
    }
    
    try {
        if (Get-Command "tar.exe" -ErrorAction SilentlyContinue) {
            Write-Host "[*] Extracting with tar.exe (fast)..." -ForegroundColor DarkGray
            $proc = Start-Process -FilePath "tar.exe" -ArgumentList "-xf `"$zipPath`" -C `"$destinationPath`"" -NoNewWindow -PassThru -Wait
            if ($proc.ExitCode -eq 0) {
                Write-Host "[+] Extraction complete (tar)." -ForegroundColor Green
                return
            }
        }
    } catch {
        Write-Host "[*] tar.exe failed. Falling back to native Expand-Archive..." -ForegroundColor Yellow
    }
    
    try {
        Expand-Archive -Path $zipPath -DestinationPath $destinationPath -Force
        Write-Host "[+] Extraction complete (Expand-Archive)." -ForegroundColor Green
    } catch {
        Write-Host "[!] Extraction failed: $_" -ForegroundColor Red
        throw $_
    }
}

function Flatten-Subfolder {
    param (
        [string]$targetPath,
        [string]$subfolderName = $null
    )
    
    $subDir = $null
    if ([string]::IsNullOrEmpty($subfolderName)) {
        $items = Get-ChildItem -Path $targetPath
        if ($items.Count -eq 1 -and $items[0].PSIsContainer) {
            $subDir = $items[0].FullName
        }
    } else {
        $possiblePath = Join-Path $targetPath $subfolderName
        if (Test-Path $possiblePath) {
            $subDir = $possiblePath
        }
    }
    
    if ($null -ne $subDir) {
        Write-Host "Flattening subfolder structure ($($subDir | Split-Path -Leaf))..." -ForegroundColor Yellow
        Get-ChildItem -Path $subDir | ForEach-Object {
            Move-Item -Path $_.FullName -Destination $targetPath -Force
        }
        Remove-Item -Path $subDir -Force -Recurse
        Write-Host "[+] Subfolder flattened." -ForegroundColor Green
    }
}

# --- PHP CONFIG OPTIMIZER ---

function Optimize-PHPConfiguration {
    $phpIni = "$BaseDir\php\php.ini"
    if (Test-Path $phpIni) {
        $content = Get-Content $phpIni -Raw
        
        $needsUpdate = $false
        if ($content -notmatch '(?m)^error_reporting\s*=\s*E_ALL\s*&\s*~E_DEPRECATED\s*&\s*~E_STRICT') {
            $content = $content -replace '(?m)^[ \t]*;?error_reporting\s*=\s*.*$', 'error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT'
            $needsUpdate = $true
        }
        
        if ($needsUpdate) {
            $content | Set-Content $phpIni -Force
            Write-Host "[+] PHP php.ini error reporting optimized to suppress deprecation notices." -ForegroundColor Green
        }
    }
}

# --- DATABASE HELPER ---

function Create-Database {
    param (
        [string]$dbName,
        [string]$password,
        [int]$port
    )
    Write-Host "Creating MySQL database '$dbName'..." -ForegroundColor Yellow
    $mysqlExe = "$BaseDir\mysql\bin\mysql.exe"
    if (-not (Test-Path $mysqlExe)) {
        Write-Host "[!] Warning: mysql.exe not found at $mysqlExe. Database auto-creation skipped." -ForegroundColor Red
        return $false
    }
    
    $sqlCmd = "CREATE DATABASE IF NOT EXISTS ``$dbName`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    
    # Securely bind password in environment to handle special characters cleanly and safely
    $oldPassword = $env:MYSQL_PWD
    $env:MYSQL_PWD = $password
    
    $output = & $mysqlExe -u root -P $port -h 127.0.0.1 -e $sqlCmd 2>&1
    
    if ($null -ne $oldPassword) {
        $env:MYSQL_PWD = $oldPassword
    } else {
        Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue
    }
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[+] Database '$dbName' created or verified successfully." -ForegroundColor Green
        return $true
    } else {
        Write-Host "[!] Error: Failed to connect or create MySQL database '$dbName'. Make sure MySQL is running." -ForegroundColor Red
        Write-Host "MySQL Output/Error details: $output" -ForegroundColor DarkGray
        return $false
    }
}

# --- SCRIPT CONFIGURATORS ---

function Configure-WordPress {
    param (
        [string]$path,
        [string]$dbName,
        [string]$dbUser,
        [string]$dbPassword,
        [string]$dbHost
    )
    Write-Host "Configuring WordPress (wp-config.php)..." -ForegroundColor Yellow
    $sampleConfig = Join-Path $path "wp-config-sample.php"
    $configPath = Join-Path $path "wp-config.php"
    
    if (-not (Test-Path $sampleConfig)) {
        Write-Host "[!] wp-config-sample.php not found. Skipping auto-configuration." -ForegroundColor Red
        return
    }
    
    $salts = $null
    try {
        Write-Host "Fetching secure security salts from api.wordpress.org..." -ForegroundColor Yellow
        $salts = Invoke-WebRequest -Uri "https://api.wordpress.org/secret-key/1.1/salt/" -UseBasicParsing -TimeoutSec 5 | Select-Object -ExpandProperty Content
    } catch {
        Write-Host "[*] Offline mode: Generating fallback security salts..." -ForegroundColor Yellow
    }
    
    $content = Get-Content $sampleConfig -Raw
    
    $escDbName = $dbName.Replace('\', '\\').Replace("'", "\'")
    $escDbUser = $dbUser.Replace('\', '\\').Replace("'", "\'")
    $escDbPassword = $dbPassword.Replace('\', '\\').Replace("'", "\'")
    $escDbHost = $dbHost.Replace('\', '\\').Replace("'", "\'")
    
    $content = $content.Replace("database_name_here", $escDbName)
    $content = $content.Replace("username_here", $escDbUser)
    $content = $content.Replace("password_here", $escDbPassword)
    $content = $content.Replace("localhost", $escDbHost)
    
    if ($salts) {
        $pattern = '(?s)define\(\s*''AUTH_KEY''.*?define\(\s*''NONCE_SALT''.*?\);\s*'
        $content = $content -replace $pattern, $salts.Replace('$', '$$')
    } else {
        $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_ []{}<>~`+=,.;:/?|"
        $keys = @('AUTH_KEY', 'SECURE_AUTH_KEY', 'LOGGED_IN_KEY', 'NONCE_KEY', 'AUTH_SALT', 'SECURE_AUTH_SALT', 'LOGGED_IN_SALT', 'NONCE_SALT')
        foreach ($key in $keys) {
            $randSalt = -join ((1..64) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
            $randSaltEscaped = $randSalt.Replace('\', '\\').Replace("'", "\'").Replace('$', '$$')
            $content = $content -replace "define\(\s*'$key',\s*'put your unique phrase here'\s*\);", "define('$key', '$randSaltEscaped');"
        }
    }
    
    $content | Set-Content $configPath -Force
    Write-Host "[+] wp-config.php configured successfully." -ForegroundColor Green
}

function Configure-Laravel {
    param (
        [string]$path,
        [string]$dbName,
        [string]$dbUser,
        [string]$dbPassword,
        [string]$dbHost,
        [string]$dbPort
    )
    Write-Host "Configuring Laravel env settings..." -ForegroundColor Yellow
    $envExample = Join-Path $path ".env.example"
    $envPath = Join-Path $path ".env"
    
    if (-not (Test-Path $envPath)) {
        if (Test-Path $envExample) {
            Copy-Item $envExample $envPath -Force
        } else {
            Write-Host "[!] Laravel .env file not found. Skipping auto-configuration." -ForegroundColor Red
            return
        }
    }
    
    # Safely wrap environment variables containing spaces, hashes, or quotes in double quotes
    function Sanitize-EnvValue {
        param ([string]$value)
        if ($null -eq $value) { return "" }
        if ($value -match '[\s#''"$\\]') {
            $escaped = $value.Replace('\', '\\').Replace('"', '\"').Replace('$', '\$')
            return '"' + $escaped + '"'
        }
        return $value
    }
    
    $sanDbHost = Sanitize-EnvValue $dbHost
    $sanDbPort = Sanitize-EnvValue $dbPort
    $sanDbName = Sanitize-EnvValue $dbName
    $sanDbUser = Sanitize-EnvValue $dbUser
    $sanDbPassword = Sanitize-EnvValue $dbPassword
    
    $lines = Get-Content $envPath
    $updatedLines = foreach ($line in $lines) {
        if ($line -match '^\s*#?\s*DB_CONNECTION=') { "DB_CONNECTION=mysql" }
        elseif ($line -match '^\s*#?\s*DB_HOST=') { "DB_HOST=$sanDbHost" }
        elseif ($line -match '^\s*#?\s*DB_PORT=') { "DB_PORT=$sanDbPort" }
        elseif ($line -match '^\s*#?\s*DB_DATABASE=') { "DB_DATABASE=$sanDbName" }
        elseif ($line -match '^\s*#?\s*DB_USERNAME=') { "DB_USERNAME=$sanDbUser" }
        elseif ($line -match '^\s*#?\s*DB_PASSWORD=') { "DB_PASSWORD=$sanDbPassword" }
        else { $line }
    }
    $updatedLines | Set-Content $envPath -Force
    Write-Host "[+] Laravel .env file updated." -ForegroundColor Green
    
    Write-Host "Generating Laravel application key..." -ForegroundColor Yellow
    $phpExe = "$BaseDir\php\php.exe"
    if (Test-Path $phpExe) {
        Push-Location $path
        try {
            & $phpExe artisan key:generate --force
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[+] Application key generated successfully." -ForegroundColor Green
            } else {
                Write-Host "[-] Warning: Failed to generate Application key via Artisan. Exit code: $LASTEXITCODE" -ForegroundColor Red
            }
        } catch {
            Write-Host "[-] Warning: Failed to execute artisan key:generate. $_" -ForegroundColor Red
        } finally {
            Pop-Location
        }
    }
}

function Configure-XenForo {
    param (
        [string]$path,
        [string]$dbName,
        [string]$dbUser,
        [string]$dbPassword,
        [string]$dbHost,
        [string]$dbPort
    )
    Write-Host "Configuring XenForo (src/config.php)..." -ForegroundColor Yellow
    $srcDir = Join-Path $path "src"
    if (-not (Test-Path $srcDir)) {
        New-Item -ItemType Directory -Path $srcDir -Force | Out-Null
    }
    $configPath = Join-Path $srcDir "config.php"
    
    $phpDbHost = $dbHost.Replace('\', '\\').Replace("'", "\'")
    $phpDbPort = $dbPort.Replace('\', '\\').Replace("'", "\'")
    $phpDbUser = $dbUser.Replace('\', '\\').Replace("'", "\'")
    $phpDbPassword = $dbPassword.Replace('\', '\\').Replace("'", "\'")
    $phpDbName = $dbName.Replace('\', '\\').Replace("'", "\'")
    
    $configContent = @"
<?php

`$config['db']['host'] = '$phpDbHost';
`$config['db']['port'] = '$phpDbPort';
`$config['db']['username'] = '$phpDbUser';
`$config['db']['password'] = '$phpDbPassword';
`$config['db']['dbname'] = '$phpDbName';

`$config['fullUnicode'] = true;
"@
    
    $configContent | Set-Content $configPath -Force
    Write-Host "[+] XenForo config.php created successfully." -ForegroundColor Green
}

# --- DIRECTORY HANDLER ---

function Get-InstallationPath {
    while ($true) {
        Write-Host "Enter target installation folder name under 'www' (e.g. 'wordpress' or 'projects/blog'):" -ForegroundColor Cyan
        $targetInput = Read-Host "Path"
        if ($null -ne $targetInput) { $targetInput = $targetInput.Trim() }
        
        if ([string]::IsNullOrEmpty($targetInput)) {
            Write-Host "[!] Target directory cannot be empty." -ForegroundColor Red
            continue
        }
        
        $targetInput = $targetInput.Replace("/", "\").Trim("\")
        
        $targetPath = Join-Path "$BaseDir\www" $targetInput
        $resolvedPath = [System.IO.Path]::GetFullPath($targetPath)
        $wwwPath = [System.IO.Path]::GetFullPath("$BaseDir\www")
        
        if (-not $resolvedPath.StartsWith($wwwPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host "[!] Security Warning: Installation must remain inside the www folder!" -ForegroundColor Red
            continue
        }
        
        if (Test-Path $resolvedPath) {
            Write-Host "[!] Warning: Directory '$resolvedPath' already exists." -ForegroundColor Yellow
            $overwrite = Read-Host "Do you want to overwrite it? ALL existing files in it will be deleted! (Y/N)"
            if ($overwrite.Trim().ToUpper() -eq "Y") {
                Write-Host "Deleting existing files..." -ForegroundColor Yellow
                Remove-Item -Path $resolvedPath -Recurse -Force
            } else {
                continue
            }
        }
        
        return @{ Path = $resolvedPath; RelFolder = $targetInput.Replace("\", "/") }
    }
}

# --- MAIN CONTROLLER ---

function Start-Installer {
    if (-not (Verify-StackInstalled)) { return }
    
    Optimize-PHPConfiguration
    
    $ports = Get-Ports
    $tempDir = "$BaseDir\temp_installer"
    
    # 1. Discover all modular installer scripts in the scripts_installer subdirectory
    $modulesDir = Join-Path $BaseDir "scripts_installer"
    $services = @()
    if (Test-Path $modulesDir) {
        $files = Get-ChildItem -Path $modulesDir -Filter *.ps1 -File
        foreach ($file in $files) {
            try {
                $def = $null # Reset to prevent variable pollution from previous iteration
                $def = . $file.FullName
                if ($def -is [hashtable] -and $def.Name -and $def.Install -is [scriptblock]) {
                    $def.FilePath = $file.FullName
                    if ($null -eq $def.Order) { $def.Order = 99 }
                    if ($null -eq $def.DbRequired) { $def.DbRequired = $true }
                    $services += $def
                }
            } catch {
                Write-Host "[!] Warning: Failed to load module from $($file.Name): $_" -ForegroundColor Yellow
            }
        }
    }
    
    # Sort services by Order
    $services = $services | Sort-Object { $_.Order }
    
    if ($services.Length -eq 0) {
        Write-Host "[!] Error: No installer modules discovered in '$modulesDir'!" -ForegroundColor Red
        Read-Host "Press Enter to exit..."
        return
    }
    
    :MainLoop while ($true) {
        Clear-Host
        Write-Host "====================================================================" -ForegroundColor Cyan
        Write-Host " OFFLINE PORTABLE WAMP - DYNAMIC SCRIPTS INSTALLER" -ForegroundColor Cyan
        Write-Host "====================================================================" -ForegroundColor Cyan
        Write-Host " Select a script/framework to download and configure:"
        Write-Host "--------------------------------------------------------------------"
        
        $index = 1
        foreach ($svc in $services) {
            Write-Host (" {0,2}. {1}" -f $index, $svc.Name)
            $index++
        }
        Write-Host (" {0,2}. Exit" -f $index)
        Write-Host "====================================================================" -ForegroundColor Cyan
        
        $exitChoice = $index
        $choice = Read-Host "Select an option (1-$exitChoice)"
        if ($null -ne $choice) { $choice = $choice.Trim() }
        
        if ($choice -eq "$exitChoice" -or [string]::IsNullOrEmpty($choice)) {
            if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
            Write-Host "Exiting Scripts Installer." -ForegroundColor Green
            Start-Sleep -Seconds 1
            break
        }
        
        if ($choice -notmatch "^\d+$" -or [int]$choice -lt 1 -or [int]$choice -gt $exitChoice) {
            Write-Host "[!] Invalid option. Choose 1-$exitChoice." -ForegroundColor Red
            Start-Sleep -Seconds 2
            continue
        }
        
        $selectedSvc = $services[[int]$choice - 1]
        
        # Get target paths
        $folderInfo = Get-InstallationPath
        $targetPath = $folderInfo.Path
        $relFolder = $folderInfo.RelFolder
        
        # Database setup prompts
        $configureDb = "N"
        $createDb = "N"
        $dbName = ""
        $dbUser = "root"
        $dbPassword = "root"
        $installDeps = "Y"
        
        if ($selectedSvc.DbRequired) {
            $configChoice = Read-Host "Do you want to configure database settings? (Y/N) [default: Y]"
            $configureDb = if ([string]::IsNullOrEmpty($configChoice)) { "Y" } else { $configChoice.Trim().ToUpper() }
            
            if ($configureDb -eq "Y") {
                $defaultDbName = "db_" + ($relFolder -replace '[^a-zA-Z0-9]', '_').Trim('_')
                Write-Host "Enter database name [default: $defaultDbName]:"
                $dbNameInput = Read-Host "DB Name"
                $dbName = if ([string]::IsNullOrEmpty($dbNameInput)) { $defaultDbName } else { $dbNameInput.Trim() }
                
                # Sanitize database name: replace non-alphanumeric with underscores and clean up
                $dbName = ($dbName -replace '[^a-zA-Z0-9]', '_') -replace '_+', '_'
                $dbName = $dbName.Trim('_')
                if ([string]::IsNullOrEmpty($dbName)) { $dbName = $defaultDbName }
                
                Write-Host "Enter MySQL root username [default: root]:"
                $userInput = Read-Host "DB User"
                $dbUser = if ([string]::IsNullOrEmpty($userInput)) { "root" } else { $userInput.Trim() }
                
                # Sanitize database username
                $dbUser = ($dbUser -replace '[^a-zA-Z0-9]', '_') -replace '_+', '_'
                $dbUser = $dbUser.Trim('_')
                if ([string]::IsNullOrEmpty($dbUser)) { $dbUser = "root" }
 
                Write-Host "Enter MySQL root password [default: root]:"
                $passInput = Read-Host "Password"
                $dbPassword = if ([string]::IsNullOrEmpty($passInput)) { "root" } else { $passInput }
                
                $createChoice = Read-Host "Do you want to automatically create this database? (Y/N) [default: Y]"
                $createDb = if ([string]::IsNullOrEmpty($createChoice)) { "Y" } else { $createChoice.Trim().ToUpper() }
                
                if ($createDb -eq "Y") {
                    while ($true) {
                        $dbCreated = Create-Database $dbName $dbPassword $ports.MySQL
                        if ($dbCreated) {
                            break
                        } else {
                            Write-Host "[!] Error: Database creation failed!" -ForegroundColor Red
                            $retryChoice = Read-Host "Do you want to retry database creation? (Y/N - 'N' will abort the installation)"
                            if ($retryChoice.Trim().ToUpper() -ne "Y") {
                                Write-Host "Installation aborted by user." -ForegroundColor Red
                                Start-Sleep -Seconds 2
                                $dbName = ""
                                continue MainLoop
                            }
                        }
                    }
                }
            }
        } else {
            $depsChoice = Read-Host "Do you want to automatically install NPM dependencies now? (Y/N) [default: Y]"
            $installDeps = if ([string]::IsNullOrEmpty($depsChoice)) { "Y" } else { $depsChoice.Trim().ToUpper() }
        }
        
        # Ensure temp directory exists and is empty
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        
        try {
            # Execute the modular script block
            & $selectedSvc.Install $targetPath $tempDir $dbName $dbUser $dbPassword "127.0.0.1" $ports.MySQL $installDeps
            
            # Print success info
            Print-SuccessMessage $selectedSvc.Name $targetPath $relFolder $selectedSvc.Suffix $dbName $dbPassword
        } catch {
            Write-Host "[!] An error occurred during installation: $_" -ForegroundColor Red
        }
        
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
        Read-Host "Press Enter to return to main installer menu..."
    }
}

# --- RUN EXECUTION ---
Start-Installer
