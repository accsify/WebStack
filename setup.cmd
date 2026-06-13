@echo off
:: ==============================================================================
:: Accsify WebStack - Portable Offline Web Development Environment
:: Copyright (c) 2026 Accsify. All rights reserved.
:: Author: Nacer Baaziz
::
:: This file is part of the Accsify WebStack project.
:: ==============================================================================
title Accsify WebStack Manager
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
if %errorlevel% neq 0 (
    echo.
    echo Press any key to exit...
    pause >nul
)
exit /b
