@{
    Order = 7
    Name = "Next.js App (Production-ready via create-next-app + Tailwind)"
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
        
        Write-Host "Creating Next.js project... This takes a few minutes." -ForegroundColor Yellow
        $extraArgs = if ($actualInstallDeps -ne "Y") { "--skip-install" } else { "" }
        cmd.exe /c "npx $npxFlag -y create-next-app@latest `"$targetPath`" --ts --tailwind --eslint --app --src-dir --import-alias `"`@/*`"` --use-npm --no-git $extraArgs"
        if ($LASTEXITCODE -ne 0) {
            throw "Next.js creation failed with exit code $LASTEXITCODE."
        }
    }
}
