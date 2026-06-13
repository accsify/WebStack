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
    
    $sqlCmd = "CREATE DATABASE IF NOT EXISTS \`$dbName\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    
    try {
        if ([string]::IsNullOrEmpty($password)) {
            & $mysqlExe -u root -P $port -h 127.0.0.1 -e $sqlCmd 2>&1 | Out-Null
        } else {
            & $mysqlExe -u root -p$password -P $port -h 127.0.0.1 -e $sqlCmd 2>&1 | Out-Null
        }
        Write-Host "[+] Database '$dbName' created or verified successfully." -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[!] Warning: Failed to connect to MySQL database to create '$dbName'. Make sure MySQL is running." -ForegroundColor Red
        Write-Host "Error Details: $_" -ForegroundColor DarkGray
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
    
    # Replace DB credentials
    $content = $content -replace "database_name_here", $dbName
    $content = $content -replace "username_here", $dbUser
    $content = $content -replace "password_here", $dbPassword
    $content = $content -replace "localhost", $dbHost
    
    # Replace salts
    if ($salts) {
        $pattern = '(?s)define\(\s*''AUTH_KEY''.*?define\(\s*''NONCE_SALT''.*?\);\s*'
        $content = $content -replace $pattern, $salts
    } else {
        $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_ []{}<>~`+=,.;:/?|"
        $keys = @('AUTH_KEY', 'SECURE_AUTH_KEY', 'LOGGED_IN_KEY', 'NONCE_KEY', 'AUTH_SALT', 'SECURE_AUTH_SALT', 'LOGGED_IN_SALT', 'NONCE_SALT')
        foreach ($key in $keys) {
            $randSalt = -join ((1..64) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
            $randSaltEscaped = $randSalt.Replace('\', '\\').Replace("'", "\'")
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
    
    # Replace DB configurations (supports commented-out lines in newer Laravel versions)
    $content = $content -replace '(?m)^#?\s*DB_CONNECTION=.*$', "DB_CONNECTION=mysql"
    $content = $content -replace '(?m)^#?\s*DB_HOST=.*$', "DB_HOST=$dbHost"
    $content = $content -replace '(?m)^#?\s*DB_PORT=.*$', "DB_PORT=$dbPort"
    $content = $content -replace '(?m)^#?\s*DB_DATABASE=.*$', "DB_DATABASE=$dbName"
    $content = $content -replace '(?m)^#?\s*DB_USERNAME=.*$', "DB_USERNAME=$dbUser"
    $content = $content -replace '(?m)^#?\s*DB_PASSWORD=.*$', "DB_PASSWORD=$dbPassword"
    
    $content | Set-Content $envPath -Force
    Write-Host "[+] Laravel .env file updated." -ForegroundColor Green
    
    Write-Host "Generating Laravel application key..." -ForegroundColor Yellow
    $phpExe = "$BaseDir\php\php.exe"
    if (Test-Path $phpExe) {
        $proc = Start-Process -FilePath $phpExe -ArgumentList "artisan key:generate" -WorkingDirectory $path -NoNewWindow -PassThru -Wait
        if ($proc.ExitCode -eq 0) {
            Write-Host "[+] Application key generated successfully." -ForegroundColor Green
        } else {
            Write-Host "[-] Warning: Failed to generate Application key via Artisan." -ForegroundColor Red
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
    
    $configContent = @"
<?php

`$config['db']['host'] = '$dbHost';
`$config['db']['port'] = '$dbPort';
`$config['db']['username'] = '$dbUser';
`$config['db']['password'] = '$dbPassword';
`$config['db']['dbname'] = '$dbName';

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
        if (-not $resolvedPath.StartsWith($wwwPath)) {
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
    
    $ports = Get-Ports
    $tempDir = "$BaseDir\temp_installer"
    
    while ($true) {
        Clear-Host
        Write-Host "====================================================================" -ForegroundColor Cyan
        Write-Host " OFFLINE PORTABLE WAMP - PROFESSIONAL SCRIPTS INSTALLER" -ForegroundColor Cyan
        Write-Host "====================================================================" -ForegroundColor Cyan
        Write-Host " Select a script/framework to download and configure:"
        Write-Host "--------------------------------------------------------------------"
        Write-Host " 1. WordPress (Latest release)"
        Write-Host " 2. Joomla (Joomla 5.x stable package)"
        Write-Host " 3. Laravel Framework (Automated project setup via Composer)"
        Write-Host " 4. XenForo Forums (Requires your own local xenforo.zip package)"
        Write-Host " 5. Drupal CMS (Latest Drupal stable release)"
        Write-Host " 6. React.js App (Fast setup via Vite + NPM)"
        Write-Host " 7. Next.js App (Production-ready via create-next-app + Tailwind)"
        Write-Host " 8. Vue.js App (Fast setup via Vite + NPM)"
        Write-Host " 9. PrestaShop (E-commerce platform)"
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
        
        if ($choice -notmatch "^[1-9]$") {
            Write-Host "[!] Invalid option. Choose 1-10." -ForegroundColor Red
            Start-Sleep -Seconds 2
            continue
        }
        
        # Get target paths
        $folderInfo = Get-InstallationPath
        $targetPath = $folderInfo.Path
        $relFolder = $folderInfo.RelFolder
        
        # Database Creation prompt (only for PHP/CMS scripts: WordPress, Joomla, Laravel, Xenforo, Drupal, PrestaShop)
        $isNodeApp = $choice -match "^[6-8]$"
        $createDb = "N"
        $dbName = ""
        $mysqlPassword = "root"
        
        if (-not $isNodeApp) {
            $createDb = Read-Host "Do you want to automatically create a MySQL database? (Y/N)"
            if ($createDb.Trim().ToUpper() -eq "Y") {
                while ($true) {
                    $defaultDbName = "db_" + ($relFolder -replace '[^a-zA-Z0-9]', '_').Trim('_')
                    Write-Host "Enter database name [default: $defaultDbName]:"
                    $dbNameInput = Read-Host "DB Name"
                    $dbName = if ([string]::IsNullOrEmpty($dbNameInput)) { $defaultDbName } else { $dbNameInput.Trim() }
                    
                    Write-Host "Enter MySQL root password [default: root]:"
                    $passInput = Read-Host "Password"
                    $mysqlPassword = if ([string]::IsNullOrEmpty($passInput)) { "root" } else { $passInput }
                    
                    $dbCreated = Create-Database $dbName $mysqlPassword $ports.MySQL
                    if ($dbCreated) {
                        break
                    } else {
                        Write-Host "[!] Error: Database creation failed!" -ForegroundColor Red
                        $retryChoice = Read-Host "Do you want to retry database creation? (Y/N - 'N' will abort the installation)"
                        if ($retryChoice.Trim().ToUpper() -ne "Y") {
                            Write-Host "Installation aborted by user." -ForegroundColor Red
                            Start-Sleep -Seconds 2
                            $dbName = ""
                            continue 2 # continue outer while loop
                        }
                    }
                }
            }
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
                    
                    if ($createDb.Trim().ToUpper() -eq "Y") {
                        Configure-WordPress $targetPath $dbName "root" $mysqlPassword "127.0.0.1:$($ports.MySQL)"
                    }
                    
                    Print-SuccessMessage "WordPress" $targetPath $relFolder "" $dbName $mysqlPassword
                }
                
                "2" {
                    # Joomla
                    $zipPath = "$tempDir\joomla.zip"
                    Download-File "https://github.com/joomla/joomla-cms/releases/download/5.1.1/Joomla_5.1.1-Stable-Full_Package.zip" $zipPath
                    Extract-Zip $zipPath $targetPath
                    
                    Print-SuccessMessage "Joomla" $targetPath $relFolder "" $dbName $mysqlPassword
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
                    
                    $proc = Start-Process -FilePath $phpExe -ArgumentList "`"$composerPhar`" create-project laravel/laravel `"$targetPath`" --prefer-dist --no-interaction" -NoNewWindow -PassThru -Wait
                    if ($proc.ExitCode -ne 0) {
                        throw "Composer project creation failed with exit code $($proc.ExitCode)."
                    }
                    
                    if ($createDb.Trim().ToUpper() -eq "Y") {
                        Configure-Laravel $targetPath $dbName "root" $mysqlPassword "127.0.0.1" $ports.MySQL
                    }
                    
                    Print-SuccessMessage "Laravel" $targetPath $relFolder "public" $dbName $mysqlPassword
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
                    
                    if ($createDb.Trim().ToUpper() -eq "Y") {
                        Configure-XenForo $targetPath $dbName "root" $mysqlPassword "127.0.0.1" $ports.MySQL
                    }
                    
                    Print-SuccessMessage "XenForo" $targetPath $relFolder "install" $dbName $mysqlPassword
                }
                
                "5" {
                    # Drupal
                    $zipPath = "$tempDir\drupal.zip"
                    Download-File "https://ftp.drupal.org/files/projects/drupal-10.2.6.zip" $zipPath
                    Extract-Zip $zipPath $targetPath
                    Flatten-Subfolder $targetPath
                    
                    Print-SuccessMessage "Drupal" $targetPath $relFolder "" $dbName $mysqlPassword
                }
                
                "6" {
                    # React.js
                    if (-not (Verify-NodeInstalled)) { continue }
                    
                    Write-Host "Creating React.js project using Vite... This may take a moment." -ForegroundColor Yellow
                    $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c npm create vite@latest `"$targetPath`" -- --template react --yes" -NoNewWindow -PassThru -Wait
                    if ($proc.ExitCode -ne 0) {
                        throw "Vite React creation failed."
                    }
                    
                    Write-Host "Installing NPM dependencies... This may take a minute." -ForegroundColor Yellow
                    $procInstall = Start-Process -FilePath "cmd.exe" -ArgumentList "/c npm install" -WorkingDirectory $targetPath -NoNewWindow -PassThru -Wait
                    if ($procInstall.ExitCode -ne 0) {
                        Write-Host "[-] Warning: npm install failed. You may need to run 'npm install' manually inside the folder." -ForegroundColor Red
                    }
                    
                    Write-Host "`n====================================================================" -ForegroundColor Green
                    Write-Host " [+] React.js Project created successfully!" -ForegroundColor Green
                    Write-Host "--------------------------------------------------------------------"
                    Write-Host " Target Folder:  $targetPath"
                    Write-Host " Next Steps:     cd $relFolder"
                    Write-Host "                 npm run dev"
                    Write-Host "                 (To run on network: npm run dev -- --host)" -ForegroundColor Cyan
                    Write-Host "====================================================================" -ForegroundColor Green
                }
                
                "7" {
                    # Next.js
                    if (-not (Verify-NodeInstalled)) { continue }
                    
                    Write-Host "Creating Next.js project... This takes a few minutes." -ForegroundColor Yellow
                    $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c npx -y create-next-app@latest `"$targetPath`" --ts --tailwind --eslint --app --src-dir --import-alias `"`@/*`"` --use-npm --no-git" -NoNewWindow -PassThru -Wait
                    if ($proc.ExitCode -ne 0) {
                        throw "Next.js creation failed."
                    }
                    
                    Write-Host "`n====================================================================" -ForegroundColor Green
                    Write-Host " [+] Next.js Project created successfully!" -ForegroundColor Green
                    Write-Host "--------------------------------------------------------------------"
                    Write-Host " Target Folder:  $targetPath"
                    Write-Host " Next Steps:     cd $relFolder"
                    Write-Host "                 npm run dev"
                    Write-Host "                 (To run on network: npm run dev -- --host)" -ForegroundColor Cyan
                    Write-Host "====================================================================" -ForegroundColor Green
                }
                
                "8" {
                    # Vue.js
                    if (-not (Verify-NodeInstalled)) { continue }
                    
                    Write-Host "Creating Vue.js project using Vite... This may take a moment." -ForegroundColor Yellow
                    $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c npm create vite@latest `"$targetPath`" -- --template vue --yes" -NoNewWindow -PassThru -Wait
                    if ($proc.ExitCode -ne 0) {
                        throw "Vite Vue creation failed."
                    }
                    
                    Write-Host "Installing NPM dependencies... This may take a minute." -ForegroundColor Yellow
                    $procInstall = Start-Process -FilePath "cmd.exe" -ArgumentList "/c npm install" -WorkingDirectory $targetPath -NoNewWindow -PassThru -Wait
                    if ($procInstall.ExitCode -ne 0) {
                        Write-Host "[-] Warning: npm install failed. You may need to run 'npm install' manually." -ForegroundColor Red
                    }
                    
                    Write-Host "`n====================================================================" -ForegroundColor Green
                    Write-Host " [+] Vue.js Project created successfully!" -ForegroundColor Green
                    Write-Host "--------------------------------------------------------------------"
                    Write-Host " Target Folder:  $targetPath"
                    Write-Host " Next Steps:     cd $relFolder"
                    Write-Host "                 npm run dev"
                    Write-Host "                 (To run on network: npm run dev -- --host)" -ForegroundColor Cyan
                    Write-Host "====================================================================" -ForegroundColor Green
                }
                
                "9" {
                    # PrestaShop
                    $zipPath = "$tempDir\prestashop.zip"
                    Download-File "https://github.com/PrestaShop/PrestaShop/releases/download/8.1.5/prestashop_8.1.5.zip" $zipPath
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
                    
                    Print-SuccessMessage "PrestaShop" $targetPath $relFolder "" $dbName $mysqlPassword
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
