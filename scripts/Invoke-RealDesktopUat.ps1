param(
    [Parameter(Mandatory = $true)]
    [string]$PbipPath,
    [string]$ExpectedVersion = '2.156.951.0'
)

$ErrorActionPreference = 'Stop'
if (!(Test-Path $PbipPath -PathType Leaf)) { throw "REAL-DESKTOP-UAT failed: PBIP not found: $PbipPath" }

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
if ($version -ne $ExpectedVersion) {
    throw "REAL-DESKTOP-UAT failed: expected Power BI Desktop $ExpectedVersion, found $version at $desktop."
}

if (-not (Get-Command powerbi-desktop -ErrorAction SilentlyContinue)) {
    npm install -g @microsoft/powerbi-desktop-bridge-cli@0.1.2
}

$openOutput = & powerbi-desktop open $PbipPath 2>&1
$openExit = $LASTEXITCODE
$openOutput | ForEach-Object { Write-Host $_ }
if ($openExit -ne 0) {
    throw "REAL-DESKTOP-UAT failed: Desktop Bridge could not open the PBIP. ExitCode=$openExit"
}

$statusOutput = & powerbi-desktop status 2>&1
$statusExit = $LASTEXITCODE
$statusOutput | ForEach-Object { Write-Host $_ }
if ($statusExit -ne 0) {
    throw "REAL-DESKTOP-UAT failed: Desktop Bridge status failed. ExitCode=$statusExit"
}

$statusText = ($statusOutput -join "`n")
if ($statusText -match 'TMDL Format Error|Invalid indentation|DataModelLoadFailed|ReportDefinitionValidationFailed|Definition content|Cannot resolve all the paths') {
    throw 'REAL-DESKTOP-UAT failed: Power BI Desktop reported a model/report load error.'
}

$normalizedPbip = [IO.Path]::GetFullPath($PbipPath).Replace('/','\')
if ($statusText -notmatch [regex]::Escape($normalizedPbip)) {
    throw 'REAL-DESKTOP-UAT failed: Desktop status does not identify the generated PBIP as the current file.'
}

Write-Host "REAL-DESKTOP-UAT|PASS|ProductVersion=$version|PBIP=$normalizedPbip|BridgeStatus=connected|Load=PASS"