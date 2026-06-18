@{
    Order = 8
    Name = "Vue.js App (Fast setup via Vite + NPM)"
    DbRequired = $false
    Suffix = ""
    Install = {
        param ($targetPath, $tempDir, $dbName, $dbUser, $dbPassword, $dbHost, $dbPort, $installDeps)
        
        if (-not (Verify-NodeInstalled)) { return }
        
        $npxFlag = Get-NpxOnlineFlag
        $actualInstallDeps = $installDeps
        if ($npxFlag -eq "--offline") {
            $actualInstallDeps = "N"
        }
        
        Write-Host "Creating Vue.js project using Vite... This may take a moment." -ForegroundColor Yellow
        cmd.exe /c "npx $npxFlag -y create-vite@latest `"$targetPath`" --template vue"
        if ($LASTEXITCODE -ne 0) {
            throw "Vite Vue creation failed with exit code $LASTEXITCODE."
        }
        
        if ($actualInstallDeps -eq "Y") {
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
    }
}
