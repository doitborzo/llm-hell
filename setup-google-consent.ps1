# Launches the Google Workspace MCP consent flow.
# Reads GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET / GOOGLE_ACCOUNT_EMAIL from .env
# (nothing is printed), then opens the MCP Inspector so you can run the
# browser consent. Run this from the repo root:  .\setup-google-consent.ps1

$ErrorActionPreference = 'Stop'
$envPath = Join-Path $PSScriptRoot '.env'
if (-not (Test-Path $envPath)) { throw ".env not found next to this script" }

$vars = @{}
foreach ($line in Get-Content $envPath) {
    if ($line -match '^\s*(GOOGLE_CLIENT_ID|GOOGLE_CLIENT_SECRET|GOOGLE_ACCOUNT_EMAIL)\s*=\s*(.+?)\s*$') {
        $vars[$Matches[1]] = $Matches[2]
    }
}
foreach ($k in 'GOOGLE_CLIENT_ID','GOOGLE_CLIENT_SECRET','GOOGLE_ACCOUNT_EMAIL') {
    if (-not $vars.ContainsKey($k) -or [string]::IsNullOrWhiteSpace($vars[$k])) {
        throw "$k is missing or empty in .env"
    }
}

$env:GOOGLE_CLIENT_ID     = $vars['GOOGLE_CLIENT_ID']
$env:GOOGLE_CLIENT_SECRET = $vars['GOOGLE_CLIENT_SECRET']

Write-Host "Loaded Google client credentials from .env (values hidden)." -ForegroundColor Green
Write-Host "Account to authenticate: $($vars['GOOGLE_ACCOUNT_EMAIL'])" -ForegroundColor Cyan
Write-Host ""
Write-Host "The MCP Inspector will open in your browser. In it:" -ForegroundColor Yellow
Write-Host "  1. Click 'Connect' (the server command is prefilled)." -ForegroundColor Yellow
Write-Host "  2. Go to the 'Tools' tab, pick 'manage_accounts'." -ForegroundColor Yellow
Write-Host "  3. Run it with:  operation = authenticate , category = work" -ForegroundColor Yellow
Write-Host "  4. A Google consent window opens - sign in and approve." -ForegroundColor Yellow
Write-Host "  5. (Optional) narrow scopes: manage_accounts  operation=scopes" -ForegroundColor Yellow
Write-Host "       email=$($vars['GOOGLE_ACCOUNT_EMAIL'])  services=drive,gmail" -ForegroundColor Yellow
Write-Host "  6. Verify: run 'manage_drive' operation=search email=$($vars['GOOGLE_ACCOUNT_EMAIL'])" -ForegroundColor Yellow
Write-Host "       query=fullText contains 'test'  maxResults=5" -ForegroundColor Yellow
Write-Host ""
Write-Host "When the search returns results, close the Inspector (Ctrl+C here) and tell Claude." -ForegroundColor Green
Write-Host ""

npx -y @modelcontextprotocol/inspector google-workspace-mcp
