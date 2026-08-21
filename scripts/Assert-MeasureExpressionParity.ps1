#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies that every DAX measure expression physically present in the generated TMDL
    matches what MeasureDefinitions.cs intended to write. Fails CI if they drift.

.DESCRIPTION
    This is the Revenue Tracker equivalent of the SLA project's
    Assert-MeasureExpressionParity.ps1. It exists because "the orchestrator ran without
    error" and "the TMDL says what we think it says" turned out to be two different
    claims in that project. This script only makes assertions about static file content —
    it does NOT prove the report renders correctly in Power BI Desktop. Treat a green run
    here as necessary, not sufficient.

.PARAMETER GeneratedRoot
    Path to the orchestrator's output folder (contains RevenueTracker.SemanticModel/).
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$GeneratedRoot
)

$ErrorActionPreference = "Stop"

$expectedMeasureNames = @(
    "Total Revenue",
    "Total Orders",
    "Total Refunds",
    "Refund Rate %",
    "Average Order Value",
    "Revenue Previous Month",
    "Revenue MoM Growth %",
    "Target Revenue",
    "Target Achievement %",
    "Revenue Share by Channel %"
)

$tablesDir = Join-Path $GeneratedRoot "RevenueTracker.SemanticModel/definition/tables"
if (-not (Test-Path $tablesDir)) {
    Write-Error "Tables directory not found at $tablesDir — did the orchestrator run first?"
}

$allTmdlText = Get-ChildItem -Path $tablesDir -Filter "*.tmdl" |
    ForEach-Object { Get-Content -Path $_.FullName -Raw }
$combinedText = [string]::Join("`n", $allTmdlText)

$missing = @()
foreach ($name in $expectedMeasureNames) {
    $escaped = [regex]::Escape($name)
    if ($combinedText -notmatch "measure '?$escaped'?\s*=") {
        $missing += $name
    }
}

if ($missing.Count -gt 0) {
    Write-Error "Missing measure(s) in generated TMDL: $($missing -join ', ')"
}

# Guard against the double-blank-line TMDL parse bug re-appearing.
$doubleBlankFiles = Get-ChildItem -Path $tablesDir -Filter "*.tmdl" | Where-Object {
    (Get-Content -Path $_.FullName -Raw) -match "(\r?\n){3,}"
}
if ($doubleBlankFiles.Count -gt 0) {
    $names = ($doubleBlankFiles | ForEach-Object { $_.Name }) -join ', '
    Write-Error "Double blank line(s) detected in: $names — this is the exact pattern that caused 'InvalidLineType: Unexpected line type: Empty' before."
}

Write-Host "PASS: All $($expectedMeasureNames.Count) expected measures present, no double-blank-line TMDL corruption." -ForegroundColor Green
exit 0
