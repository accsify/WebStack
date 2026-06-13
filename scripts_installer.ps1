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
    
    # Trim leading slash from suffix
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
    
    # Try using BITS first (fast, native progress bar)
    try {
        Start-BitsTransfer -Source $url -Destination $destination -ErrorAction Stop
        Write-Host "[+] Download completed using BITS Transfer." -ForegroundColor Green
        return
    } catch {
        Write-Host "[*] BITS Transfer not available. Falling back to Invoke-WebRequest..." -ForegroundColor Yellow
    }
    
    # Fallback to Invoke-WebRequest with progress preference enabled for visual feedback
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
    
    # Try using Windows native tar.exe first (takes seconds)
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
    
    # Fallback to slower Expand-Archive
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
    
    $output = $null
    if ([string]::IsNullOrEmpty($password)) {
        $output = & $mysqlExe -u root -P $port -h 127.0.0.1 -e $sqlCmd 2>&1
    } else {
        $output = & $mysqlExe -u root "-p$password" -P $port -h 127.0.0.1 -e $sqlCmd 2>&1
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
    
    # Fetch salts from WordPress API
    $salts = $null
    try {
        Write-Host "Fetching secure security salts from api.wordpress.org..." -ForegroundColor Yellow
        $salts = Invoke-WebRequest -Uri "https://api.wordpress.org/secret-key/1.1/salt/" -UseBasicParsing -TimeoutSec 5 | Select-Object -ExpandProperty Content
    } catch {
        Write-Host "[*] Offline mode: Generating fallback security salts..." -ForegroundColor Yellow
    }
    
    $content = Get-Content $sampleConfig -Raw
    
    # Escape DB credentials for single-quoted PHP strings
    $escDbName = $dbName.Replace('\', '\\').Replace("'", "\'")
    $escDbUser = $dbUser.Replace('\', '\\').Replace("'", "\'")
    $escDbPassword = $dbPassword.Replace('\', '\\').Replace("'", "\'")
    $escDbHost = $dbHost.Replace('\', '\\').Replace("'", "\'")
    
    # Replace DB credentials literally
    $content = $content.Replace("database_name_here", $escDbName)
    $content = $content.Replace("username_here", $escDbUser)
    $content = $content.Replace("password_here", $escDbPassword)
    $content = $content.Replace("localhost", $escDbHost)
    
    # Replace salts
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
    
    $content = Get-Content $envPath -Raw
    
    # Escape credentials for regex replacement
    $escDbHost = $dbHost.Replace('$', '$$')
    $escDbPort = $dbPort.Replace('$', '$$')
    $escDbName = $dbName.Replace('$', '$$')
    $escDbUser = $dbUser.Replace('$', '$$')
    $escDbPassword = $dbPassword.Replace('$', '$$')
    
    # Replace DB configurations (supports commented-out lines in newer Laravel versions)
    $content = $content -replace '(?m)^#?\s*DB_CONNECTION=.*$', "DB_CONNECTION=mysql"
    $content = $content -replace '(?m)^#?\s*DB_HOST=.*$', "DB_HOST=$escDbHost"
    $content = $content -replace '(?m)^#?\s*DB_PORT=.*$', "DB_PORT=$escDbPort"
    $content = $content -replace '(?m)^#?\s*DB_DATABASE=.*$', "DB_DATABASE=$escDbName"
    $content = $content -replace '(?m)^#?\s*DB_USERNAME=.*$', "DB_USERNAME=$escDbUser"
    $content = $content -replace '(?m)^#?\s*DB_PASSWORD=.*$', "DB_PASSWORD=$escDbPassword"
    
    $content | Set-Content $envPath -Force
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
    
    # Escape for single-quoted PHP strings
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
        
        # Format separators and trim
        $targetInput = $targetInput.Replace("/", "\").Trim("\")
        
        $targetPath = Join-Path "$BaseDir\www" $targetInput
        $resolvedPath = [System.IO.Path]::GetFullPath($targetPath)
        $wwwPath = [System.IO.Path]::GetFullPath("$BaseDir\www")
        
        # Directory traversal prevention check
        if (-not $resolvedPath.StartsWith($wwwPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host "[!] Security Warning: Installation must remain inside the www folder!" -ForegroundColor Red
            continue
        }
        
        # Check if already exists
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
    
    # Run PHP optimization on start to suppress deprecations
    Optimize-PHPConfiguration
    
    $ports = Get-Ports
    $tempDir = "$BaseDir\temp_installer"
    
    :MainLoop while ($true) {
        Clear-Host
        Write-Host "====================================================================" -ForegroundColor Cyan
        Write-Host " OFFLINE PORTABLE WAMP - PROFESSIONAL SCRIPTS INSTALLER" -ForegroundColor Cyan
        Write-Host "====================================================================" -ForegroundColor Cyan
        Write-Host " Select a script/framework to download and configure:"
        Write-Host "--------------------------------------------------------------------"
        Write-Host " 1. WordPress (Latest release)"
        Write-Host " 2. Joomla (Joomla 5.2.2 stable package)"
        Write-Host " 3. Laravel Framework (Automated project setup via Composer)"
        Write-Host " 4. XenForo Forums (Requires your own local xenforo.zip package)"
        Write-Host " 5. Drupal CMS (Drupal 10.3.0 stable release)"
        Write-Host " 6. React.js App (Fast setup via Vite + NPM)"
        Write-Host " 7. Next.js App (Production-ready via create-next-app + Tailwind)"
        Write-Host " 8. Vue.js App (Fast setup via Vite + NPM)"
        Write-Host " 9. PrestaShop (PrestaShop 8.1.7 stable)"
        Write-Host " 10. Exit"
        Write-Host "====================================================================" -ForegroundColor Cyan
        
        $choice = Read-Host "Select an option (1-10)"
        if ($null -ne $choice) { $choice = $choice.Trim() }
        
        if ($choice -eq "10" -or [string]::IsNullOrEmpty($choice)) {
            # Clean up temp installer folder if exists
            if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
            Write-Host "Exiting Scripts Installer." -ForegroundColor Green
            Start-Sleep -Seconds 1
            break
        }
        
        if ($choice -notmatch "^(?:[1-9]|10)$") {
            Write-Host "[!] Invalid option. Choose 1-10." -ForegroundColor Red
            Start-Sleep -Seconds 2
            continue
        }
        
        # Get target paths
        $folderInfo = Get-InstallationPath
        $targetPath = $folderInfo.Path
        $relFolder = $folderInfo.RelFolder
        
        # Database setup prompts (only for PHP/CMS scripts: WordPress, Joomla, Laravel, Xenforo, Drupal, PrestaShop)
        $isNodeApp = $choice -match "^[6-8]$"
        $configureDb = "N"
        $createDb = "N"
        $dbName = ""
        $dbUser = "root"
        $dbPassword = "root"
        $installDeps = "Y"
        
        if (-not $isNodeApp) {
            $configChoice = Read-Host "Do you want to configure database settings? (Y/N) [default: Y]"
            $configureDb = if ([string]::IsNullOrEmpty($configChoice)) { "Y" } else { $configChoice.Trim().ToUpper() }
            
            if ($configureDb -eq "Y") {
                # Determine default database name
                $defaultDbName = "db_" + ($relFolder -replace '[^a-zA-Z0-9]', '_').Trim('_')
                Write-Host "Enter database name [default: $defaultDbName]:"
                $dbNameInput = Read-Host "DB Name"
                $dbName = if ([string]::IsNullOrEmpty($dbNameInput)) { $defaultDbName } else { $dbNameInput.Trim() }
                
                Write-Host "Enter MySQL root username [default: root]:"
                $userInput = Read-Host "DB User"
                $dbUser = if ([string]::IsNullOrEmpty($userInput)) { "root" } else { $userInput.Trim() }

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
            switch ($choice) {
                "1" {
                    # WordPress
                    $zipPath = "$tempDir\wordpress.zip"
                    Download-File "https://wordpress.org/latest.zip" $zipPath
                    Extract-Zip $zipPath $targetPath
                    Flatten-Subfolder $targetPath "wordpress"
                    
                    if ($configureDb -eq "Y") {
                        Configure-WordPress $targetPath $dbName $dbUser $dbPassword "127.0.0.1:$($ports.MySQL)"
                    }
                    
                    Print-SuccessMessage "WordPress" $targetPath $relFolder "" $dbName $dbPassword
                }
                
                "2" {
                    # Joomla
                    $zipPath = "$tempDir\joomla.zip"
                    Download-File "https://github.com/joomla/joomla-cms/releases/download/5.2.2/Joomla_5.2.2-Stable-Full_Package.zip" $zipPath
                    Extract-Zip $zipPath $targetPath
                    
                    Print-SuccessMessage "Joomla" $targetPath $relFolder "" $dbName $dbPassword
                }
                
                "3" {
                    # Laravel
                    $composerPhar = "$BaseDir\composer.phar"
                    if (-not (Test-Path $composerPhar)) {
                        Write-Host "Composer is required for Laravel. Downloading composer.phar..." -ForegroundColor Yellow
                        Download-File "https://getcomposer.org/composer.phar" $composerPhar
                    }
                    
                    Write-Host "Creating Laravel project. This takes a few minutes..." -ForegroundColor Yellow
                    $phpExe = "$BaseDir\php\php.exe"
                    if (-not (Test-Path $phpExe)) {
                        throw "php.exe not found under $BaseDir\php. Cannot run Composer."
                    }
                    
                    & $phpExe $composerPhar create-project laravel/laravel $targetPath --prefer-dist --no-interaction
                    if ($LASTEXITCODE -ne 0) {
                        throw "Composer project creation failed with exit code $LASTEXITCODE."
                    }
                    
                    if ($configureDb -eq "Y") {
                        Configure-Laravel $targetPath $dbName $dbUser $dbPassword "127.0.0.1" $ports.MySQL
                    }
                    
                    Print-SuccessMessage "Laravel" $targetPath $relFolder "public" $dbName $dbPassword
                }
                
                "4" {
                    # XenForo
                    Write-Host "XenForo is a commercial product. Please provide the zip archive." -ForegroundColor Yellow
                    Write-Host "Place your 'xenforo.zip' in: $BaseDir" -ForegroundColor DarkGray
                    
                    $zipPath = Read-Host "Enter path to xenforo.zip [default: $BaseDir\xenforo.zip]"
                    if ([string]::IsNullOrEmpty($zipPath)) { $zipPath = "$BaseDir\xenforo.zip" }
                    
                    if (-not (Test-Path $zipPath)) {
                        Write-Host "[!] Error: XenForo zip archive not found at '$zipPath'!" -ForegroundColor Red
                        Read-Host "Press Enter to return..."
                        continue
                    }
                    
                    Extract-Zip $zipPath $targetPath
                    
                    # Flatten 'upload' subfolder if exists
                    if (Test-Path (Join-Path $targetPath "upload")) {
                        Flatten-Subfolder $targetPath "upload"
                    } else {
                        Flatten-Subfolder $targetPath
                    }
                    
                    if ($configureDb -eq "Y") {
                        Configure-XenForo $targetPath $dbName $dbUser $dbPassword "127.0.0.1" $ports.MySQL
                    }
                    
                    Print-SuccessMessage "XenForo" $targetPath $relFolder "install" $dbName $dbPassword
                }
                
                "5" {
                    # Drupal
                    $zipPath = "$tempDir\drupal.zip"
                    Download-File "https://ftp.drupal.org/files/projects/drupal-10.3.0.zip" $zipPath
                    Extract-Zip $zipPath $targetPath
                    Flatten-Subfolder $targetPath
                    
                    Print-SuccessMessage "Drupal" $targetPath $relFolder "" $dbName $dbPassword
                }
                
                "6" {
                    # React.js
                    if (-not (Verify-NodeInstalled)) { continue }
                    
                    Write-Host "Creating React.js project using Vite... This may take a moment." -ForegroundColor Yellow
                    cmd.exe /c "npx -y create-vite@latest `"$targetPath`" --template react"
                    if ($LASTEXITCODE -ne 0) {
                        throw "Vite React creation failed with exit code $LASTEXITCODE."
                    }
                    
                    if ($installDeps -eq "Y") {
                        Write-Host "Installing NPM dependencies... This may take a minute." -ForegroundColor Yellow
                        Push-Location $targetPath
                        try {
                            cmd.exe /c "npm install"
                            if ($LASTEXITCODE -ne 0) {
                                Write-Host "[-] Warning: npm install failed. You may need to run 'npm install' manually inside the folder." -ForegroundColor Red
                            }
                        } finally {
                            Pop-Location
                        }
                    } else {
                        Write-Host "[*] Skipping NPM dependencies installation. Run 'npm install' manually inside the project directory later." -ForegroundColor Yellow
                    }
                    
                    Write-Host "`n====================================================================" -ForegroundColor Green
                    Write-Host " [+] React.js Project created successfully!" -ForegroundColor Green
                    Write-Host "--------------------------------------------------------------------"
                    Write-Host " Target Folder:  $targetPath"
                    Write-Host " Next Steps:     cd $relFolder"
                    if ($installDeps -ne "Y") {
                        Write-Host "                 npm install" -ForegroundColor Yellow
                    }
                    Write-Host "                 npm run dev"
                    Write-Host "                 (To run on network: npm run dev -- --host)" -ForegroundColor Cyan
                    Write-Host "====================================================================" -ForegroundColor Green
                }
                
                "7" {
                    # Next.js
                    if (-not (Verify-NodeInstalled)) { continue }
                    
                    Write-Host "Creating Next.js project... This takes a few minutes." -ForegroundColor Yellow
                    $extraArgs = if ($installDeps -ne "Y") { "--skip-install" } else { "" }
                    cmd.exe /c "npx -y create-next-app@latest `"$targetPath`" --ts --tailwind --eslint --app --src-dir --import-alias `"`@/*`"` --use-npm --no-git $extraArgs"
                    if ($LASTEXITCODE -ne 0) {
                        throw "Next.js creation failed with exit code $LASTEXITCODE."
                    }
                    
                    Write-Host "`n====================================================================" -ForegroundColor Green
                    Write-Host " [+] Next.js Project created successfully!" -ForegroundColor Green
                    Write-Host "--------------------------------------------------------------------"
                    Write-Host " Target Folder:  $targetPath"
                    Write-Host " Next Steps:     cd $relFolder"
                    if ($installDeps -ne "Y") {
                        Write-Host "                 npm install" -ForegroundColor Yellow
                    }
                    Write-Host "                 npm run dev"
                    Write-Host "                 (To run on network: npm run dev -- --host)" -ForegroundColor Cyan
                    Write-Host "====================================================================" -ForegroundColor Green
                }
                
                "8" {
                    # Vue.js
                    if (-not (Verify-NodeInstalled)) { continue }
                    
                    Write-Host "Creating Vue.js project using Vite... This may take a moment." -ForegroundColor Yellow
                    cmd.exe /c "npx -y create-vite@latest `"$targetPath`" --template vue"
                    if ($LASTEXITCODE -ne 0) {
                        throw "Vite Vue creation failed with exit code $LASTEXITCODE."
                    }
                    
                    if ($installDeps -eq "Y") {
                        Write-Host "Installing NPM dependencies... This may take a minute." -ForegroundColor Yellow
                        Push-Location $targetPath
                        try {
                            cmd.exe /c "npm install"
                            if ($LASTEXITCODE -ne 0) {
                                Write-Host "[-] Warning: npm install failed. You may need to run 'npm install' manually inside the folder." -ForegroundColor Red
                            }
                        } finally {
                            Pop-Location
                        }
                    } else {
                        Write-Host "[*] Skipping NPM dependencies installation. Run 'npm install' manually inside the project directory later." -ForegroundColor Yellow
                    }
                    
                    Write-Host "`n====================================================================" -ForegroundColor Green
                    Write-Host " [+] Vue.js Project created successfully!" -ForegroundColor Green
                    Write-Host "--------------------------------------------------------------------"
                    Write-Host " Target Folder:  $targetPath"
                    Write-Host " Next Steps:     cd $relFolder"
                    if ($installDeps -ne "Y") {
                        Write-Host "                 npm install" -ForegroundColor Yellow
                    }
                    Write-Host "                 npm run dev"
                    Write-Host "                 (To run on network: npm run dev -- --host)" -ForegroundColor Cyan
                    Write-Host "====================================================================" -ForegroundColor Green
                }
                
                "9" {
                    # PrestaShop
                    $zipPath = "$tempDir\prestashop.zip"
                    Download-File "https://github.com/PrestaShop/PrestaShop/releases/download/8.1.7/prestashop_8.1.7.zip" $zipPath
                    Extract-Zip $zipPath $targetPath
                    
                    # PrestaShop zip sometimes contains an inner index.php and a prestashop.zip file inside it!
                    $innerZip = Join-Path $targetPath "prestashop.zip"
                    if (Test-Path $innerZip) {
                        Write-Host "Extracting inner PrestaShop package..." -ForegroundColor Yellow
                        Extract-Zip $innerZip $targetPath
                        Remove-Item $innerZip -Force
                        # Clean up other installer files
                        Remove-Item (Join-Path $targetPath "index.php") -Force -ErrorAction SilentlyContinue
                        Remove-Item (Join-Path $targetPath "Install_PrestaShop.html") -Force -ErrorAction SilentlyContinue
                    }
                    
                    Print-SuccessMessage "PrestaShop" $targetPath $relFolder "" $dbName $dbPassword
                }
            }
        } catch {
            Write-Host "[!] An error occurred during installation: $_" -ForegroundColor Red
        }
        
        # Clean up temp folder
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
        Read-Host "Press Enter to return to main installer menu..."
    }
}

# --- RUN EXECUTION ---
Start-Installer
