<?php
# ==============================================================================
# Accsify WebStack - Portal Dashboard Welcome Page
# Copyright (c) 2026 Accsify. All rights reserved.
# Author: Nacer Baaziz
#
# This file is part of the Accsify WebStack project.
# ==============================================================================

$mysqli_conn = false;
$mysqli_error = "";
$mysql_port = "3306";

// Parse my.ini to get port
$ini_path = dirname(__DIR__) . "/mysql/my.ini";
if (file_exists($ini_path)) {
    $ini_content = file_get_contents($ini_path);
    if (preg_match('/^\s*port\s*=\s*(\d+)/m', $ini_content, $matches)) {
        $mysql_port = $matches[1];
    }
}

// Test MySQL Connection
$passwords_to_try = array("", "root");
foreach ($passwords_to_try as $pass) {
    try {
        $mysqli = @new mysqli("127.0.0.1", "root", $pass, "", $mysql_port);
        if (!$mysqli->connect_error) {
            $mysqli_conn = true;
            $mysqli->close();
            $mysqli_error = "";
            break;
        } else {
            $mysqli_error = $mysqli->connect_error;
        }
    } catch (Exception $e) {
        $mysqli_error = $e->getMessage();
    }
}

// Check PHP Extensions
$required_extensions = array(
    "curl"      => "cURL Integration",
    "openssl"   => "OpenSSL Encryption",
    "mbstring"  => "Multibyte String",
    "mysqli"    => "MySQL Improved",
    "pdo_mysql" => "PDO MySQL Driver",
    "fileinfo"  => "File Info Utility",
    "gd"        => "GD Graphics Library"
);

