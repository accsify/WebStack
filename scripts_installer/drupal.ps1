@{
    Order = 5
    Name = "Drupal CMS (Drupal 10.3.0 stable release)"
    DbRequired = $true
    Suffix = ""
    Install = {
        param ($targetPath, $tempDir, $dbName, $dbUser, $dbPassword, $dbHost, $dbPort, $installDeps)
        
        $zipPath = "$tempDir\drupal.zip"
        Download-File "https://ftp.drupal.org/files/projects/drupal-10.3.0.zip" $zipPath
        Extract-Zip $zipPath $targetPath
        Flatten-Subfolder $targetPath
    }
}
