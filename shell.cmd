@echo off
:: ==============================================================================
:: Accsify WebStack - Portable Offline Web Development Environment
:: Copyright (c) 2026 Accsify. All rights reserved.
:: Author: Nacer Baaziz
::
:: This file is part of the Accsify WebStack project.
:: ==============================================================================
title Accsify WebStack Shell Environment
setlocal
cd /d "%~dp0"

:: Set local path for this shell session only
set "PATH=%~dp0php;%~dp0mysql\bin;%PATH%"

:: Register session commands and shortcuts
doskey composer=php "%~dp0composer.phar" $*
doskey artisan=php artisan $*
doskey setup="%~dp0setup.cmd"
doskey installer="%~dp0scripts_installer.cmd"
doskey start-server=powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" --start
doskey stop-server=powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" --stop
doskey restart-server=powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" --restart
doskey status=powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" --status
doskey help=echo ========================================================== ^& echo  ACCSIFY WEBSTACK SHORTCUTS: ^& echo ---------------------------------------------------------- ^& echo  setup           - Open main stack setup manager ^& echo  installer       - Open automated script installer ^& echo  composer        - Run PHP Composer package manager ^& echo  artisan         - Run Laravel artisan (in project folder) ^& echo  start-server    - Start Apache and MySQL in background ^& echo  stop-server     - Stop Apache and MySQL background processes ^& echo  restart-server  - Restart Apache and MySQL services ^& echo  status          - View stack running status and ports ^& echo  help            - View this shortcut list ^& echo ==========================================================

:: Clear and show welcoming header
cls
echo ==========================================================
echo  ACCSIFY WEBSTACK DEVELOPER SHELL
echo ==========================================================
echo  PHP and MySQL are added to this session's PATH.
echo  You can run: php, mysql, mysqladmin, mysqld, etc.
echo.
echo  Type 'help' to see a list of WebStack command shortcuts.
echo ----------------------------------------------------------
echo  PHP Version:
php -v 2>nul | findstr /b "PHP"
if %errorlevel% neq 0 echo   [!] PHP is not installed yet. Run 'setup' to install modules.
echo.
echo  MySQL Version:
mysql --version 2>nul
if %errorlevel% neq 0 echo   [!] MySQL is not installed yet. Run 'setup' to install modules.
echo ==========================================================
echo.

cmd /k
