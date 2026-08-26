param(
    [Parameter(Mandatory = $true)]
    [string]$PbipPath,
    [string]$ExpectedVersion = '2.156.951.0',
    [string]$DiagnosticsRoot = (Join-Path $PWD 'DesktopDiagnostics')
)

$ErrorActionPreference = 'Stop'
if (!(Test-Path $PbipPath -PathType Leaf)) { throw "REAL-DESKTOP-UAT failed: PBIP not found: $PbipPath" }
New-Item -ItemType Directory -Path $DiagnosticsRoot -Force | Out-Null

$desktopCandidates = @(
    'C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe',
    'C:\Program Files\Microsoft Power BI Desktop RS\bin\PBIDesktop.exe'
)
$desktop = $desktopCandidates | Where-Object { Test-Path $_ -PathType Leaf } | Select-Object -First 1
if (-not $desktop) {
    $desktop = Get-ChildItem 'C:\Program Files' -Filter 'PBIDesktop.exe' -File -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $desktop) { throw 'REAL-DESKTOP-UAT failed: PBIDesktop.exe is not installed on the runner.' }

$version = (Get-Item $desktop).VersionInfo.ProductVersion
$startup = [ordered]@{
    ProductVersion = $version
    DesktopPath = $desktop
    PbipPath = [IO.Path]::GetFullPath($PbipPath)
    BridgeOpen = $false
    BridgeStatus = $false
    PbipLoad = $false
    DiagnosticsCaptured = $false
}
$startup | ConvertTo-Json | Set-Content (Join-Path $DiagnosticsRoot 'desktop-startup.json') -Encoding utf8

if ($version -ne $ExpectedVersion) {
    throw "REAL-DESKTOP-UAT failed: expected Power BI Desktop $ExpectedVersion, found $version at $desktop."
}

if (-not (Get-Command powerbi-desktop -ErrorAction SilentlyContinue)) {
    npm install -g @microsoft/powerbi-desktop-bridge-cli@0.1.2
}

$openOutput = & powerbi-desktop open $PbipPath 2>&1
$openExit = $LASTEXITCODE
$openOutput | Tee-Object -FilePath (Join-Path $DiagnosticsRoot 'bridge-open.log') | ForEach-Object { Write-Host $_ }
if ($openExit -ne 0) {
    throw "REAL-DESKTOP-UAT failed: Desktop Bridge could not open the PBIP. ExitCode=$openExit"
}
$startup.BridgeOpen = $true

Start-Sleep -Seconds 5
$statusOutput = & powerbi-desktop status 2>&1
$statusExit = $LASTEXITCODE
$statusOutput | Tee-Object -FilePath (Join-Path $DiagnosticsRoot 'bridge-status.log') | ForEach-Object { Write-Host $_ }
if ($statusExit -ne 0) {
    throw "REAL-DESKTOP-UAT failed: Desktop Bridge status failed. ExitCode=$statusExit"
}
$startup.BridgeStatus = $true

$statusText = ($statusOutput -join "`n")
if ($statusText -match 'TMDL Format Error|Invalid indentation|DataModelLoadFailed|ReportDefinitionValidationFailed|Definition content|Cannot resolve all the paths|Failed to load') {
    throw 'REAL-DESKTOP-UAT failed: Power BI Desktop reported a model/report load error.'
}

$normalizedPbip = [IO.Path]::GetFullPath($PbipPath).Replace('/','\')
if ($statusText -notmatch [regex]::Escape($normalizedPbip)) {
    throw 'REAL-DESKTOP-UAT failed: Desktop status does not identify the generated PBIP as the current file.'
}
$startup.PbipLoad = $true

$processes = Get-Process PBIDesktop -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,Path,StartTime
$processes | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $DiagnosticsRoot 'desktop-processes.json') -Encoding utf8

$eventLog = Get-WinEvent -FilterHashtable @{ LogName='Application'; StartTime=(Get-Date).AddMinutes(-10) } -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -match 'Power BI|PBIDesktop|Application Error|Windows Error Reporting' } |
    Select-Object TimeCreated,ProviderName,Id,LevelDisplayName,Message -First 100
$eventLog | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $DiagnosticsRoot 'desktop-eventlog.json') -Encoding utf8

$startup.DiagnosticsCaptured = $true
$startup | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $DiagnosticsRoot 'desktop-uat.json') -Encoding utf8

Write-Host "REAL-DESKTOP-UAT|PASS|ProductVersion=$version|PBIP=$normalizedPbip|BridgeOpen=PASS|BridgeStatus=PASS|Load=PASS|Diagnostics=PASS"
