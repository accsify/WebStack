# Accsify WebStack

Accsify WebStack is a professional, high-performance, and completely portable offline web development environment (WAMP stack) for Windows 10/11. Designed to run with zero installation or system modifications, it packs Apache 2.4, PHP 8.x, MySQL 8.x, and phpMyAdmin into a single self-contained directory. 

Additionally, it features an automated, optimized script installer for popular web frameworks (such as Next.js, React, Laravel, WordPress, and XenForo) and a developer command shell environment populated with aliases for Composer and Artisan.

---

# Table of Contents
{toc}
- [Description](#description)
- [Key Features](#key-features)
- [System Prerequisites](#system-prerequisites)
- [How to Install](#how-to-install)
- [Usage Guide](#usage-guide)
  - [1. Setup Manager (setup.cmd)](#1-setup-manager-setupcmd)
  - [2. Developer Shell (shell.cmd)](#2-developer-shell-shellcmd)
  - [3. Script Installer (scripts_installer.cmd)](#3-script-installer-scripts_installercmd)
- [Supported Frameworks & CMS](#supported-frameworks--cms)
- [Folder Structure](#folder-structure)
- [Author & Copyright](#author--copyright)
- [License](#license)

---

## Description

Accsify WebStack allows developers to maintain a fully portable offline localhost stack on a local folder or USB flash drive. By using native Windows automation (PowerShell 5.1+ and Batch wrappers), it handles downloads, extraction, service registration, configuration adjustments, and database provisioning natively.

It resolves common local stack issues such as complex configuration file setups, slow ZIP extractions, and manual database credentials mappings.

---

## Key Features

- **Zero Installation / Highly Portable**: Runs directly from any folder or USB drive. All configurations are automatically adjusted relative to the stack's base directory.
- **Setup Manager**: Install, update, start, stop, restart, or change options (ports, MySQL password, PHP limits) through an interactive console.
- **Windows Services Integration**: Support for registering Apache and MySQL as Windows Services to run in the background (UAC elevated securely).
- **Developer Shell**: Opens a custom terminal with local PATH variables set for PHP and MySQL, plus pre-registered DOSKEY command aliases (e.g. `composer`, `artisan`, `status`, `start-server`, `stop-server`).
- **Automated Script Installer**: Installs and auto-configures WordPress, Joomla, Laravel, XenForo, Drupal, React.js, Next.js, and Vue.js with:
  - **Fast Extraction**: Utilizes native Windows `tar.exe` when available, reducing extraction times to under 3 seconds.
  - **Database Auto-Creation**: Creates the database with clean modern collations (`utf8mb4_unicode_ci`) using the local MySQL instance.
  - **Dynamic Salts & Key Generation**: Fetches secure salts from the WordPress API and automatically executes Artisan key generation for Laravel.
- **Security Guardrails**: Features built-in directory traversal prevention checks to restrict installations strictly within the `www/` root directory.

---

## System Prerequisites

- **Operating System**: Windows 10 or Windows 11 (64-bit).
- **PowerShell**: Version 5.1 or newer (pre-installed by default on Windows 10/11).
- **Active Internet Connection**: Only required during the initial modules download (Setup Option 1) or when installing scripts (WordPress, Laravel, React, etc.).
- **Node.js & NPM** *(Optional)*: Required only if you plan to bootstrap React, Next.js, or Vue.js apps.

---

## How to Install

1. **Clone or Download** this repository into your preferred directory (e.g., `D:\web_dev`).
2. Run [setup.cmd](file:///d:/web_dev/setup.cmd) by double-clicking it.
3. Select **Option 1** (`Install / Update modules`). The script will check for the Microsoft VC++ Redistributable, download Apache, PHP, MySQL, and phpMyAdmin, and set up default configuration files.
4. Once completed, your portable stack is ready to use!

---

## Usage Guide

### 1. Setup Manager (setup.cmd)
Manage the Stack through [setup.cmd](file:///d:/web_dev/setup.cmd):
- **Option 1**: Installs, updates, or reinstalls stack components.
- **Option 2 / Option 4**: Launches Apache and MySQL. Can run as user-space background processes or interactive windows.
- **Option 5 / Option 6**: Stops or restarts servers.
- **Option 7**: Installs Apache and MySQL as auto-running Windows Services (`PortableApache` and `PortableMySQL`). This securely requests Administrator elevation.
- **Option 8**: Changes server configurations like Apache web port, MySQL port, root password, PHP limits, and **toggles Network Access** (Localhost Only vs. LAN Network Access). When Public LAN Network Access is enabled, it automatically detects your system's LAN IP address and generates the appropriate network URL (e.g. `http://192.168.1.50:port/`) so that other users on the network can access your APIs/web pages. The stack dynamically reads the port configuration from `httpd.conf` on every boot, meaning manual config file edits are automatically remembered, verified, and applied to firewall rules during server startup.

### 2. Developer Shell (shell.cmd)
Open [shell.cmd](file:///d:/web_dev/shell.cmd) to enter the custom terminal session. You can use these command line shortcuts directly:
- `setup` - Opens the main Setup Manager console.
- `installer` - Opens the automated scripts installer.
- `composer` - Runs PHP Composer package manager (utilizes root `composer.phar`).
- `artisan` - Runs Laravel Artisan utility inside your active project directory.
- `start-server` - Starts Apache and MySQL servers in the background.
- `stop-server` - Stops all running Apache and MySQL processes.
- `restart-server` - Restarts the servers.
- `status` - Displays the running state and active ports.
- `help` - Shows the shortcut guide.

### 3. Script Installer (scripts_installer.cmd)
Open [scripts_installer.cmd](file:///d:/web_dev/scripts_installer.cmd) to install and configure frameworks in your `www/` folder:
1. Choose a framework or CMS from the menu (e.g. `1` for WordPress, `3` for Laravel).
2. Enter the target folder name (e.g. `myblog` or `projects/laravel`).
3. Choose if you want to create a database. If **Y**, the script will ask for the DB name and root password, create it, and automatically write it into the app's configuration.
4. The script will automatically download the files, extract them (using `tar.exe` for speed), configure the setup (salts, `.env`, config keys), and output the local URL for you to open in your browser.

### LAN/Network Access Troubleshooting
If other devices cannot connect to your local LAN IP (e.g., getting `ERR_CONNECTION_REFUSED` or timeout):
1. **Windows Firewall**: Windows Firewall blocks inbound connection requests on Public network profiles by default.
   - If you run the setup manager as **Administrator**, it will automatically configure the firewall rules for you.
   - Otherwise, you can manually allow Apache by running this command in an **Administrator PowerShell** window:
     ```powershell
     Remove-NetFirewallRule -Name 'AccsifyWebStackApache' -ErrorAction SilentlyContinue; New-NetFirewallRule -Name 'AccsifyWebStackApache' -DisplayName 'Accsify WebStack - Apache' -Description 'Allows Apache inbound traffic' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 80 -Program 'd:\web_dev\apache24\bin\httpd.exe' -Profile Any
     ```
2. **Explicit HTTP Protocol**: Modern browsers automatically force/upgrade connections to HTTPS (port 443). Since Accsify WebStack runs HTTP (port 80) by default, you must explicitly type the `http://` prefix in your browser (e.g., `http://192.168.1.6`) to prevent connection refused errors.
3. **Restart Apache**: Ensure you restart Apache after toggling network access or changing ports.

---

## Supported Frameworks & CMS

| Option | Platform | Setup Automation |
| :--- | :--- | :--- |
| **1** | **WordPress** | Downloads latest zip, flattens subfolder, creates MySQL DB, downloads secure salts from WordPress API, and writes `wp-config.php`. |
| **2** | **Joomla** | Downloads stable Joomla 5.x Full Package, extracts, and provisions the database. |
| **3** | **Laravel** | Downloads `composer.phar` on the fly, runs `create-project`, creates DB, configures `.env` (including newer Laravel 11 commented settings), and runs `artisan key:generate`. |
| **4** | **XenForo** | Prompts for a local licensed `xenforo.zip`, extracts, flattens `upload/` files, creates DB, and generates `src/config.php`. |
| **5** | **Drupal** | Downloads latest Drupal release, extracts, flattens, and creates DB. |
| **6** | **React.js** | Checks for Node.js, creates React project via Vite, and automatically runs `npm install`. |
| **7** | **Next.js** | Checks for Node.js, runs a non-interactive `create-next-app` configured with TypeScript, TailwindCSS, App Router, and NPM. |
| **8** | **Vue.js** | Checks for Node.js, creates Vue project via Vite, and runs `npm install`. |
| **9** | **PrestaShop** | Downloads stable PrestaShop zip, extracts nested packages, and creates MySQL database. |

---

## Folder Structure

```text
d:\web_dev\
│   README.md               - Comprehensive documentation
│   setup.cmd               - Main management launcher (Batch)
│   setup.ps1               - Main management logic (PowerShell)
│   shell.cmd               - Developer command prompt with PATH and aliases
│   scripts_installer.cmd   - Scripts installer launcher (Batch)
│   scripts_installer.ps1   - Scripts installer logic (PowerShell)
│   composer.phar           - PHP package manager (auto-downloaded)
│
├───apache24\               - Apache server directory (auto-downloaded)
├───mysql\                  - MySQL server directory (auto-downloaded)
├───php\                    - PHP engine directory (auto-downloaded)
├───phpmyadmin\             - phpMyAdmin directory (auto-downloaded)
└───www\                    - Local server document root (Document Root)
```

---

## Author & Copyright

- **Author**: Nacer Baaziz
- **Organization**: [Accsify](https://github.com/accsify)
- **Copyright**: Copyright (c) 2026 Accsify. All rights reserved.

---

## License

This project is open-source software licensed under the MIT License. See the LICENSE file (if available) for more details.
