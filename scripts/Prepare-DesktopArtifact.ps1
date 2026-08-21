[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GeneratedRoot,

    [string]$AssemblyRoot
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($AssemblyRoot)) {
    $AssemblyRoot = Join-Path $GeneratedRoot 'RevenueTracker.Desktop'
}

$reportSource = Join-Path $GeneratedRoot 'RevenueTracker.Report'
$semanticSource = Join-Path $GeneratedRoot 'RevenueTracker.SemanticModel'
$pbipSource = Join-Path $GeneratedRoot 'RevenueTracker.pbip'

foreach ($required in @($reportSource, $semanticSource, $pbipSource)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Desktop assembly source is missing: $required"
    }
}

if (Test-Path -LiteralPath $AssemblyRoot) {
    Remove-Item -LiteralPath $AssemblyRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $AssemblyRoot -Force | Out-Null

function Copy-Tree {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        $target = Join-Path $Destination $item.Name
        if ($item.PSIsContainer) {
            Copy-Tree -Source $item.FullName -Destination $target
        }
        else {
            Copy-Item -LiteralPath $item.FullName -Destination $target -Force
        }
    }
}

# Assemble the three independently generated artifacts into the exact relative
# layout expected by the root .pbip and definition.pbir references.
Copy-Tree -Source $reportSource -Destination (Join-Path $AssemblyRoot 'RevenueTracker.Report')
Copy-Tree -Source $semanticSource -Destination (Join-Path $AssemblyRoot 'RevenueTracker.SemanticModel')
Copy-Item -LiteralPath $pbipSource -Destination (Join-Path $AssemblyRoot 'RevenueTracker.pbip') -Force

$pbipPath = Join-Path $AssemblyRoot 'RevenueTracker.pbip'
$pbirPath = Join-Path $AssemblyRoot 'RevenueTracker.Report\definition.pbir'
$pbismPath = Join-Path $AssemblyRoot 'RevenueTracker.SemanticModel\definition.pbism'

foreach ($required in @($pbipPath, $pbirPath, $pbismPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Desktop assembly gate failed: required artifact is missing: $required"
    }
}

try {
    $pbip = Get-Content -LiteralPath $pbipPath -Raw | ConvertFrom-Json
    $pbir = Get-Content -LiteralPath $pbirPath -Raw | ConvertFrom-Json
    $pbism = Get-Content -LiteralPath $pbismPath -Raw | ConvertFrom-Json
}
catch {
    throw "Desktop assembly gate failed: assembled JSON could not be parsed. $($_.Exception.Message)"
}

$reportPath = $pbip.artifacts[0].report.path
if ($reportPath -ne 'RevenueTracker.Report') {
    throw "Desktop assembly gate failed: RevenueTracker.pbip report path is '$reportPath', expected 'RevenueTracker.Report'."
}

$datasetPath = $pbir.datasetReference.byPath.path
if ($datasetPath -ne '../RevenueTracker.SemanticModel') {
    throw "Desktop assembly gate failed: definition.pbir dataset path is '$datasetPath', expected '../RevenueTracker.SemanticModel'."
}

if (-not ($pbism.version -and $pbism.settings -ne $null)) {
    throw 'Desktop assembly gate failed: definition.pbism does not contain the expected version/settings structure.'
}

$runnerPathPattern = [regex]::Escape($env:GITHUB_WORKSPACE)
$runnerPathHits = Get-ChildItem -LiteralPath $AssemblyRoot -Recurse -File -Force |
    Select-String -Pattern $runnerPathPattern -SimpleMatch -ErrorAction SilentlyContinue
if ($runnerPathHits) {
    $hit = $runnerPathHits | Select-Object -First 1
    throw "Desktop assembly gate failed: GitHub runner path found in assembled artifact: $($hit.Path)"
}

$reportFiles = @(Get-ChildItem -LiteralPath (Join-Path $AssemblyRoot 'RevenueTracker.Report') -Recurse -File -Force)
$semanticFiles = @(Get-ChildItem -LiteralPath (Join-Path $AssemblyRoot 'RevenueTracker.SemanticModel') -Recurse -File -Force)

Write-Host "DESKTOP-ASSEMBLY-GATE|PASS"
Write-Host "AssemblyRoot=$AssemblyRoot"
Write-Host "ReportFiles=$($reportFiles.Count)"
Write-Host "SemanticModelFiles=$($semanticFiles.Count)"
Write-Host "PBIP=$(Split-Path $pbipPath -Leaf)"
Write-Host "PBIR=RevenueTracker.Report/definition.pbir"
Write-Host "PBISM=RevenueTracker.SemanticModel/definition.pbism"
Write-Host "DatasetReference=$datasetPath"
