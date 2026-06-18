@{
    Order = 9
    Name = "PrestaShop (PrestaShop 8.1.7 stable)"
    DbRequired = $true
    Suffix = ""
    Install = {
        param ($targetPath, $tempDir, $dbName, $dbUser, $dbPassword, $dbHost, $dbPort, $installDeps)
        
        $zipPath = "$tempDir\prestashop.zip"
        Download-File "https://github.com/PrestaShop/PrestaShop/releases/download/8.1.7/prestashop_8.1.7.zip" $zipPath
        Extract-Zip $zipPath $targetPath
        
        $innerZip = Join-Path $targetPath "prestashop.zip"
        if (Test-Path $innerZip) {
            Write-Host "Extracting inner PrestaShop package..." -ForegroundColor Yellow
            Extract-Zip $innerZip $targetPath
            Remove-Item $innerZip -Force
            Remove-Item (Join-Path $targetPath "index.php") -Force -ErrorAction SilentlyContinue
            Remove-Item (Join-Path $targetPath "Install_PrestaShop.html") -Force -ErrorAction SilentlyContinue
        }
    }
}
