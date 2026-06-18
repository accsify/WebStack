@{
    Order = 1
    Name = "WordPress (Latest release)"
    DbRequired = $true
    Suffix = ""
    Install = {
        param ($targetPath, $tempDir, $dbName, $dbUser, $dbPassword, $dbHost, $dbPort, $installDeps)
        
        $zipPath = "$tempDir\wordpress.zip"
        Download-File "https://wordpress.org/latest.zip" $zipPath
        Extract-Zip $zipPath $targetPath
        Flatten-Subfolder $targetPath "wordpress"
        
        if ($dbName) {
            Configure-WordPress $targetPath $dbName $dbUser $dbPassword "${dbHost}:${dbPort}"
        }
    }
}
