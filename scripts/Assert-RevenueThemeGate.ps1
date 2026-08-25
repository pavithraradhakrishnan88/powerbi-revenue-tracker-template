#Requires -Version 7.0
<#!
.SYNOPSIS
    Validates that the Revenue Tracker custom theme is present, registered in PBIR,
    copied into the generated report, and that every generated visual JSON is valid.

    Visual count is discovered from the generated report. The separate native visual
    formatting gate owns the explicit 4-visual contract.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$GeneratedRoot
)

$ErrorActionPreference = 'Stop'

$reportRoot = Join-Path $GeneratedRoot 'RevenueTracker.Report'
$themeRelativePath = 'StaticResources/RegisteredResources/RevenueTracker_LavenderTheme.json'
$themePath = Join-Path $reportRoot $themeRelativePath
$reportJsonPath = Join-Path $reportRoot 'definition/report.json'
$pagesRoot = Join-Path $reportRoot 'definition/pages'

if (-not (Test-Path $themePath -PathType Leaf)) {
    throw "THEME-GATE failed: generated custom theme is missing at $themePath"
}

try {
    $theme = Get-Content -Path $themePath -Raw | ConvertFrom-Json
}
catch {
    throw "THEME-GATE failed: custom theme is not valid JSON: $($_.Exception.Message)"
}

if ([string]$theme.name -ne 'Revenue Tracker - White Fintech') {
    throw "THEME-GATE failed: unexpected theme name '$($theme.name)'."
}
if ([string]$theme.background -ne '#FFFFFF') {
    throw "THEME-GATE failed: theme background must remain #FFFFFF."
}
if (-not ($theme.dataColors -contains '#7B5CFA') -or -not ($theme.dataColors -contains '#F0629B')) {
    throw 'THEME-GATE failed: required violet/pink data colors are missing.'
}

$report = Get-Content -Path $reportJsonPath -Raw | ConvertFrom-Json
$customTheme = $report.themeCollection.customTheme
if ($null -eq $customTheme) {
    throw 'THEME-GATE failed: report.json has no themeCollection.customTheme registration.'
}
if ([string]$customTheme.name -ne 'RevenueTracker_LavenderTheme.json') {
    throw "THEME-GATE failed: report.json customTheme.name is '$($customTheme.name)'."
}
if ([string]$customTheme.type -ne 'RegisteredResources') {
    throw "THEME-GATE failed: report.json customTheme.type is '$($customTheme.type)'."
}

$registered = @($report.resourcePackages | Where-Object { $_.name -eq 'RegisteredResources' })
if ($registered.Count -ne 1) {
    throw 'THEME-GATE failed: exactly one RegisteredResources package is expected.'
}
$themeItem = @($registered[0].items | Where-Object { $_.name -eq 'RevenueTracker_LavenderTheme.json' })
if ($themeItem.Count -ne 1 -or [string]$themeItem[0].type -ne 'CustomTheme' -or [string]$themeItem[0].path -ne 'RevenueTracker_LavenderTheme.json') {
    throw 'THEME-GATE failed: custom theme resource registration is incomplete or points to the wrong path.'
}

$visualFiles = @(Get-ChildItem -Path $pagesRoot -Recurse -Filter 'visual.json' -File)
$invalidVisuals = @()
foreach ($visualFile in $visualFiles) {
    try {
        Get-Content -Path $visualFile.FullName -Raw | ConvertFrom-Json | Out-Null
    }
    catch {
        $invalidVisuals += $visualFile.FullName
    }
}

if ($invalidVisuals.Count -gt 0) {
    throw "PBIR-VISUAL-GATE failed: $($invalidVisuals.Count) visual.json file(s) contain invalid JSON: $($invalidVisuals -join '; ')"
}

Write-Host "THEME-GATE|PASS|Theme=RevenueTracker_LavenderTheme.json|Background=#FFFFFF|RegisteredResources=PASS"
Write-Host "PBIR-VISUAL-GATE|PASS|GeneratedVisuals=$($visualFiles.Count)|JsonValidity=PASS"
exit 0
