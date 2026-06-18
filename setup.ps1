# ==============================================================================
# Accsify WebStack - Portable Offline Web Development Environment
# Copyright (c) 2026 Accsify. All rights reserved.
# Author: Nacer Baaziz
#
# This file is part of the Accsify WebStack project.
# ==============================================================================

if ($Host.Name -eq "ConsoleHost") {
    $Host.UI.RawUI.WindowTitle = "Accsify WebStack Manager"
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

function Get-SystemPHPPath {
    $cmd = Get-Command php.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        $binDir = Split-Path -Parent $cmd.Source
        if (Test-Path "$binDir\php.exe") {
            return $binDir
        }
    }
    $commonPaths = @(
        "C:\php",
        "C:\tools\php"
    )
    foreach ($path in $commonPaths) {
        if (Test-Path "$path\php.exe") {
            return $path
        }
    }
    return $null
}

function Get-SystemMySQLPath {
    $cmd = Get-Command mysqld.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        $binDir = Split-Path -Parent $cmd.Source
        $mysqlRoot = Split-Path -Parent $binDir
        if (Test-Path "$binDir\mysqld.exe") {
            return $mysqlRoot
        }
    }
    try {
        $service = Get-CimInstance -ClassName Win32_Service -Filter "Name LIKE '%mysql%' OR Name LIKE '%mariadb%'" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($service -and $service.PathName) {
            $pathStr = $service.PathName.Trim()
            if ($pathStr.StartsWith('"')) {
                $endQuote = $pathStr.IndexOf('"', 1)
                if ($endQuote -gt 0) {
                    $exePath = $pathStr.Substring(1, $endQuote - 1)
                } else {
                    $exePath = $pathStr.Replace('"', '')
                }
            } else {
                $exePath = ($pathStr -split "\s+")[0]
            }
            if (Test-Path $exePath) {
                $binDir = Split-Path -Parent $exePath
                $mysqlRoot = Split-Path -Parent $binDir
                return $mysqlRoot
            }
        }
    } catch {}
    
    $commonPaths = @(
        "C:\Program Files\MySQL",
        "C:\Program Files (x86)\MySQL",
        "C:\Program Files\MariaDB",
        "C:\laragon\bin\mysql"
    )
    foreach ($rootPath in $commonPaths) {
        if (Test-Path $rootPath) {
            $subFolder = Get-ChildItem -Path $rootPath -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path "$($_.FullName)\bin\mysqld.exe" } | Select-Object -First 1
            if ($subFolder) {
                return $subFolder.FullName
            }
        }
    }
    return $null
}

function Get-SystemApachePath {
    $cmd = Get-Command httpd.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        $binDir = Split-Path -Parent $cmd.Source
        $apacheRoot = Split-Path -Parent $binDir
        if (Test-Path "$binDir\httpd.exe") {
            return $apacheRoot
        }
    }
    try {
        $service = Get-CimInstance -ClassName Win32_Service -Filter "Name LIKE '%apache%' OR Name LIKE '%httpd%'" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($service -and $service.PathName) {
            $pathStr = $service.PathName.Trim()
            if ($pathStr.StartsWith('"')) {
                $endQuote = $pathStr.IndexOf('"', 1)
                if ($endQuote -gt 0) {
                    $exePath = $pathStr.Substring(1, $endQuote - 1)
                } else {
                    $exePath = $pathStr.Replace('"', '')
                }
            } else {
                $exePath = ($pathStr -split "\s+")[0]
            }
            if (Test-Path $exePath) {
                $binDir = Split-Path -Parent $exePath
                $apacheRoot = Split-Path -Parent $binDir
                return $apacheRoot
            }
        }
    } catch {}
    
    $commonPaths = @(
        "C:\Apache24",
        "C:\apache",
        "C:\laragon\bin\apache"
    )
    foreach ($path in $commonPaths) {
        if (Test-Path "$path\bin\httpd.exe") {
            return $path
        }
        if (Test-Path $path) {
            $subFolder = Get-ChildItem -Path $path -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path "$($_.FullName)\bin\httpd.exe" } | Select-Object -First 1
            if ($subFolder) {
                return $subFolder.FullName
            }
        }
    }
    return $null
}

function Get-Statuses {
    $apacheLocal = $false
    $mysqlLocal = $false
    $apacheSystem = $false
    $mysqlSystem = $false
    
    # Check httpd processes
    $httpdProcs = Get-Process -Name "httpd" -ErrorAction SilentlyContinue
    foreach ($p in $httpdProcs) {
        try {
            if ($p.Path -like "$BaseDir*") {
                $apacheLocal = $true
            } else {
                $apacheSystem = $true
            }
        } catch {
            $apacheSystem = $true
        }
    }
    
    # Check mysqld processes
    $mysqldProcs = Get-Process -Name "mysqld" -ErrorAction SilentlyContinue
    foreach ($p in $mysqldProcs) {
        try {
            if ($p.Path -like "$BaseDir*") {
                $mysqlLocal = $true
            } else {
                $mysqlSystem = $true
            }
        } catch {
            $mysqlSystem = $true
        }
    }
    
    # Check portable services
    $apacheService = Get-Service -Name "PortableApache" -ErrorAction SilentlyContinue
    if ($apacheService -and $apacheService.Status -eq "Running") {
        $apacheLocal = $true
    }
    $mysqlService = Get-Service -Name "PortableMySQL" -ErrorAction SilentlyContinue
    if ($mysqlService -and $mysqlService.Status -eq "Running") {
        $mysqlLocal = $true
    }
    
    return @{
        ApacheLocal = $apacheLocal;
        ApacheSystem = $apacheSystem;
        Apache = ($apacheLocal -or $apacheSystem);
        MySQLLocal = $mysqlLocal;
        MySQLSystem = $mysqlSystem;
        MySQL = ($mysqlLocal -or $mysqlSystem);
    }
}

function Get-SSLEnabledState {
    $conf = "$BaseDir\apache24\conf\httpd.conf"
    if (Test-Path $conf) {
        $line = Get-Content $conf | Select-String -Pattern "^Include\s+conf/extra/httpd-ssl.conf" -ErrorAction SilentlyContinue
        if ($line) {
            return $true
        }
    }
    return $false
}

