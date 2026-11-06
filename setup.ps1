# One-command local setup for Windows.
#
#   .\setup.ps1
#
# - ensures Docker is running
# - applies the WSL2 MTU fix (1442) if missing, and restarts Docker
# - makes sure a .env exists
# - builds and starts the dev stack
# - creates an admin login if none exists
#
# Re-runnable: each step is a no-op if already done.

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Info($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "    $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    $m" -ForegroundColor Yellow }

# --- 1. Docker running? ----------------------------------------------------
Info "Checking Docker..."
function Test-Docker { try { docker info 2>$null | Out-Null; return $LASTEXITCODE -eq 0 } catch { return $false } }
if (-not (Test-Docker)) {
    Warn "Docker daemon not responding. Trying to start Docker Desktop..."
    $dd = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dd) { Start-Process $dd } else { throw "Docker Desktop not found. Install it from https://www.docker.com/products/docker-desktop/ and re-run." }
    $deadline = (Get-Date).AddMinutes(3)
    while (-not (Test-Docker) -and (Get-Date) -lt $deadline) { Start-Sleep 3 }
    if (-not (Test-Docker)) { throw "Docker did not start in time. Start Docker Desktop manually and re-run." }
}
Ok "Docker is running."

# --- 2. MTU fix (WSL2) -----------------------------------------------------
Info "Checking Docker MTU (WSL2 download fix)..."
$daemonPath = Join-Path $env:USERPROFILE ".docker\daemon.json"
$needRestart = $false
if (Test-Path $daemonPath) {
    $cfg = Get-Content $daemonPath -Raw | ConvertFrom-Json
    if (-not ($cfg.PSObject.Properties.Name -contains 'mtu')) {
        $cfg | Add-Member -NotePropertyName mtu -NotePropertyValue 1442
        ($cfg | ConvertTo-Json -Depth 20) | Set-Content $daemonPath -Encoding utf8
        $needRestart = $true
    } elseif ($cfg.mtu -ne 1442) {
        Warn "daemon.json has mtu=$($cfg.mtu) (not 1442). Leaving it as-is."
    }
} else {
    '{ "mtu": 1442 }' | Set-Content $daemonPath -Encoding utf8
    $needRestart = $true
}
if ($needRestart) {
    Warn "Added mtu=1442 to daemon.json. Restarting Docker to apply..."
    Get-Process 'Docker Desktop','com.docker.backend' -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Kill() } catch {} }
    try { wsl --shutdown } catch {}
    Start-Sleep 6
    Start-Process "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
    $deadline = (Get-Date).AddMinutes(3)
    while (-not (Test-Docker) -and (Get-Date) -lt $deadline) { Start-Sleep 3 }
    if (-not (Test-Docker)) { throw "Docker did not come back after the MTU change. Start it manually and re-run." }
    Ok "MTU applied, Docker back up."
} else {
    Ok "MTU already configured."
}

# --- 3. .env present? ------------------------------------------------------
Info "Checking .env..."
if (-not (Test-Path ".env")) {
    if (Test-Path ".env.example") {
        Copy-Item ".env.example" ".env"
        Warn "Created .env from .env.example. Open it and set POSTGRES_PASSWORD"
        Warn "and MODEL_API_KEY (an OpenRouter key: https://openrouter.ai/)."
    } else {
        throw "No .env and no .env.example found."
    }
} else {
    Ok ".env present."
}

# --- 4. Build & start ------------------------------------------------------
Info "Building and starting the stack (first run takes a few minutes)..."
docker compose up -d --build
if ($LASTEXITCODE -ne 0) { throw "docker compose up failed. See the output above." }

Info "Waiting for the API to become healthy..."
$deadline = (Get-Date).AddMinutes(4)
do {
    Start-Sleep 4
    try { $h = (Invoke-WebRequest "http://localhost:8000/api/health" -UseBasicParsing -TimeoutSec 5).StatusCode } catch { $h = 0 }
} while ($h -ne 200 -and (Get-Date) -lt $deadline)
if ($h -eq 200) { Ok "API healthy." } else { Warn "API not confirmed healthy yet; it may still be starting." }

# --- 5. Admin user ---------------------------------------------------------
Info "Ensuring an admin login exists..."
$env_vars = @{}
Get-Content ".env" | ForEach-Object {
    if ($_ -match '^\s*(SEED_ADMIN_USERNAME|SEED_ADMIN_PASSWORD|POSTGRES_USER|POSTGRES_DB)\s*=\s*(.+?)\s*$') { $env_vars[$Matches[1]] = $Matches[2] }
}
$pu = $env_vars['POSTGRES_USER']; $pd = $env_vars['POSTGRES_DB']
$count = (docker compose exec -T postgres psql -U "$pu" -d "$pd" -tAc "select count(*) from users;" 2>$null)
if ($count -and ([int]($count.Trim()) -gt 0)) {
    Ok "A user already exists - skipping creation."
} else {
    $au = $env_vars['SEED_ADMIN_USERNAME']; if (-not $au) { $au = 'admin' }
    $ap = $env_vars['SEED_ADMIN_PASSWORD']
    if (-not $ap) {
        $sec = Read-Host "Choose an admin password" -AsSecureString
        $ap = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
    }
    # Credentials go in via env vars, not command args, so they stay out of
    # the container's process list and survive special characters.
    docker compose exec -T -e NU="$au" -e NP="$ap" api sh -c 'python manage.py create-user "$NU" --password "$NP" --role admin' | Out-Null
    Ok "Created admin user '$au' (password from your .env's SEED_ADMIN_PASSWORD, or what you just entered)."
}

Write-Host ""
Write-Host "All set. Open http://localhost:3001 and sign in." -ForegroundColor Green
Write-Host "  API:        http://localhost:8000" -ForegroundColor DarkGray
Write-Host "  Grafana:    http://localhost:3000" -ForegroundColor DarkGray
Write-Host "  Stop:       docker compose stop" -ForegroundColor DarkGray
Write-Host "  Start:      docker compose up -d" -ForegroundColor DarkGray