// Scan for local web projects in www/
$projects = array();
$www_dir = __DIR__;
if (is_dir($www_dir)) {
    $items = scandir($www_dir);
    foreach ($items as $item) {
        if ($item !== '.' && $item !== '..' && is_dir($www_dir . '/' . $item) && $item !== 'phpmyadmin') {
            $project_path = $www_dir . '/' . $item;
            $type = 'Static Website';
            $icon = '🌐';
            $badge_class = 'badge-secondary';
            
            // Detect framework or CMS
            if (file_exists($project_path . '/wp-config.php') || file_exists($project_path . '/wp-settings.php')) {
                $type = 'WordPress';
                $icon = '📝';
                $badge_class = 'badge-wordpress';
            } elseif (file_exists($project_path . '/artisan') || file_exists($project_path . '/bootstrap/app.php')) {
                $type = 'Laravel';
                $icon = '⚡';
                $badge_class = 'badge-laravel';
            } elseif (file_exists($project_path . '/configuration.php') && is_dir($project_path . '/administrator')) {
                $type = 'Joomla';
                $icon = '⚙️';
                $badge_class = 'badge-joomla';
            } elseif (file_exists($project_path . '/core/lib/Drupal.php') || (file_exists($project_path . '/index.php') && strpos(@file_get_contents($project_path . '/index.php'), 'Drupal') !== false)) {
                $type = 'Drupal';
                $icon = '💧';
                $badge_class = 'badge-drupal';
            } elseif (file_exists($project_path . '/package.json')) {
                $pkg = json_decode(@file_get_contents($project_path . '/package.json'), true);
                if (isset($pkg['dependencies']['next'])) {
                    $type = 'Next.js App';
                    $icon = '⚛️';
                    $badge_class = 'badge-next';
                } elseif (isset($pkg['dependencies']['react'])) {
                    $type = 'React App';
                    $icon = '⚛️';
                    $badge_class = 'badge-react';
                } elseif (isset($pkg['dependencies']['vue'])) {
                    $type = 'Vue.js App';
                    $icon = '🟢';
                    $badge_class = 'badge-vue';
                } else {
                    $type = 'NodeJS App';
                    $icon = '📦';
                    $badge_class = 'badge-info';
                }
            }
            
            $projects[] = array(
                'name' => $item,
                'type' => $type,
                'icon' => $icon,
                'badge' => $badge_class,
                'url' => '/' . $item
            );
        }
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Accsify WebStack Dashboard</title>
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg-gradient: linear-gradient(135deg, #090d16 0%, #111827 100%);
            --card-bg: rgba(17, 24, 39, 0.75);
            --card-hover: rgba(31, 41, 55, 0.85);
            --glass-border: rgba(255, 255, 255, 0.05);
            --text-primary: #f9fafb;
            --text-secondary: #9ca3af;
            --accent-blue: #3b82f6;
            --accent-cyan: #06b6d4;
            --accent-emerald: #10b981;
            --accent-rose: #f43f5e;
            --accent-purple: #8b5cf6;
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        body {
            font-family: 'Outfit', sans-serif;
            background: var(--bg-gradient);
            color: var(--text-primary);
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            padding: 3rem 1.5rem;
            overflow-x: hidden;
        }

        .container {
            max-width: 1100px;
            width: 100%;
            display: flex;
            flex-direction: column;
            gap: 2.5rem;
        }

        /* HEADER */
        header {
            text-align: center;
            margin-bottom: 1rem;
        }

        header h1 {
            font-size: 3rem;
            font-weight: 700;
            background: linear-gradient(to right, #00f2fe, #4facfe);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            margin-bottom: 0.5rem;
            letter-spacing: -1px;
        }

        header .subtitle {
            color: var(--text-secondary);
            font-size: 1.2rem;
            font-weight: 300;
        }

        /* STATS GRID */
        .status-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 1.5rem;
        }

        .status-card {
            background: var(--card-bg);
            border: 1px solid var(--glass-border);
            border-radius: 20px;
            padding: 1.75rem;
            backdrop-filter: blur(12px);
            display: flex;
            flex-direction: column;
            gap: 1rem;
            transition: all 0.3s ease;
            box-shadow: 0 10px 30px -15px rgba(0, 0, 0, 0.5);
        }

        .status-card:hover {
            transform: translateY(-4px);
            border-color: var(--accent-cyan);
            box-shadow: 0 15px 30px -10px rgba(6, 182, 212, 0.15);
        }

        .card-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
        }

        .card-title {
            font-size: 1rem;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 1px;
            color: var(--text-secondary);
        }

        .card-value {
            font-size: 1.75rem;
            font-weight: 700;
            color: var(--text-primary);
        }

        /* BADGES */
        .badge {
            padding: 0.4rem 0.9rem;
            border-radius: 9999px;
            font-size: 0.8rem;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            display: inline-flex;
            align-items: center;
            gap: 0.35rem;
            width: fit-content;
        }

        .badge-success { background: rgba(16, 185, 129, 0.15); color: var(--accent-emerald); border: 1px solid rgba(16, 185, 129, 0.3); }
        .badge-error { background: rgba(244, 63, 94, 0.15); color: var(--accent-rose); border: 1px solid rgba(244, 63, 94, 0.3); }
        .badge-info { background: rgba(6, 182, 212, 0.15); color: var(--accent-cyan); border: 1px solid rgba(6, 182, 212, 0.3); }
        .badge-secondary { background: rgba(156, 163, 175, 0.15); color: var(--text-secondary); border: 1px solid rgba(156, 163, 175, 0.3); }
        
        /* FRAMEWORK BADGES */
        .badge-laravel { background: rgba(244, 63, 94, 0.15); color: #f43f5e; border: 1px solid rgba(244, 63, 94, 0.3); }
        .badge-wordpress { background: rgba(59, 130, 246, 0.15); color: #3b82f6; border: 1px solid rgba(59, 130, 246, 0.3); }
        .badge-joomla { background: rgba(245, 158, 11, 0.15); color: #f59e0b; border: 1px solid rgba(245, 158, 11, 0.3); }
        .badge-drupal { background: rgba(6, 182, 212, 0.15); color: #06b6d4; border: 1px solid rgba(6, 182, 212, 0.3); }
        .badge-react { background: rgba(6, 182, 212, 0.15); color: #06b6d4; border: 1px solid rgba(6, 182, 212, 0.3); }
        .badge-next { background: rgba(255, 255, 255, 0.15); color: #ffffff; border: 1px solid rgba(255, 255, 255, 0.3); }
        .badge-vue { background: rgba(16, 185, 129, 0.15); color: #10b981; border: 1px solid rgba(16, 185, 129, 0.3); }

        /* CONTENT SECTION */
        .section-wrapper {
            display: grid;
            grid-template-columns: 2fr 1fr;
            gap: 2rem;
        }

        @media (max-width: 900px) {
            .section-wrapper {
                grid-template-columns: 1fr;
            }
        }

        .panel {
            background: var(--card-bg);
            border: 1px solid var(--glass-border);
            border-radius: 24px;
            padding: 2.25rem;
            backdrop-filter: blur(12px);
            display: flex;
            flex-direction: column;
            gap: 1.5rem;
            box-shadow: 0 15px 35px -20px rgba(0, 0, 0, 0.6);
        }

        .panel-title {
            font-size: 1.25rem;
            font-weight: 600;
            display: flex;
            align-items: center;
            gap: 0.5rem;
            border-bottom: 1px solid rgba(255, 255, 255, 0.05);
            padding-bottom: 0.75rem;
        }

        /* PROJECTS LIST */
        .projects-list {
            display: flex;
            flex-direction: column;
            gap: 1rem;
            max-height: 450px;
            overflow-y: auto;
            padding-right: 0.25rem;
        }

        .projects-list::-webkit-scrollbar {
            width: 6px;
        }
        .projects-list::-webkit-scrollbar-track {
            background: rgba(255, 255, 255, 0.02);
            border-radius: 10px;
        }
        .projects-list::-webkit-scrollbar-thumb {
            background: rgba(255, 255, 255, 0.1);
            border-radius: 10px;
        }

        .project-card {
            background: rgba(255, 255, 255, 0.02);
            border: 1px solid rgba(255, 255, 255, 0.03);
            border-radius: 16px;
            padding: 1.25rem;
            display: flex;
            align-items: center;
            justify-content: space-between;
            transition: all 0.25s ease;
            text-decoration: none;
            color: var(--text-primary);
        }

        .project-card:hover {
            background: var(--card-hover);
            border-color: var(--accent-blue);
            transform: translateX(4px);
        }

        .project-info {
            display: flex;
            align-items: center;
            gap: 1rem;
        }

        .project-icon {
            font-size: 1.75rem;
            background: rgba(255, 255, 255, 0.05);
            width: 48px;
            height: 48px;
            border-radius: 12px;
            display: flex;
            align-items: center;
            justify-content: center;
        }

        .project-name {
            font-weight: 600;
            font-size: 1.1rem;
            margin-bottom: 0.15rem;
        }

        .project-meta {
            font-size: 0.85rem;
            color: var(--text-secondary);
        }

        .launch-btn {
            background: rgba(59, 130, 246, 0.1);
            color: var(--accent-blue);
            padding: 0.5rem;
            border-radius: 10px;
            transition: all 0.2s;
            display: flex;
            align-items: center;
            justify-content: center;
        }

        .project-card:hover .launch-btn {
            background: var(--accent-blue);
            color: #ffffff;
        }

        .no-projects {
            text-align: center;
            padding: 3rem 1.5rem;
            color: var(--text-secondary);
            font-size: 1rem;
            background: rgba(255, 255, 255, 0.01);
            border: 1px dashed rgba(255, 255, 255, 0.05);
            border-radius: 16px;
        }

        /* EXTENSIONS PANEL */
        .extensions-list {
            display: grid;
            grid-template-columns: 1fr;
            gap: 0.75rem;
        }

        .extension-item {
            background: rgba(255, 255, 255, 0.02);
            border: 1px solid rgba(255, 255, 255, 0.03);
            border-radius: 12px;
            padding: 0.85rem 1rem;
            display: flex;
            align-items: center;
            justify-content: space-between;
        }

        .ext-name {
            font-weight: 500;
            font-size: 0.95rem;
        }

        .ext-desc {
            font-size: 0.8rem;
            color: var(--text-secondary);
        }

        .indicator {
            width: 8px;
            height: 8px;
            border-radius: 50%;
            display: inline-block;
        }
        .indicator-on { background: var(--accent-emerald); box-shadow: 0 0 8px var(--accent-emerald); }
        .indicator-off { background: var(--accent-rose); box-shadow: 0 0 8px var(--accent-rose); }

        /* QUICK ACTIONS */
        .actions-panel {
            display: flex;
            flex-direction: column;
            gap: 1rem;
        }

        .btn {
            text-decoration: none;
            color: var(--text-primary);
            background: linear-gradient(135deg, #1e293b 0%, #0f172a 100%);
            border: 1px solid var(--glass-border);
            padding: 1.1rem 1.75rem;
            border-radius: 14px;
            font-weight: 600;
            font-size: 1rem;
            transition: all 0.3s ease;
            box-shadow: 0 4px 10px rgba(0, 0, 0, 0.2);
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 0.75rem;
        }

        .btn:hover {
            transform: translateY(-2px);
            border-color: var(--accent-blue);
            box-shadow: 0 10px 20px -5px rgba(59, 130, 246, 0.3);
            background: var(--card-hover);
        }

        .btn-primary {
            background: linear-gradient(135deg, #2563eb 0%, #1d4ed8 100%);
            border: none;
        }
        .btn-primary:hover {
            background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%);
            box-shadow: 0 10px 25px -5px rgba(37, 99, 235, 0.4);
        }

        /* FOOTER */
        footer {
            margin-top: auto;
            padding-top: 5rem;
            padding-bottom: 2rem;
            text-align: center;
            color: var(--text-secondary);
            font-size: 0.9rem;
            display: flex;
            flex-direction: column;
            gap: 0.5rem;
        }

        footer a {
            color: var(--accent-cyan);
            text-decoration: none;
            font-weight: 500;
        }

        footer a:hover {
            text-decoration: underline;
        }
    </style>
</head>
<body>
    <div class="container">
        <!-- HEADER -->
        <header>
            <h1>Accsify WebStack</h1>
            <div class="subtitle">Portable, High-Performance Offline Web Development Environment</div>
        </header>

        <!-- STATUS CARDS -->
        <div class="status-grid">
            <!-- APACHE -->
            <div class="status-card">
                <div class="card-header">
                    <span class="card-title">Server Engine</span>
                    <span class="badge badge-success">Active</span>
                </div>
                <div class="card-value">Apache 2.4</div>
                <span class="badge badge-info" style="font-size: 0.75rem;">
                    Port <?php echo $_SERVER['SERVER_PORT']; ?>
                </span>
            </div>

            <!-- PHP -->
            <div class="status-card">
                <div class="card-header">
                    <span class="card-title">PHP Interpreter</span>
                    <span class="badge badge-info">Loaded</span>
                </div>
                <div class="card-value">PHP <?php echo PHP_VERSION; ?></div>
                <span class="badge badge-secondary" style="font-size: 0.75rem;">
                    mod_php integration
                </span>
            </div>

            <!-- MYSQL -->
            <div class="status-card">
                <div class="card-header">
                    <span class="card-title">Database Client</span>
                    <?php if ($mysqli_conn): ?>
                        <span class="badge badge-success">Connected</span>
                    <?php else: ?>
                        <span class="badge badge-error">Disconnected</span>
                    <?php endif; ?>
                </div>
                <div class="card-value">MySQL 8.x</div>
                <span class="badge badge-secondary" style="font-size: 0.75rem;" title="<?php echo htmlspecialchars($mysqli_error); ?>">
                    Port <?php echo $mysql_port; ?>
                </span>
            </div>
        </div>

        <!-- TWO COLUMN LAYOUT -->
        <div class="section-wrapper">
            <!-- LOCAL SITES -->
            <div class="panel">
                <div class="panel-title">
                    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="color: var(--accent-blue);"><path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"></path><polyline points="9 22 9 12 15 12 15 22"></polyline></svg>
                    Your Local Web Projects
                </div>
                <div class="projects-list">
                    <?php if (empty($projects)): ?>
                        <div class="no-projects">
                            <p style="font-weight: 500; margin-bottom: 0.5rem;">No local web projects found yet.</p>
                            <p style="font-size: 0.85rem; color: var(--text-secondary);">Create a subdirectory in <code>www/</code> or use <code>scripts_installer.cmd</code> to install WordPress, Laravel, Next.js, and more!</p>
                        </div>
                    <?php else: ?>
                        <?php foreach ($projects as $project): ?>
                            <a href="<?php echo htmlspecialchars($project['url']); ?>" class="project-card" target="_blank">
                                <div class="project-info">
                                    <div class="project-icon"><?php echo $project['icon']; ?></div>
                                    <div>
                                        <div class="project-name"><?php echo htmlspecialchars($project['name']); ?></div>
                                        <div class="project-meta">
                                            Local folder: <code>www/<?php echo htmlspecialchars($project['name']); ?></code>
                                        </div>
                                    </div>
                                </div>
                                <div style="display: flex; align-items: center; gap: 1rem;">
                                    <span class="badge <?php echo $project['badge']; ?>"><?php echo $project['type']; ?></span>
                                    <div class="launch-btn">
                                        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"></path><polyline points="15 3 21 3 21 9"></polyline><line x1="10" y1="14" x2="21" y2="3"></line></svg>
                                    </div>
                                </div>
                            </a>
                        <?php endforeach; ?>
                    <?php endif; ?>
                </div>
            </div>

            <!-- RIGHT PANEL: EXTENSIONS & ACTIONS -->
            <div style="display: flex; flex-direction: column; gap: 2rem;">
                <!-- QUICK ACTIONS -->
                <div class="panel">
                    <div class="panel-title">
                        <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="color: var(--accent-purple);"><circle cx="12" cy="12" r="3"></circle><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z"></path></svg>
                        Quick Tools
                    </div>
                    <div class="actions-panel">
                        <a href="/phpmyadmin" class="btn btn-primary" target="_blank">
                            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5"></path></svg>
                            Launch phpMyAdmin
                        </a>
                        <a href="/info.php" class="btn" target="_blank">
                            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"></circle><line x1="12" y1="16" x2="12" y2="12"></line><line x1="12" y1="8" x2="12.01" y2="8"></line></svg>
                            Check PHP configuration
                        </a>
                    </div>
                </div>

                <!-- EXTENSIONS STATUS -->
                <div class="panel">
                    <div class="panel-title">
                        <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="color: var(--accent-emerald);"><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"></path><polyline points="3.27 6.96 12 12.01 20.73 6.96"></polyline><line x1="12" y1="22.08" x2="12" y2="12"></line></svg>
                        PHP Stack Status
                    </div>
                    <div class="extensions-list">
                        <?php foreach ($required_extensions as $ext => $desc): ?>
                            <?php $loaded = extension_loaded($ext); ?>
                            <div class="extension-item">
                                <div>
                                    <span class="ext-name"><?php echo $ext; ?></span>
                                    <span class="ext-desc" style="display: block; font-size: 0.75rem; color: var(--text-secondary);"><?php echo $desc; ?></span>
                                </div>
                                <span class="indicator <?php echo $loaded ? 'indicator-on' : 'indicator-off'; ?>" title="<?php echo $loaded ? 'Loaded' : 'Not Loaded'; ?>"></span>
                            </div>
                        <?php endforeach; ?>
                    </div>
                </div>
            </div>
        </div>

        <!-- FOOTER -->
        <footer>
            <div>
                Accsify WebStack by <a href="https://github.com/accsify" target="_blank">Nacer Baaziz</a>.
            </div>
            <div style="font-size: 0.8rem; margin-top: 0.25rem;">
                Licensed under MIT License | Managed locally via <code>setup.cmd</code>
            </div>
        </footer>
    </div>
</body>
</html>