function Configure-SSL-Helper {
    param (
        [bool]$ForceRegen = $false
    )
    
    $opensslPath = "$BaseDir\apache24\bin\openssl.exe"
    if (-not (Test-Path $opensslPath)) {
        Write-Host "[-] openssl.exe not found at $opensslPath. Cannot generate SSL certificates." -ForegroundColor Red
        return $false
    }
    
    $currentLanIp = Get-LocalIPAddress
    $ipFile = "$BaseDir\apache24\conf\ssl-ip.txt"
    $storedIp = ""
    if (Test-Path $ipFile) {
        $storedIp = (Get-Content $ipFile).Trim()
    }
    
    $certPath = "$BaseDir\apache24\conf\server.crt"
    $keyPath = "$BaseDir\apache24\conf\server.key"
    
    $needsRegen = $ForceRegen -or (-not (Test-Path $certPath)) -or (-not (Test-Path $keyPath)) -or ($currentLanIp -ne $storedIp)
    
    if ($needsRegen) {
        Write-Host "[*] Configuring SSL Certificate (LAN IP: $currentLanIp)..." -ForegroundColor Yellow
        
        $certDir = Split-Path -Parent $certPath
        $keyDir = Split-Path -Parent $keyPath
        if (-not (Test-Path $certDir)) { New-Item -ItemType Directory -Path $certDir -Force | Out-Null }
        if (-not (Test-Path $keyDir)) { New-Item -ItemType Directory -Path $keyDir -Force | Out-Null }
        
        $opensslCnf = "$BaseDir\apache24\conf\openssl-san.cnf"
        $altNames = @"
[alt_names]
DNS.1 = localhost
DNS.2 = 127.0.0.1
IP.1 = 127.0.0.1
"@
        if ($currentLanIp -ne "127.0.0.1") {
            $altNames += "`r`nIP.2 = $currentLanIp"
        }
        
        $cnfContent = @"
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = localhost

[v3_req]
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

$altNames
"@
        $cnfContent | Set-Content $opensslCnf -Force
        
        Write-Host "Generating private key and self-signed certificate..." -ForegroundColor Yellow
        try {
            # Copy z.dll to zlib1.dll to satisfy OpenSSL's dynamic dependency on ZLIB1.dll
            $zPath = "$BaseDir\apache24\bin\z.dll"
            $zlib1Path = "$BaseDir\apache24\bin\zlib1.dll"
            if ((Test-Path $zPath) -and (-not (Test-Path $zlib1Path))) {
                Copy-Item -Path $zPath -Destination $zlib1Path -Force -ErrorAction SilentlyContinue
            }
            
            & $opensslPath req -x509 -nodes -days 365 -newkey rsa:2048 -keyout $keyPath -out $certPath -config $opensslCnf
            if ($LASTEXITCODE -ne 0) {
                throw "OpenSSL failed with exit code $LASTEXITCODE"
            }
            $currentLanIp | Set-Content $ipFile -Force
            Write-Host "[+] SSL Certificate generated successfully for localhost and $currentLanIp." -ForegroundColor Green
        } catch {
            Write-Host "[-] Failed to generate SSL Certificate: $_" -ForegroundColor Red
            Remove-Item $opensslCnf -Force -ErrorAction SilentlyContinue
            return $false
        }
        
        Remove-Item $opensslCnf -Force -ErrorAction SilentlyContinue
        
        Write-Host "Trusting certificate locally..." -ForegroundColor Yellow
        try {
            $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            if ($isAdmin) {
                Write-Host "Elevated privileges detected. Importing to LocalMachine Root store (silent)..." -ForegroundColor Yellow
                Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -match "CN=localhost" } | Remove-Item -Confirm:$false -ErrorAction SilentlyContinue
                Import-Certificate -FilePath $certPath -CertStoreLocation Cert:\LocalMachine\Root -ErrorAction Stop | Out-Null
                Write-Host "[+] SSL Certificate trusted system-wide." -ForegroundColor Green
            } else {
                Write-Host "Non-elevated privileges. Importing to CurrentUser Root store (requires clicking 'Yes' on the Windows warning dialog)..." -ForegroundColor Yellow
                $importCode = {
                    param($certPath)
                    Get-ChildItem Cert:\CurrentUser\Root | Where-Object { $_.Subject -match "CN=localhost" } | Remove-Item -Confirm:$false -ErrorAction SilentlyContinue
                    Import-Certificate -FilePath $certPath -CertStoreLocation Cert:\CurrentUser\Root -ErrorAction Stop | Out-Null
                }
                $job = Start-Job -ScriptBlock $importCode -ArgumentList $certPath
                if ($job) {
                    $job | Wait-Job -Timeout 3 | Out-Null
                    if ($job.State -eq "Running") {
                        Write-Host "[*] Import is running in background (waiting for user confirmation)..." -ForegroundColor Yellow
                    } else {
                        Receive-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
                        Write-Host "[+] SSL Certificate trust updated." -ForegroundColor Green
                    }
                    Remove-Job -Job $job -Force
                }
            }
        } catch {
            Write-Host "[-] Failed to trust certificate locally: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[*] SSL Certificate is up-to-date for IP: $currentLanIp" -ForegroundColor Green
    }
    
    Write-Host "Enabling SSL modules in Apache httpd.conf..." -ForegroundColor Yellow
    $conf = "$BaseDir\apache24\conf\httpd.conf"
    if (Test-Path $conf) {
        $c = Get-Content $conf -Raw
        $sslUpdated = $false
        if ($c -match '(?m)^#\s*LoadModule\s+ssl_module') {
            $c = $c -replace '(?m)^#\s*LoadModule\s+ssl_module', 'LoadModule ssl_module'
            $sslUpdated = $true
        }
        if ($c -match '(?m)^#\s*LoadModule\s+socache_shmcb_module') {
            $c = $c -replace '(?m)^#\s*LoadModule\s+socache_shmcb_module', 'LoadModule socache_shmcb_module'
            $sslUpdated = $true
        }
        if ($c -match '(?m)^#\s*Include\s+conf/extra/httpd-ssl\.conf') {
            $c = $c -replace '(?m)^#\s*Include\s+conf/extra/httpd-ssl\.conf', 'Include conf/extra/httpd-ssl.conf'
            $sslUpdated = $true
        }
        if ($sslUpdated) {
            $c | Set-Content $conf -Force
            Write-Host "[+] SSL module loading enabled in httpd.conf." -ForegroundColor Green
        }
    }
    
    $sslConf = "$BaseDir\apache24\conf\extra\httpd-ssl.conf"
    if (Test-Path $sslConf) {
        $c = Get-Content $sslConf -Raw
        $c = $c -replace 'DocumentRoot\s+"[^"]*"', 'DocumentRoot "${SRVROOT}/../www"'
        $c = $c -replace 'ServerName\s+\S+', 'ServerName localhost:443'
        $c = $c -replace 'SSLCertificateFile\s+"[^"]*"', 'SSLCertificateFile "${SRVROOT}/conf/server.crt"'
        $c = $c -replace 'SSLCertificateKeyFile\s+"[^"]*"', 'SSLCertificateKeyFile "${SRVROOT}/conf/server.key"'
        $c | Set-Content $sslConf -Force
        Write-Host "[+] httpd-ssl.conf updated with correct DocumentRoot and certificate paths." -ForegroundColor Green
    }
    return $true
}


function Verify-Installed {
    if (-not (Test-Path "$BaseDir\apache24") -or -not (Test-Path "$BaseDir\php") -or -not (Test-Path "$BaseDir\mysql")) {
        Write-Host "[!] Error: Portability stack is not fully installed. Run Option 1 first." -ForegroundColor Red
        Read-Host "Press Enter to return to menu..."
        return $false
    }
    return $true
}

