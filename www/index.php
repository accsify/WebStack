<?php
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
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Offline WAMP Stack Dashboard</title>
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;700&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg-gradient: linear-gradient(135deg, #0f172a 0%, #1e1b4b 100%);
            --card-bg: rgba(30, 41, 59, 0.7);
            --glass-border: rgba(255, 255, 255, 0.08);
            --text-primary: #f8fafc;
            --text-secondary: #94a3b8;
            --accent-cyan: #38bdf8;
            --accent-emerald: #10b981;
            --accent-rose: #f43f5e;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: 'Outfit', sans-serif;
            background: var(--bg-gradient);
            color: var(--text-primary);
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            padding: 2rem;
            overflow-x: hidden;
        }
        .container {
            max-width: 900px;
            width: 100%;
            backdrop-filter: blur(16px);
            background: var(--card-bg);
            border: 1px solid var(--glass-border);
            border-radius: 24px;
            padding: 3rem;
            box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
            transition: transform 0.3s ease, box-shadow 0.3s ease;
        }
        .container:hover {
            transform: translateY(-4px);
            box-shadow: 0 30px 60px -10px rgba(56, 189, 248, 0.15);
        }
        h1 {
            font-size: 2.5rem;
            font-weight: 700;
            text-align: center;
            margin-bottom: 0.5rem;
            background: linear-gradient(to right, #38bdf8, #818cf8);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .subtitle {
            text-align: center;
            color: var(--text-secondary);
            font-size: 1.1rem;
            margin-bottom: 3rem;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            gap: 2rem;
            margin-bottom: 3rem;
        }
        .card {
            background: rgba(15, 23, 42, 0.4);
            border: 1px solid var(--glass-border);
            border-radius: 16px;
            padding: 2rem 1.5rem;
            text-align: center;
            transition: all 0.3s ease;
        }
        .card:hover {
            background: rgba(15, 23, 42, 0.6);
            border-color: var(--accent-cyan);
            transform: scale(1.03);
        }
        .card-title {
            font-size: 1.2rem;
            font-weight: 600;
            margin-bottom: 0.75rem;
            color: var(--text-secondary);
        }
        .card-value {
            font-size: 1.8rem;
            font-weight: 700;
            color: var(--text-primary);
            margin-bottom: 1rem;
        }
        .badge {
            display: inline-block;
            padding: 0.4rem 1rem;
            border-radius: 9999px;
            font-size: 0.85rem;
            font-weight: 600;
            text-transform: uppercase;
        }
        .badge-success { background: rgba(16, 185, 129, 0.2); color: var(--accent-emerald); border: 1px solid rgba(16, 185, 129, 0.4); }
        .badge-error { background: rgba(244, 63, 94, 0.2); color: var(--accent-rose); border: 1px solid rgba(244, 63, 94, 0.4); }
        .badge-info { background: rgba(56, 189, 248, 0.2); color: var(--accent-cyan); border: 1px solid rgba(56, 189, 248, 0.4); }
        .actions {
            display: flex;
            flex-wrap: wrap;
            justify-content: center;
            gap: 1.5rem;
        }
        .btn {
            text-decoration: none;
            color: var(--text-primary);
            background: linear-gradient(135deg, #2563eb 0%, #1d4ed8 100%);
            padding: 1rem 2rem;
            border-radius: 12px;
            font-weight: 600;
            transition: all 0.3s ease;
            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
            display: inline-flex;
            align-items: center;
            gap: 0.5rem;
        }
        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 15px -3px rgba(37, 99, 235, 0.4);
            filter: brightness(1.1);
        }
        .btn-secondary {
            background: rgba(255, 255, 255, 0.05);
            border: 1px solid var(--glass-border);
        }
        .btn-secondary:hover {
            background: rgba(255, 255, 255, 0.1);
            box-shadow: 0 10px 15px -3px rgba(255, 255, 255, 0.05);
        }
        .footer {
            margin-top: 4rem;
            color: var(--text-secondary);
            font-size: 0.9rem;
            text-align: center;
        }
        .footer a { color: var(--accent-cyan); text-decoration: none; }
        .footer a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Portable Server Environment</h1>
        <div class="subtitle">Your offline high-performance local stack is ready.</div>

        <div class="grid">
            <div class="card">
                <div class="card-title">Web Server</div>
                <div class="card-value">Apache</div>
                <span class="badge badge-success">[ RUNNING ]</span>
            </div>
            <div class="card">
                <div class="card-title">PHP Version</div>
                <div class="card-value"><?php echo PHP_VERSION; ?></div>
                <span class="badge badge-info">mod_php</span>
            </div>
            <div class="card">
                <div class="card-title">Database Port</div>
                <div class="card-value">MySQL (Port <?php echo $mysql_port; ?>)</div>
                <?php if ($mysqli_conn): ?>
                    <span class="badge badge-success">Connected</span>
                <?php else: ?>
                    <span class="badge badge-error" title="<?php echo htmlspecialchars($mysqli_error); ?>">Disconnected</span>
                <?php endif; ?>
            </div>
        </div>

        <div class="actions">
            <a href="/phpmyadmin" class="btn">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5"></path></svg>
                Open phpMyAdmin
            </a>
            <a href="http://localhost:<?php echo $_SERVER['SERVER_PORT']; ?>" class="btn btn-secondary">
                Documentation
            </a>
        </div>
    </div>
    <div class="footer">
        Managed via <code>setup.cmd</code> | Designed professionally.
    </div>
</body>
</html>
