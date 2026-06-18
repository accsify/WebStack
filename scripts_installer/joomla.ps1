@{
    Order = 2
    Name = "Joomla (Joomla 5.2.2 stable package)"
    DbRequired = $true
    Suffix = ""
    Install = {
        param ($targetPath, $tempDir, $dbName, $dbUser, $dbPassword, $dbHost, $dbPort, $installDeps)
        
        $zipPath = "$tempDir\joomla.zip"
        Download-File "https://github.com/joomla/joomla-cms/releases/download/5.2.2/Joomla_5.2.2-Stable-Full_Package.zip" $zipPath
        Extract-Zip $zipPath $targetPath
    }
}