function Configure-Firewall {
    param (
        [string]$Action,
        [int]$Port = 80
    )
    
    $ruleName = "AccsifyWebStackApache"
    $displayName = "Accsify WebStack - Apache Web Server"
    $binaryPath = "$BaseDir\apache24\bin\httpd.exe"
    
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if ($Action -eq "Add") {
        if ($isAdmin) {
            try {
                Remove-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue | Out-Null
                New-NetFirewallRule -Name $ruleName `
                                    -DisplayName $displayName `
                                    -Description "Allows inbound HTTP traffic for Accsify WebStack Apache Web Server" `
                                    -Direction Inbound `
                                    -Action Allow `
                                    -Protocol TCP `
                                    -LocalPort $Port `
                                    -Program $binaryPath `
                                    -Profile Any `
                                    -ErrorAction Stop | Out-Null
                Write-Host "[+] Windows Firewall rule '$displayName' added successfully for port $Port." -ForegroundColor Green
            } catch {
                Write-Host "[-] Failed to configure Windows Firewall automatically: $_" -ForegroundColor Yellow
                Show-FirewallWarning -Port $Port
            }
        } else {
            Show-FirewallWarning -Port $Port
        }
    } elseif ($Action -eq "Remove") {
        if ($isAdmin) {
            try {
                Remove-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue | Out-Null
                Write-Host "[-] Windows Firewall rule '$displayName' removed." -ForegroundColor Green
            } catch {
                Write-Host "[-] Failed to remove Windows Firewall rule: $_" -ForegroundColor Yellow
            }
        }
    }
}
 
function Show-FirewallWarning {
    param (
        [int]$Port = 80
    )
    $binaryPath = "$BaseDir\apache24\bin\httpd.exe"
    Write-Host "`n[!] Windows Firewall must allow inbound traffic on port $Port." -ForegroundColor Yellow
    Write-Host "[*] To configure it, please run this command in an Administrator PowerShell window:" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "Remove-NetFirewallRule -Name 'AccsifyWebStackApache' -ErrorAction SilentlyContinue; New-NetFirewallRule -Name 'AccsifyWebStackApache' -DisplayName 'Accsify WebStack - Apache' -Description 'Allows Apache inbound traffic' -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -Program '$binaryPath' -Profile Any" -ForegroundColor White
    Write-Host "--------------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "Press Enter to continue..."
    Read-Host | Out-Null
}

function Prompt-ApacheRestart {
    $statuses = Get-Statuses
    if ($statuses.Apache) {
        Write-Host "`n[*] Apache is currently running." -ForegroundColor Yellow
        $restartChoice = Read-Host "Restart Apache now to apply the new configurations? (y/n)"
        if ($restartChoice -and $restartChoice.Trim().ToLower() -eq 'y') {
            Write-Host "Restarting Apache..." -ForegroundColor Yellow
            Restart-Server
        } else {
            Write-Host "[*] Remember to restart Apache manually to apply these changes." -ForegroundColor Yellow
            Read-Host "Press Enter to continue..." | Out-Null
        }
    }
}

function Set-MySQLPassword-Admin {
    param (
        [string]$newPassword
    )
    Write-Host "Stopping any running MySQL instances..." -ForegroundColor Yellow
    # Stop services if running
    $mysqlSvc = Get-Service -Name "PortableMySQL" -ErrorAction SilentlyContinue
    if ($mysqlSvc -and $mysqlSvc.Status -eq "Running") {
        try {
            Stop-Service -Name "PortableMySQL" -ErrorAction Stop
        } catch {
            Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"Stop-Service PortableMySQL`"" -Verb RunAs -Wait
        }
    }
    Stop-Process -Name "mysqld" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    
    $myIni = "$BaseDir\mysql\my.ini"
    $initFile = "$BaseDir\mysql\init_reset.sql"
    
    # Escape single quotes in password
    $escapedPassword = $newPassword.Replace("'", "''")
    
    # Create the init-file
    $sqlCmd = "ALTER USER 'root'@'localhost' IDENTIFIED BY '$escapedPassword';"
    $sqlCmd | Set-Content $initFile -Force
    
    Write-Host "Starting MySQL with init-file to reset password..." -ForegroundColor Yellow
    $mysqlProc = Start-Process -FilePath "$BaseDir\mysql\bin\mysqld.exe" -ArgumentList "--defaults-file=`"$myIni`" --init-file=`"$initFile`"" -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 5
    
    # Stop the temporary mysqld process
    Stop-Process -Id $mysqlProc.Id -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "mysqld" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    
    # Clean up the init-file
    Remove-Item $initFile -Force -ErrorAction SilentlyContinue
    
    Write-Host "[+] MySQL root password updated successfully to '$newPassword'!" -ForegroundColor Green
    return $true
}


# --- DASHBOARD GENERATOR ---

function Create-Dashboard {
    $dashboardContent = @'
<?php
$mysqli_conn = false;
$mysqli_error = "";
$mysql_port = "3306";

// Parse my.ini to get port
$ini_path = dirname(__DIR__) . "/mysql/my.ini";
if (file_exists($ini_path)) {
    $ini_content = file_get_contents($ini_path);
    if (preg_match('/^\s*port\s*=\s*(\d+)/m', $ini_content, $matches)) {
        $mysql_port = $matches[1];
    }
}

// Test MySQL Connection
$passwords_to_try = array("", "root");
foreach ($passwords_to_try as $pass) {
    try {
        $mysqli = @new mysqli("127.0.0.1", "root", $pass, "", $mysql_port);
        if (!$mysqli->connect_error) {
            $mysqli_conn = true;
            $mysqli->close();
            $mysqli_error = "";
            break;
        } else {
            $mysqli_error = $mysqli->connect_error;
        }
    } catch (Exception $e) {
        $mysqli_error = $e->getMessage();
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Offline WAMP Stack Dashboard</title>
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;700&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg-gradient: linear-gradient(135deg, #0f172a 0%, #1e1b4b 100%);
            --card-bg: rgba(30, 41, 59, 0.7);
            --glass-border: rgba(255, 255, 255, 0.08);
            --text-primary: #f8fafc;
            --text-secondary: #94a3b8;
            --accent-cyan: #38bdf8;
            --accent-emerald: #10b981;
            --accent-rose: #f43f5e;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: 'Outfit', sans-serif;
            background: var(--bg-gradient);
            color: var(--text-primary);
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            padding: 2rem;
            overflow-x: hidden;
        }
        .container {
            max-width: 900px;
            width: 100%;
            backdrop-filter: blur(16px);
            background: var(--card-bg);
            border: 1px solid var(--glass-border);
            border-radius: 24px;
            padding: 3rem;
            box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
            transition: transform 0.3s ease, box-shadow 0.3s ease;
        }
        .container:hover {
            transform: translateY(-4px);
            box-shadow: 0 30px 60px -10px rgba(56, 189, 248, 0.15);
        }
        h1 {
            font-size: 2.5rem;
            font-weight: 700;
            text-align: center;
            margin-bottom: 0.5rem;
            background: linear-gradient(to right, #38bdf8, #818cf8);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .subtitle {
            text-align: center;
            color: var(--text-secondary);
            font-size: 1.1rem;
            margin-bottom: 3rem;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            gap: 2rem;
            margin-bottom: 3rem;
        }
        .card {
            background: rgba(15, 23, 42, 0.4);
            border: 1px solid var(--glass-border);
            border-radius: 16px;
            padding: 2rem 1.5rem;
            text-align: center;
            transition: all 0.3s ease;
        }
        .card:hover {
            background: rgba(15, 23, 42, 0.6);
            border-color: var(--accent-cyan);
            transform: scale(1.03);
        }
        .card-title {
            font-size: 1.2rem;
            font-weight: 600;
            margin-bottom: 0.75rem;
            color: var(--text-secondary);
        }
        .card-value {
            font-size: 1.8rem;
            font-weight: 700;
            color: var(--text-primary);
            margin-bottom: 1rem;
        }
        .badge {
            display: inline-block;
            padding: 0.4rem 1rem;
            border-radius: 9999px;
            font-size: 0.85rem;
            font-weight: 600;
            text-transform: uppercase;
        }
        .badge-success { background: rgba(16, 185, 129, 0.2); color: var(--accent-emerald); border: 1px solid rgba(16, 185, 129, 0.4); }
        .badge-error { background: rgba(244, 63, 94, 0.2); color: var(--accent-rose); border: 1px solid rgba(244, 63, 94, 0.4); }
        .badge-info { background: rgba(56, 189, 248, 0.2); color: var(--accent-cyan); border: 1px solid rgba(56, 189, 248, 0.4); }
        .actions {
            display: flex;
            flex-wrap: wrap;
            justify-content: center;
            gap: 1.5rem;
        }
        .btn {
            text-decoration: none;
            color: var(--text-primary);
            background: linear-gradient(135deg, #2563eb 0%, #1d4ed8 100%);
            padding: 1rem 2rem;
            border-radius: 12px;
            font-weight: 600;
            transition: all 0.3s ease;
            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
            display: inline-flex;
            align-items: center;
            gap: 0.5rem;
        }
        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 15px -3px rgba(37, 99, 235, 0.4);
            filter: brightness(1.1);
        }
        .btn-secondary {
            background: rgba(255, 255, 255, 0.05);
            border: 1px solid var(--glass-border);
        }
        .btn-secondary:hover {
            background: rgba(255, 255, 255, 0.1);
            box-shadow: 0 10px 15px -3px rgba(255, 255, 255, 0.05);
        }
        .footer {
            margin-top: 4rem;
            color: var(--text-secondary);
            font-size: 0.9rem;
            text-align: center;
        }
        .footer a { color: var(--accent-cyan); text-decoration: none; }
        .footer a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Portable Server Environment</h1>
        <div class="subtitle">Your offline high-performance local stack is ready.</div>

        <div class="grid">
            <div class="card">
                <div class="card-title">Web Server</div>
                <div class="card-value">Apache</div>
                <span class="badge badge-success">[ RUNNING ]</span>
            </div>
            <div class="card">
                <div class="card-title">PHP Version</div>
                <div class="card-value"><?php echo PHP_VERSION; ?></div>
                <span class="badge badge-info">mod_php</span>
            </div>
            <div class="card">
                <div class="card-title">Database Port</div>
                <div class="card-value">MySQL (Port <?php echo $mysql_port; ?>)</div>
                <?php if ($mysqli_conn): ?>
                    <span class="badge badge-success">Connected</span>
                <?php else: ?>
                    <span class="badge badge-error" title="<?php echo htmlspecialchars($mysqli_error); ?>">Disconnected</span>
                <?php endif; ?>
            </div>
        </div>

        <div class="actions">
            <a href="/phpmyadmin" class="btn">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5"></path></svg>
                Open phpMyAdmin
            </a>
            <a href="http://localhost:<?php echo $_SERVER['SERVER_PORT']; ?>" class="btn btn-secondary">
                Documentation
            </a>
        </div>
    </div>
    <div class="footer">
        Managed via <code>setup.cmd</code> | Designed professionally.
    </div>
</body>
</html>
'@
    $wwwDir = "$BaseDir\www"
    if (-not (Test-Path $wwwDir)) {
        New-Item -ItemType Directory -Path $wwwDir -Force | Out-Null
    }
    $dashboardContent | Set-Content "$wwwDir\index.php" -Force
}

# --- OPTION FUNCTIONS ---

function Install-Modules {
    Clear-Host
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host " INSTALL / UPDATE PORTABLE STACK MODULES" -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
    
    # 1. VC++ Redist check
    $vcInstalled = $false
    if (Test-Path "$env:SystemRoot\System32\vcruntime140.dll") {
        $vcInstalled = $true
    }
    if (-not $vcInstalled) {
        Write-Host "[!] VC++ Redistributable (x64) is required but missing." -ForegroundColor Yellow
        Write-Host "Downloading VC++ Redistributable..."
        Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" -OutFile "$BaseDir\vc_redist.x64.exe"
        Write-Host "Installing VC++ Redistributable (please approve Administrator prompt)..." -ForegroundColor Yellow
        Start-Process -FilePath "$BaseDir\vc_redist.x64.exe" -ArgumentList "/install /quiet /norestart" -Verb RunAs -Wait
        Remove-Item "$BaseDir\vc_redist.x64.exe" -Force -ErrorAction SilentlyContinue
        if (Test-Path "$env:SystemRoot\System32\vcruntime140.dll") {
            Write-Host "[+] VC++ Redistributable installed successfully." -ForegroundColor Green
        } else {
            Write-Host "[-] VC++ Redistributable installation failed." -ForegroundColor Red
        }
    } else {
        Write-Host "  VC++ Redistributable:  [ INSTALLED ]" -ForegroundColor Green
    }
    
    # Define and clean up temp installer directory
    $tempDir = "$BaseDir\temp_installer"
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    
    Write-Host "`nPreparing stack components..."
    
    # Apache
    if (-not (Test-Path "$BaseDir\apache24")) {
        $sysApache = Get-SystemApachePath
        $apacheCopied = $false
        if ($sysApache) {
            Write-Host "`n[+] System-installed Apache detected at: $sysApache" -ForegroundColor Green
            Write-Host "Copying Apache files from system installation..." -ForegroundColor Yellow
            try {
                New-Item -ItemType Directory -Path "$tempDir\apache24" -Force | Out-Null
                Copy-Item -Path "$sysApache\*" -Destination "$tempDir\apache24" -Recurse -Force -ErrorAction Stop
                $apacheCopied = $true
                Write-Host "[+] Apache successfully copied from system." -ForegroundColor Green
            } catch {
                Write-Host "[-] Failed to copy system Apache: $_. Falling back to downloading..." -ForegroundColor Yellow
            }
        }
        
        if (-not $apacheCopied) {
            Write-Host "`nDownloading Apache..." -ForegroundColor Yellow
            $url = $null
            try {
                $page = Invoke-WebRequest -Uri "https://www.apachelounge.com/download/" -UseBasicParsing -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" -TimeoutSec 10
                $match = [regex]::Match($page.Content, 'href="([^"]*httpd-[^"]*-win64[^"]*\.zip)"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                if ($match.Success) {
                    $link = $match.Groups[1].Value
                    if ($link -notmatch "^http") {
                        if ($link.StartsWith("/")) {
                            $url = "https://www.apachelounge.com" + $link
                        } else {
                            $url = "https://www.apachelounge.com/download/" + $link
                        }
                    } else {
                        $url = $link
                    }
                }
            } catch {}
            if ($null -eq $url) {
                $url = "https://www.apachelounge.com/download/VS18/binaries/httpd-2.4.68-260610-Win64-VS18.zip"
            }
            Write-Host "URL: $url" -ForegroundColor DarkGray
            Invoke-WebRequest -Uri $url -OutFile "$tempDir\apache.zip" -UserAgent "Mozilla/5.0"
            Write-Host "Extracting Apache..." -ForegroundColor Cyan
            New-Item -ItemType Directory -Path "$tempDir\apache_extracted" -Force | Out-Null
            Expand-Archive -Path "$tempDir\apache.zip" -DestinationPath "$tempDir\apache_extracted" -Force
            $extractedFolder = Get-ChildItem -Path "$tempDir\apache_extracted" -Directory | Where-Object { $_.Name -like "Apache*" } | Select-Object -First 1
            if ($extractedFolder) {
                Move-Item -Path $extractedFolder.FullName -Destination "$tempDir\apache24" -Force
            } else {
                Move-Item -Path "$tempDir\apache_extracted" -Destination "$tempDir\apache24" -Force
            }
        }
        
        Move-Item -Path "$tempDir\apache24" -Destination "$BaseDir\apache24" -Force
    } else {
        Write-Host "[*] Apache already installed." -ForegroundColor Green
    }
    
    # PHP
    if (-not (Test-Path "$BaseDir\php")) {
        $sysPHP = Get-SystemPHPPath
        $phpCopied = $false
        if ($sysPHP) {
            Write-Host "`n[+] System-installed PHP detected at: $sysPHP" -ForegroundColor Green
            Write-Host "Copying PHP files from system installation..." -ForegroundColor Yellow
            try {
                New-Item -ItemType Directory -Path "$tempDir\php" -Force | Out-Null
                Copy-Item -Path "$sysPHP\*" -Destination "$tempDir\php" -Recurse -Force -ErrorAction Stop
                $phpCopied = $true
                Write-Host "[+] PHP successfully copied from system." -ForegroundColor Green
            } catch {
                Write-Host "[-] Failed to copy system PHP: $_. Falling back to downloading..." -ForegroundColor Yellow
            }
        }
        
        if (-not $phpCopied) {
            Write-Host "`nDownloading PHP..." -ForegroundColor Yellow
            $phpUrl = $null
            try {
                $page = Invoke-WebRequest -Uri "https://windows.php.net/download/" -UseBasicParsing -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" -TimeoutSec 10
                $matches = [regex]::Matches($page.Content, 'href="([^"]*php-\d+\.\d+\.\d+-Win32-[^"]+-x64\.zip)"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                foreach ($m in $matches) {
                    $link = $m.Groups[1].Value
                    if ($link -notmatch "-nts-") {
                        if ($link -notmatch "^http") {
                            $phpUrl = "https://windows.php.net" + $link
                        } else {
                            $phpUrl = $link
                        }
                        break
                    }
                }
            } catch {}
            if ($null -eq $phpUrl) {
                $phpUrl = "https://windows.php.net/downloads/releases/archives/php-8.3.0-Win32-vs16-x64.zip"
            }
            Write-Host "URL: $phpUrl" -ForegroundColor DarkGray
            New-Item -ItemType Directory -Path "$tempDir\php" -Force | Out-Null
            Invoke-WebRequest -Uri $phpUrl -OutFile "$tempDir\php.zip" -UserAgent "Mozilla/5.0"
            Write-Host "Extracting PHP..." -ForegroundColor Cyan
            Expand-Archive -Path "$tempDir\php.zip" -DestinationPath "$tempDir\php" -Force
        }
        
        Move-Item -Path "$tempDir\php" -Destination "$BaseDir\php" -Force
    } else {
        Write-Host "[*] PHP already installed." -ForegroundColor Green
    }
    
    # MySQL
    if (-not (Test-Path "$BaseDir\mysql")) {
        $sysMySQL = Get-SystemMySQLPath
        $mysqlCopied = $false
        if ($sysMySQL) {
            Write-Host "`n[+] System-installed MySQL detected at: $sysMySQL" -ForegroundColor Green
            Write-Host "Copying MySQL files from system installation (excluding data folder)..." -ForegroundColor Yellow
            try {
                New-Item -ItemType Directory -Path "$tempDir\mysql" -Force | Out-Null
                Get-ChildItem -Path $sysMySQL -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "data" -and $_.Name -ne "Uploads" } | ForEach-Object {
                    Copy-Item -Path $_.FullName -Destination "$tempDir\mysql" -Recurse -Force -ErrorAction Stop
                }
                $mysqlCopied = $true
                Write-Host "[+] MySQL successfully copied from system." -ForegroundColor Green
            } catch {
                Write-Host "[-] Failed to copy system MySQL: $_. Falling back to downloading..." -ForegroundColor Yellow
            }
        }
        
        if (-not $mysqlCopied) {
            Write-Host "`nDownloading MySQL..." -ForegroundColor Yellow
            $mysqlUrl = "https://mirrors.dotsrc.org/mysql/Downloads/MySQL-8.0/mysql-8.0.28-winx64.zip"
            Write-Host "URL: $mysqlUrl" -ForegroundColor DarkGray
            try {
                Invoke-WebRequest -Uri $mysqlUrl -OutFile "$tempDir\mysql.zip" -UserAgent "Mozilla/5.0" -ErrorAction Stop
            } catch {
                Write-Host "Mirror download failed. Trying official archive backup..." -ForegroundColor Yellow
                $mysqlUrl = "https://downloads.mysql.com/get/Downloads/MySQL-8.0/mysql-8.0.37-winx64.zip"
                Invoke-WebRequest -Uri $mysqlUrl -OutFile "$tempDir\mysql.zip" -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" -ErrorAction Stop
            }
            Write-Host "Extracting MySQL..." -ForegroundColor Cyan
            New-Item -ItemType Directory -Path "$tempDir\mysql_extracted" -Force | Out-Null
            Expand-Archive -Path "$tempDir\mysql.zip" -DestinationPath "$tempDir\mysql_extracted" -Force
            $mysqlFolder = Get-ChildItem -Path "$tempDir\mysql_extracted" -Directory | Where-Object { $_.Name -like "mysql-*" } | Select-Object -First 1
            if ($mysqlFolder) {
                Move-Item -Path $mysqlFolder.FullName -Destination "$tempDir\mysql" -Force
            } else {
                Move-Item -Path "$tempDir\mysql_extracted" -Destination "$tempDir\mysql" -Force
            }
        }
        
        Move-Item -Path "$tempDir\mysql" -Destination "$BaseDir\mysql" -Force
    } else {
        Write-Host "[*] MySQL already installed." -ForegroundColor Green
    }
    
    # phpMyAdmin
    if (-not (Test-Path "$BaseDir\phpmyadmin")) {
        Write-Host "`nDownloading phpMyAdmin..." -ForegroundColor Yellow
        $pmaUrl = "https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.zip"
        Write-Host "URL: $pmaUrl" -ForegroundColor DarkGray
        Invoke-WebRequest -Uri $pmaUrl -OutFile "$tempDir\pma.zip" -UserAgent "Mozilla/5.0"
        Write-Host "Extracting phpMyAdmin..." -ForegroundColor Cyan
        New-Item -ItemType Directory -Path "$tempDir\pma_extracted" -Force | Out-Null
        Expand-Archive -Path "$tempDir\pma.zip" -DestinationPath "$tempDir\pma_extracted" -Force
        $pmaFolder = Get-ChildItem -Path "$tempDir\pma_extracted" -Directory | Where-Object { $_.Name -like "phpMyAdmin-*" } | Select-Object -First 1
        if ($pmaFolder) {
            Move-Item -Path $pmaFolder.FullName -Destination "$tempDir\phpmyadmin" -Force
        } else {
            Move-Item -Path "$tempDir\pma_extracted" -Destination "$tempDir\phpmyadmin" -Force
        }
        Move-Item -Path "$tempDir\phpmyadmin" -Destination "$BaseDir\phpmyadmin" -Force
    } else {
        Write-Host "[*] phpMyAdmin already installed." -ForegroundColor Green
    }
    
    # Cleanup temp folder
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # www
    if (-not (Test-Path "$BaseDir\www")) {
        New-Item -ItemType Directory -Path "$BaseDir\www" -Force | Out-Null
    }
    
    # Configure PHP
    $phpIni = "$BaseDir\php\php.ini"
    if (Test-Path "$BaseDir\php\php.ini-development") {
        Copy-Item "$BaseDir\php\php.ini-development" $phpIni -Force
    }
    if (Test-Path $phpIni) {
        $content = Get-Content $phpIni -Raw
        $content = $content -replace '(?m)^[ \t]*;?extension_dir\s*=\s*\S+', "extension_dir = `"$baseDirForward/php/ext`""
        
        $exts = @('curl', 'fileinfo', 'gd', 'intl', 'mbstring', 'exif', 'mysqli', 'openssl', 'pdo_mysql', 'pdo_sqlite', 'sqlite3', 'sodium', 'zip', 'bz2', 'soap', 'gmp')
        foreach ($ext in $exts) {
            $content = $content -replace "(?m)^[ \t]*;?extension\s*=\s*$ext", "extension=$ext"
        }
        $content = $content -replace '(?m)^[ \t]*;?upload_max_filesize\s*=\s*\S+', 'upload_max_filesize = 128M'
        $content = $content -replace '(?m)^[ \t]*;?post_max_size\s*=\s*\S+', 'post_max_size = 128M'
        $content = $content -replace '(?m)^[ \t]*;?memory_limit\s*=\s*\S+', 'memory_limit = 512M'
        $content = $content -replace '(?m)^[ \t]*;?max_execution_time\s*=\s*\S+', 'max_execution_time = 300'
        $content = $content -replace '(?m)^[ \t]*;?max_input_time\s*=\s*\S+', 'max_input_time = 300'
        
        if ($content -match 'max_input_vars') {
            $content = $content -replace '(?m)^[ \t]*;?max_input_vars\s*=\s*\S+', 'max_input_vars = 5000'
        } else {
            $content += "`r`nmax_input_vars = 5000`r`n"
        }
        
        $content = $content -replace '(?m)^[ \t]*;?error_reporting\s*=\s*.*$', 'error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT'
        $content | Set-Content $phpIni -Force
        Write-Host "[+] PHP php.ini configured with all necessary extensions and limits." -ForegroundColor Green
    }
    
    # Configure Apache
    $confPath = "$BaseDir\apache24\conf\httpd.conf"
    if (Test-Path $confPath) {
        $content = Get-Content $confPath -Raw
        $content = $content -replace 'Define SRVROOT "c:/Apache24"', "Define SRVROOT `"$baseDirForward/apache24`""
        $content = $content -replace 'DocumentRoot "\$\{SRVROOT\}/htdocs"', "DocumentRoot `"$baseDirForward/www`""
        $content = $content -replace '<Directory "\$\{SRVROOT\}/htdocs">', "<Directory `"$baseDirForward/www`">"
        $content = $content -replace 'DirectoryIndex index.html', 'DirectoryIndex index.php index.html'
        
        # Enable URL rewriting and key modules for frameworks like Laravel/WordPress
        $modules = @('rewrite_module', 'headers_module', 'expires_module', 'deflate_module')
        foreach ($mod in $modules) {
            $content = $content -replace "#\s*LoadModule\s+$mod", "LoadModule $mod"
        }
        # Enable AllowOverride All in the DocumentRoot Directory block
        $content = $content -replace '(?si)(<Directory\s+"[^"]*www">.*?AllowOverride\s+)None', '${1}All'
        
        # Clean up any existing PHP Integration block to avoid duplicate configurations
        $content = $content -replace '(?s)(?:\r?\n)?\s*# PHP Integration.*?</Directory>\s*', ''
        
        $phpDll = Get-ChildItem -Path "$BaseDir\php" -Filter "php*apache2_4.dll" | Select-Object -First 1 -ExpandProperty Name
        if (-not $phpDll) { $phpDll = "php8apache2_4.dll" }
        $libcrypto = Get-ChildItem -Path "$BaseDir\php" -Filter "libcrypto*.dll" | Select-Object -First 1 -ExpandProperty Name
        if (-not $libcrypto) { $libcrypto = "libcrypto-3-x64.dll" }
        $libssl = Get-ChildItem -Path "$BaseDir\php" -Filter "libssl*.dll" | Select-Object -First 1 -ExpandProperty Name
        if (-not $libssl) { $libssl = "libssl-3-x64.dll" }
        
        $dependencies = @(
            "brotlicommon.dll",
            "brotlidec.dll",
            "libzstd.dll",
            "nghttp2.dll",
            $libcrypto,
            $libssl,
            "libssh2.dll"
        )
        
        $loadFiles = ""
        foreach ($dep in $dependencies) {
            if (Test-Path "$BaseDir\php\$dep") {
                $loadFiles += "LoadFile `"`$`{SRVROOT}/../php/$dep`"`r`n"
            }
        }
        
        $phpBlock = @"
 
# PHP Integration
$loadFiles`LoadModule php_module "`$`{SRVROOT}/../php/$phpDll"
AddHandler application/x-httpd-php .php
PHPIniDir "`$`{SRVROOT}/../php"
 
# phpMyAdmin Alias
Alias /phpmyadmin "`$`{SRVROOT}/../phpmyadmin"
<Directory "`$`{SRVROOT}/../phpmyadmin">
    Options Indexes FollowSymLinks MultiViews
    AllowOverride All
    Require all granted
</Directory>
"@
        $content += "`r`n" + $phpBlock
        $content | Set-Content $confPath
        Write-Host "[+] Apache httpd.conf configured (mod_rewrite and AllowOverride All enabled)." -ForegroundColor Green
    }
    
    # Configure MySQL
    $myIni = "$BaseDir\mysql\my.ini"
    if (-not (Test-Path $myIni)) {
        $mysqlDirForward = "$baseDirForward/mysql"
        $myIniContent = @"
[mysqld]
port = 3306
basedir = "$mysqlDirForward"
datadir = "$mysqlDirForward/data"
default_authentication_plugin = mysql_native_password
max_allowed_packet = 64M
sql_mode = "NO_ENGINE_SUBSTITUTION"
 
[client]
port = 3306
"@
        $myIniContent | Set-Content $myIni
        Write-Host "[+] MySQL my.ini configured." -ForegroundColor Green
    }
    
    # Initialize MySQL
    if (-not (Test-Path "$BaseDir\mysql\data\mysql")) {
        New-Item -ItemType Directory -Path "$BaseDir\mysql\data" -Force | Out-Null
        Write-Host "Initializing MySQL database (insecure mode)..." -ForegroundColor Yellow
        $proc = Start-Process -FilePath "$BaseDir\mysql\bin\mysqld.exe" -ArgumentList "--defaults-file=`"$BaseDir\mysql\my.ini`" --initialize-insecure" -NoNewWindow -PassThru
        $proc.WaitForExit()
        Write-Host "[+] MySQL initialized." -ForegroundColor Green
        
        # Automatically set root password to 'root'
        Write-Host "Setting default MySQL root password to 'root'..." -ForegroundColor Yellow
        Set-MySQLPassword-Admin "root"
    }
    
    # Configure phpMyAdmin
    $pmaConfig = "$BaseDir\phpmyadmin\config.inc.php"
    if (Test-Path "$BaseDir\phpmyadmin\config.sample.inc.php") {
        Copy-Item "$BaseDir\phpmyadmin\config.sample.inc.php" $pmaConfig -Force
        $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        $secretEscaped = -join ((1..32) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
        $content = Get-Content $pmaConfig -Raw
        $mysqlPort = 3306
        if (Test-Path "$BaseDir\mysql\my.ini") {
            $portLine = Get-Content "$BaseDir\mysql\my.ini" | Select-String -Pattern "^\s*port\s*=\s*(\d+)" | Select-Object -First 1
            if ($portLine) { $mysqlPort = $portLine.Matches.Groups[1].Value }
        }
        $content = $content -replace "\['blowfish_secret'\] = ''", "['blowfish_secret'] = '$secretEscaped'"
        $content = $content -replace "\['host'\] = 'localhost'", "['host'] = '127.0.0.1';`r`n`$cfg['Servers'][`$i]['port'] = '$mysqlPort';"
        $content = $content -replace "\['AllowNoPassword'\] = false;", "['AllowNoPassword'] = true;"
        $content | Set-Content $pmaConfig -Force
        Write-Host "[+] phpMyAdmin configured." -ForegroundColor Green
    }
    
    # Create dashboard
    Create-Dashboard
    
    Write-Host "`n[+] Installation and Configuration complete!" -ForegroundColor Green
    Read-Host "Press Enter to return to menu..."
}

function Run-Server-Interactive {
    if (-not (Verify-Installed)) { return }
    Clear-Host
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host " RUN SERVER IN INTERACTIVE MODE" -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
    
    $ports = Get-Ports
    $state = Get-NetworkAccessState
    
    if (Get-SSLEnabledState) {
        Configure-SSL-Helper
    }
    
    $statuses = Get-Statuses
    $apacheRunningOnPort = $false
    $mysqlRunningOnPort = $false
    
    if ($statuses.ApacheLocal) {
        $apacheRunningOnPort = $true
    } else {
        $apacheConn = Get-NetTCPConnection -LocalPort $ports.Apache -ErrorAction SilentlyContinue
        if ($apacheConn) {
            if ($statuses.ApacheSystem) {
                Write-Host "[*] Apache port $($ports.Apache) is occupied by system Apache. Using it." -ForegroundColor Green
                $apacheRunningOnPort = $true
            } else {
                Write-Host "[!] Error: Apache port $($ports.Apache) is occupied by another program." -ForegroundColor Red
                Read-Host "Press Enter to return..."
                return
            }
        }
    }
    
    if ($statuses.MySQLLocal) {
        $mysqlRunningOnPort = $true
    } else {
        $mysqlConn = Get-NetTCPConnection -LocalPort $ports.MySQL -ErrorAction SilentlyContinue
        if ($mysqlConn) {
            if ($statuses.MySQLSystem) {
                Write-Host "[*] MySQL port $($ports.MySQL) is occupied by system MySQL. Using it." -ForegroundColor Green
                $mysqlRunningOnPort = $true
            } else {
                Write-Host "[!] Error: MySQL port $($ports.MySQL) is occupied by another program." -ForegroundColor Red
                Read-Host "Press Enter to return..."
                return
            }
        }
    }
    
    if ($state -ne "Localhost Only (Private)" -and -not $apacheRunningOnPort) {
        Configure-Firewall -Action "Add" -Port $ports.Apache
    }
    
    if (-not $apacheRunningOnPort) {
        Write-Host "Starting Apache in minimized window..."
        Start-Process -FilePath "$BaseDir\apache24\bin\httpd.exe" -WindowStyle Minimized
        Start-Sleep -Seconds 1
    }
    
    if (-not $mysqlRunningOnPort) {
        Write-Host "Starting MySQL in minimized window..."
        Start-Process -FilePath "$BaseDir\mysql\bin\mysqld.exe" -ArgumentList "--defaults-file=`"$BaseDir\mysql\my.ini`"" -WindowStyle Minimized
        Start-Sleep -Seconds 2
    }
    
    Write-Host "[+] Servers active/launched in minimized windows." -ForegroundColor Green
    Read-Host "Press Enter to return to menu..."
}

function Open-Cli {
    Clear-Host
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host " CLI ENVIRONMENT TERMINAL" -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "Opening a new Command Prompt session with local PATH populated for PHP and MySQL..."
    
    $cmdString = "set `"PATH=$BaseDir\php;$BaseDir\mysql\bin;%PATH%`" && cls && echo ========================================================== && echo  PORTABLE STACK ENVIRONMENT TERMINAL && echo ========================================================== && echo  PHP and MySQL are added to this session's PATH. && echo. && echo  PHP Version: && php -v | findstr /b `"PHP`" && echo  MySQL Version: && mysql --version && echo =========================================================="
    Start-Process -FilePath "cmd.exe" -ArgumentList "/k `"$cmdString`""
    
    Start-Sleep -Seconds 1
}

function Start-Server {
    if (-not (Verify-Installed)) { return }
    Clear-Host
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host " START SERVER" -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
    
    $ports = Get-Ports
    $state = Get-NetworkAccessState
    
    if (Get-SSLEnabledState) {
        Configure-SSL-Helper
    }
    
    $statuses = Get-Statuses
    $apacheRunningOnPort = $false
    $mysqlRunningOnPort = $false
    
    # Check if local is running or if port is occupied
    if ($statuses.ApacheLocal) {
        $apacheRunningOnPort = $true
    } else {
        $apacheConn = Get-NetTCPConnection -LocalPort $ports.Apache -ErrorAction SilentlyContinue
        if ($apacheConn) {
            if ($statuses.ApacheSystem) {
                Write-Host "[*] Apache port $($ports.Apache) is occupied by system Apache. Using it." -ForegroundColor Green
                $apacheRunningOnPort = $true
            } else {
                Write-Host "[!] Error: Apache port $($ports.Apache) is occupied by another program." -ForegroundColor Red
                Read-Host "Press Enter to return..."
                return
            }
        }
    }
    
    if ($statuses.MySQLLocal) {
        $mysqlRunningOnPort = $true
    } else {
        $mysqlConn = Get-NetTCPConnection -LocalPort $ports.MySQL -ErrorAction SilentlyContinue
        if ($mysqlConn) {
            if ($statuses.MySQLSystem) {
                Write-Host "[*] MySQL port $($ports.MySQL) is occupied by system MySQL. Using it." -ForegroundColor Green
                $mysqlRunningOnPort = $true
            } else {
                Write-Host "[!] Error: MySQL port $($ports.MySQL) is occupied by another program." -ForegroundColor Red
                Read-Host "Press Enter to return..."
                return
            }
        }
    }
    
    if ($apacheRunningOnPort -and $mysqlRunningOnPort) {
        Write-Host "[*] Servers are already running (or active via system)." -ForegroundColor Yellow
        Read-Host "Press Enter to return..."
        return
    }
    
    # Check if services exist
    $apacheSvc = Get-Service -Name "PortableApache" -ErrorAction SilentlyContinue
    $mysqlSvc = Get-Service -Name "PortableMySQL" -ErrorAction SilentlyContinue
    
    if ($apacheSvc -and $mysqlSvc) {
        Write-Host "Starting Apache and MySQL Services (requires elevation)..." -ForegroundColor Yellow
        
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if ($state -ne "Localhost Only (Private)" -and $isAdmin -and -not $apacheRunningOnPort) {
            Configure-Firewall -Action "Add" -Port $ports.Apache
        }
        
        try {
            $svcsToStart = @()
            if (-not $apacheRunningOnPort) { $svcsToStart += "PortableApache" }
            if (-not $mysqlRunningOnPort) { $svcsToStart += "PortableMySQL" }
            if ($svcsToStart.Length -gt 0) {
                Start-Service -Name $svcsToStart -ErrorAction Stop
            }
            Write-Host "[+] Auto-run services started successfully." -ForegroundColor Green
        } catch {
            Write-Host "[!] Failed to start services. Requesting elevation..." -ForegroundColor Yellow
            $cmdLine = ""
            if (-not $apacheRunningOnPort) { $cmdLine += "Start-Service PortableApache;" }
            if (-not $mysqlRunningOnPort) { $cmdLine += "Start-Service PortableMySQL;" }
            if ($cmdLine) {
                Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$cmdLine`"" -Verb RunAs -Wait
            }
        }
        Start-Sleep -Seconds 2
        return
    }
    
    if ($state -ne "Localhost Only (Private)" -and -not $apacheRunningOnPort) {
        Configure-Firewall -Action "Add" -Port $ports.Apache
    }
    
    if (-not $apacheRunningOnPort) {
        Write-Host "Starting Apache in background..."
        Start-Process -FilePath "$BaseDir\apache24\bin\httpd.exe" -WindowStyle Hidden
        Start-Sleep -Seconds 1
    }
    
    if (-not $mysqlRunningOnPort) {
        Write-Host "Starting MySQL in background..."
        Start-Process -FilePath "$BaseDir\mysql\bin\mysqld.exe" -ArgumentList "--defaults-file=`"$BaseDir\mysql\my.ini`"" -WindowStyle Hidden
        Start-Sleep -Seconds 2
    }
    
    Write-Host "[+] Servers started in background (hidden processes)." -ForegroundColor Green
    Start-Sleep -Seconds 2
}

function Stop-Server {
    Clear-Host
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host " STOP SERVER" -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
    
    # Stop services if they exist
    $apacheSvc = Get-Service -Name "PortableApache" -ErrorAction SilentlyContinue
    if ($apacheSvc) {
        Write-Host "Stopping Services..." -ForegroundColor Yellow
        try {
            Stop-Service -Name "PortableApache", "PortableMySQL" -ErrorAction Stop
        } catch {
            Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"Stop-Service PortableApache, PortableMySQL`"" -Verb RunAs -Wait
        }
    }
    
    # Kill user-space processes only if they run from $BaseDir to avoid killing system ones
    Write-Host "Stopping stack user-space processes..." -ForegroundColor Yellow
    Get-Process -Name "httpd" -ErrorAction SilentlyContinue | Where-Object {
        try {
            $_.Path -like "$BaseDir*"
        } catch { $false }
    } | Stop-Process -Force -ErrorAction SilentlyContinue
    
    Get-Process -Name "mysqld" -ErrorAction SilentlyContinue | Where-Object {
        try {
            $_.Path -like "$BaseDir*"
        } catch { $false }
    } | Stop-Process -Force -ErrorAction SilentlyContinue
    
    Write-Host "[+] Server components stopped successfully." -ForegroundColor Green
    Start-Sleep -Seconds 2
}

function Restart-Server {
    Stop-Server
    Start-Server
}

function Setup-AutoRun {
    if (-not (Verify-Installed)) { return }
    Clear-Host
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host " SETUP AUTO RUN WITH SYSTEM" -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host " Registers Apache and MySQL as Windows Services."
    Write-Host " Note: Requires Administrator privileges (UAC prompt will appear)." -ForegroundColor Red
    Write-Host "--------------------------------------------------------------------"
    Write-Host " 1. Enable Auto-Run (Install & Start Services)"
    Write-Host " 2. Disable Auto-Run (Stop & Uninstall Services)"
    Write-Host " 3. Back to Main Menu"
    Write-Host "--------------------------------------------------------------------"
    $arChoice = Read-Host "Select an option (1-3)"
    if ($null -ne $arChoice) { $arChoice = $arChoice.Trim() }
    
    if ($arChoice -eq "1") {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            Write-Host "[*] Requesting Administrator elevation to install services..." -ForegroundColor Yellow
            $scriptPath = $PSCommandPath
            Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" --install-services" -Verb RunAs -Wait
        } else {
            Install-Services-Worker
        }
    } elseif ($arChoice -eq "2") {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            Write-Host "[*] Requesting Administrator elevation to remove services..." -ForegroundColor Yellow
            $scriptPath = $PSCommandPath
            Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" --remove-services" -Verb RunAs -Wait
        } else {
            Remove-Services-Worker
        }
    }
}

function Install-Services-Worker {
    Write-Host "Installing Auto-Run Services..."
    Stop-Process -Name "httpd" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "mysqld" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    
    # Install Apache Service
    Write-Host "Installing Apache Service..."
    Start-Process -FilePath "$BaseDir\apache24\bin\httpd.exe" -ArgumentList "-k install -n `"PortableApache`"" -Wait
    Set-Service -Name "PortableApache" -StartupType Automatic
    
    # Install MySQL Service
    Write-Host "Installing MySQL Service..."
    Start-Process -FilePath "$BaseDir\mysql\bin\mysqld.exe" -ArgumentList "--install `"PortableMySQL`" --defaults-file=`"$BaseDir\mysql\my.ini`"" -Wait
    Set-Service -Name "PortableMySQL" -StartupType Automatic
    
    # Start services
    Write-Host "Starting services..."
    Start-Service -Name "PortableApache", "PortableMySQL"
    
    # Configure firewall rule if network access is public
    $ports = Get-Ports
    $state = Get-NetworkAccessState
    if ($state -ne "Localhost Only (Private)") {
        Configure-Firewall -Action "Add" -Port $ports.Apache
    }
    
    Write-Host "[+] Auto-run services installed and started successfully!" -ForegroundColor Green
    Read-Host "Press Enter to continue..."
}

function Remove-Services-Worker {
    Write-Host "Removing Auto-Run Services..."
    Write-Host "Stopping services..."
    Stop-Service -Name "PortableApache", "PortableMySQL" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    
    # Uninstall Apache Service
    Write-Host "Uninstalling Apache Service..."
    Start-Process -FilePath "$BaseDir\apache24\bin\httpd.exe" -ArgumentList "-k uninstall -n `"PortableApache`"" -Wait
    
    # Uninstall MySQL Service
    Write-Host "Uninstalling MySQL Service..."
    Start-Process -FilePath "sc.exe" -ArgumentList "delete PortableMySQL" -Wait
    
    Write-Host "[-] Auto-run services removed successfully." -ForegroundColor Green
    Read-Host "Press Enter to continue..."
}

function Change-Options {
    if (-not (Verify-Installed)) { return }
    while ($true) {
        Clear-Host
        $ports = Get-Ports
        $netState = Get-NetworkAccessState
        $sslState = if (Get-SSLEnabledState) { "Enabled" } else { "Disabled" }
        Write-Host "====================================================================" -ForegroundColor Cyan
        Write-Host " CONFIGURATION OPTIONS MANAGEMENT" -ForegroundColor Cyan
        Write-Host "====================================================================" -ForegroundColor Cyan
        Write-Host " 1. Change Apache Web Port (Current: $($ports.Apache))"
        Write-Host " 2. Change MySQL Port (Current: $($ports.MySQL))"
        Write-Host " 3. Change / Set MySQL Root Password"
        Write-Host " 4. Modify PHP limits (Memory Limit, Execution Time)"
        Write-Host " 5. Toggle Network Access (Current: $netState)"
        Write-Host " 6. Enable / Configure SSL (HTTPS) (Current: $sslState)"
        Write-Host " 7. Back to Main Menu"
        Write-Host "--------------------------------------------------------------------"
        $optChoice = Read-Host "Select an option (1-7)"
        if ($null -ne $optChoice) { $optChoice = $optChoice.Trim() }
        
        switch ($optChoice) {
            "1" {
                $newPort = Read-Host "Enter new Apache Port (1-65535)"
                if ($newPort -match "^\d+$" -and [int]$newPort -ge 1 -and [int]$newPort -le 65535) {
                    $conf = "$BaseDir\apache24\conf\httpd.conf"
                    $c = Get-Content $conf -Raw
                    $state = Get-NetworkAccessState
                    if ($state -eq "Localhost Only (Private)") {
                        $c = $c -replace '(?m)^Listen\s+\S+', "Listen 127.0.0.1:$newPort"
                    } else {
                        $c = $c -replace '(?m)^Listen\s+\S+', "Listen $newPort"
                    }
                    $c = $c -replace '(?m)^ServerName\s+localhost:\d+', "ServerName localhost:$newPort"
                    $c | Set-Content $conf -Force
                    Write-Host "[+] Apache port updated to $newPort." -ForegroundColor Green
                    
                    if ($state -ne "Localhost Only (Private)") {
                        Configure-Firewall -Action "Add" -Port $newPort
                    }
                    Prompt-ApacheRestart
                } else {
                    Write-Host "[!] Invalid port number. Must be between 1 and 65535." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                }
            }
            "2" {
                $newPort = Read-Host "Enter new MySQL Port (1-65535)"
                if ($newPort -match "^\d+$") {
                    $ini = "$BaseDir\mysql\my.ini"
                    $c = Get-Content $ini
                    $c = $c -replace '^port\s*=\s*\d+', "port = $newPort"
                    $c | Set-Content $ini
                    
                    $pma = "$BaseDir\phpmyadmin\config.inc.php"
                    if (Test-Path $pma) {
                        $c = Get-Content $pma
                        if ($c -match "\['port'\]") {
                            $c = $c -replace "\['port'\]\s*=\s*'\d+'", "['port'] = '$newPort'"
                        } else {
                            $c = $c -replace "\['host'\]\s*=\s*'127.0.0.1'", "['host'] = '127.0.0.1';`r`n`$cfg['Servers'][`$i]['port'] = '$newPort'"
                        }
                        $c | Set-Content $pma
                    }
                    Write-Host "[+] MySQL port updated to $newPort. Please restart the server." -ForegroundColor Green
                } else {
                    Write-Host "[!] Invalid port number." -ForegroundColor Red
                }
                Start-Sleep -Seconds 2
            }
            "3" {
                $newPass = Read-Host "Enter new MySQL Root Password"
                if ($null -ne $newPass) { $newPass = $newPass.Trim() }
                if ([string]::IsNullOrEmpty($newPass)) {
                    Write-Host "[!] Password cannot be empty." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                    continue
                }
                $statuses = Get-Statuses
                $wasRunning = $statuses.MySQL
                
                Set-MySQLPassword-Admin $newPass
                
                if ($wasRunning) {
                    Write-Host "Restarting MySQL server..." -ForegroundColor Yellow
                    Start-Server
                }
                Read-Host "Press Enter to continue..."
            }
            "4" {
                Clear-Host
                Write-Host "====================================================================" -ForegroundColor Cyan
                Write-Host " MODIFY PHP LIMITS" -ForegroundColor Cyan
                Write-Host "====================================================================" -ForegroundColor Cyan
                Write-Host " 1. Memory Limit (e.g. 256M, 512M, 1G)"
                Write-Host " 2. Max Execution Time (seconds)"
                Write-Host " 3. Back"
                $phpOpt = Read-Host "Select choice"
                if ($null -ne $phpOpt) { $phpOpt = $phpOpt.Trim() }
                if ($phpOpt -eq "1") {
                    $mem = Read-Host "Enter memory limit (e.g. 512M)"
                    $ini = "$BaseDir\php\php.ini"
                    $c = Get-Content $ini -Raw
                    $c = $c -replace '(?m)^[ \t]*memory_limit\s*=\s*\S+', "memory_limit = $mem"
                    $c | Set-Content $ini -Force
                    Write-Host "[+] Memory limit set to $mem" -ForegroundColor Green
                    Start-Sleep -Seconds 2
                } elseif ($phpOpt -eq "2") {
                    $time = Read-Host "Enter max execution time (seconds)"
                    $ini = "$BaseDir\php\php.ini"
                    $c = Get-Content $ini -Raw
                    $c = $c -replace '(?m)^[ \t]*max_execution_time\s*=\s*\d+', "max_execution_time = $time"
                    $c | Set-Content $ini -Force
                    Write-Host "[+] Max execution time set to $time seconds." -ForegroundColor Green
                    Start-Sleep -Seconds 2
                }
            }
            "5" {
                $conf = "$BaseDir\apache24\conf\httpd.conf"
                $c = Get-Content $conf -Raw
                $ports = Get-Ports
                $state = Get-NetworkAccessState
                
                if ($state -eq "Localhost Only (Private)") {
                    # Toggle to LAN Network (Public)
                    $c = $c -replace '(?m)^Listen\s+\S+', "Listen $($ports.Apache)"
                    $c | Set-Content $conf -Force
                    Write-Host "[+] Network Access updated to LAN Network (Public). Apache will listen on all interfaces." -ForegroundColor Green
                    Configure-Firewall -Action "Add" -Port $ports.Apache
                } else {
                    # Toggle to Localhost Only (Private)
                    $c = $c -replace '(?m)^Listen\s+\S+', "Listen 127.0.0.1:$($ports.Apache)"
                    $c | Set-Content $conf -Force
                    Write-Host "[+] Network Access updated to Localhost Only (Private). Apache will listen on 127.0.0.1." -ForegroundColor Green
                    Configure-Firewall -Action "Remove"
                }
                Prompt-ApacheRestart
            }
            "6" {
                Clear-Host
                Write-Host "====================================================================" -ForegroundColor Cyan
                Write-Host " CONFIGURE SSL (HTTPS)" -ForegroundColor Cyan
                Write-Host "====================================================================" -ForegroundColor Cyan
                Write-Host "Current Status: $sslState"
                Write-Host " 1. Enable / Regenerate SSL Certificate (Localhost & dynamic LAN IP)"
                Write-Host " 2. Disable SSL (HTTPS)"
                Write-Host " 3. Back"
                Write-Host "--------------------------------------------------------------------"
                $sslChoice = Read-Host "Select choice (1-3)"
                if ($null -ne $sslChoice) { $sslChoice = $sslChoice.Trim() }
                
                if ($sslChoice -eq "1") {
                    $res = Configure-SSL-Helper -ForceRegen $true
                    if ($res) {
                        Prompt-ApacheRestart
                    } else {
                        Read-Host "Press Enter to continue..." | Out-Null
                    }
                } elseif ($sslChoice -eq "2") {
                    Write-Host "Disabling SSL modules in Apache httpd.conf..." -ForegroundColor Yellow
                    $conf = "$BaseDir\apache24\conf\httpd.conf"
                    if (Test-Path $conf) {
                        $c = Get-Content $conf -Raw
                        $c = $c -replace '(?m)^LoadModule ssl_module', '#LoadModule ssl_module'
                        $c = $c -replace '(?m)^LoadModule socache_shmcb_module', '#LoadModule socache_shmcb_module'
                        $c = $c -replace '(?m)^Include conf/extra/httpd-ssl.conf', '#Include conf/extra/httpd-ssl.conf'
                        $c | Set-Content $conf -Force
                        Write-Host "[+] SSL disabled in httpd.conf." -ForegroundColor Green
                        Prompt-ApacheRestart
                    }
                }
            }
            "7" { return }
        }
    }
}

# --- MAIN LOOP ---

function Show-Menu {
    Clear-Host
    $ports = Get-Ports
    $statuses = Get-Statuses
    
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host " PORTABLE OFFLINE SERVER MANAGEMENT DASHBOARD" -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host " Base Directory: $BaseDir"
    Write-Host "--------------------------------------------------------------------"
    
    if ($statuses.Apache) {
        $netState = Get-NetworkAccessState
        $suffix = if ($statuses.ApacheSystem -and -not $statuses.ApacheLocal) { " (System)" } else { "" }
        if ($netState -eq "LAN Network (Public)") {
            $ip = Get-LocalIPAddress
            Write-Host "  Apache Web Server: [ RUNNING ] on port $($ports.Apache) (Public LAN)$suffix" -ForegroundColor Green
            Write-Host "                     LAN Access URL: http://$ip`:$($ports.Apache)/" -ForegroundColor Cyan
        } else {
            Write-Host "  Apache Web Server: [ RUNNING ] on port $($ports.Apache) (Local Only)$suffix" -ForegroundColor Green
        }
    } else {
        Write-Host "  Apache Web Server: [ STOPPED ]" -ForegroundColor Red
    }
    
    if ($statuses.MySQL) {
        $suffix = if ($statuses.MySQLSystem -and -not $statuses.MySQLLocal) { " (System)" } else { "" }
        Write-Host "  MySQL Database:   [ RUNNING ] on port $($ports.MySQL)$suffix" -ForegroundColor Green
    } else {
        Write-Host "  MySQL Database:   [ STOPPED ]" -ForegroundColor Red
    }
    
    Write-Host "--------------------------------------------------------------------"
    Write-Host " 1." -NoNewline -ForegroundColor Yellow; Write-Host " Install / Update modules (Apache, MySQL, PHP, phpMyAdmin)"
    Write-Host " 2." -NoNewline -ForegroundColor Yellow; Write-Host " Run Server (Interactive Console / Background Process)"
    Write-Host " 3." -NoNewline -ForegroundColor Yellow; Write-Host " Open CLI Environment (Local PHP/MySQL Session PATH)"
    Write-Host " 4." -NoNewline -ForegroundColor Yellow; Write-Host " Start Server"
    Write-Host " 5." -NoNewline -ForegroundColor Yellow; Write-Host " Stop Server"
    Write-Host " 6." -NoNewline -ForegroundColor Yellow; Write-Host " Restart Server"
    Write-Host " 7." -NoNewline -ForegroundColor Yellow; Write-Host " Setup Auto Run with System (Windows Services)"
    Write-Host " 8." -NoNewline -ForegroundColor Yellow; Write-Host " Change Options (Ports, Root Password, PHP settings)"
    Write-Host " 9." -NoNewline -ForegroundColor Yellow; Write-Host " Exit"
    Write-Host "====================================================================" -ForegroundColor Cyan
}

# Handle CLI arguments and flags
if ($args -contains "--install-services") {
    Install-Services-Worker
    exit
}
if ($args -contains "--remove-services") {
    Remove-Services-Worker
    exit
}
if ($args -contains "--start") {
    Start-Server
    exit
}
if ($args -contains "--stop") {
    Stop-Server
    exit
}
if ($args -contains "--restart") {
    Restart-Server
    exit
}
if ($args -contains "--ssl") {
    Configure-SSL-Helper -ForceRegen $true
    exit
}
if ($args -contains "--status") {
    $ports = Get-Ports
    $statuses = Get-Statuses
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host " ACCSIFY WEBSTACK RUNNING STATUS" -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
    if ($statuses.Apache) {
        $netState = Get-NetworkAccessState
        if ($netState -eq "LAN Network (Public)") {
            $ip = Get-LocalIPAddress
            Write-Host "  Apache Web Server: [ RUNNING ] on port $($ports.Apache) (Public LAN)" -ForegroundColor Green
            Write-Host "                     LAN Access URL: http://$ip`:$($ports.Apache)/" -ForegroundColor Cyan
        } else {
            Write-Host "  Apache Web Server: [ RUNNING ] on port $($ports.Apache) (Local Only)" -ForegroundColor Green
        }
    } else {
        Write-Host "  Apache Web Server: [ STOPPED ]" -ForegroundColor Red
    }
    if ($statuses.MySQL) {
        Write-Host "  MySQL Database:   [ RUNNING ] on port $($ports.MySQL)" -ForegroundColor Green
    } else {
        Write-Host "  MySQL Database:   [ STOPPED ]" -ForegroundColor Red
    }
    Write-Host "====================================================================" -ForegroundColor Cyan
    exit
}

while ($true) {
    Show-Menu
    $choice = Read-Host "Select an option (1-9)"
    if ($null -ne $choice) { $choice = $choice.Trim() }
    switch ($choice) {
        "1" { Install-Modules }
        "2" { Run-Server-Interactive }
        "3" { Open-Cli }
        "4" { Start-Server }
        "5" { Stop-Server }
        "6" { Restart-Server }
        "7" { Setup-AutoRun }
        "8" { Change-Options }
        "9" { Write-Host "Goodbye!" -ForegroundColor Green; Start-Sleep -Seconds 1; exit }
        default { Write-Host "Invalid choice. Please select 1-9." -ForegroundColor Red; Start-Sleep -Seconds 2 }
    }
}
