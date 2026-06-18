@{
    Order = 3
    Name = "Laravel Framework (Automated project setup via Composer)"
    DbRequired = $true
    Suffix = "public"
    Install = {
        param ($targetPath, $tempDir, $dbName, $dbUser, $dbPassword, $dbHost, $dbPort, $installDeps)
        
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
        
        if ($dbName) {
            Configure-Laravel $targetPath $dbName $dbUser $dbPassword $dbHost $dbPort
        }
    }
}
