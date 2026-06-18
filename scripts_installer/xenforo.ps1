@{
    Order = 4
    Name = "XenForo Forums (Requires your own local xenforo.zip package)"
    DbRequired = $true
    Suffix = "install"
    Install = {
        param ($targetPath, $tempDir, $dbName, $dbUser, $dbPassword, $dbHost, $dbPort, $installDeps)
        
        Write-Host "XenForo is a commercial product. Please provide the zip archive." -ForegroundColor Yellow
        Write-Host "Place your 'xenforo.zip' in: $BaseDir" -ForegroundColor DarkGray
        
        $zipPath = Read-Host "Enter path to xenforo.zip [default: $BaseDir\xenforo.zip]"
        if ([string]::IsNullOrEmpty($zipPath)) { $zipPath = "$BaseDir\xenforo.zip" }
        
        if (-not (Test-Path $zipPath)) {
            throw "XenForo zip archive not found at '$zipPath'!"
        }
        
        Extract-Zip $zipPath $targetPath
        
        if (Test-Path (Join-Path $targetPath "upload")) {
            Flatten-Subfolder $targetPath "upload"
        } else {
            Flatten-Subfolder $targetPath
        }
        
        if ($dbName) {
            Configure-XenForo $targetPath $dbName $dbUser $dbPassword $dbHost $dbPort
        }
    }
}
