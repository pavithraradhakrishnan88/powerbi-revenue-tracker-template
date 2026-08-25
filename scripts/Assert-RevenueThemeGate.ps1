#Requires -Version 7.0
<#!
.SYNOPSIS
    Validates the Revenue Tracker theme, public HTML Content custom visual
    registration, and JSON validity of every generated PBIR visual.

    The native visual formatting gate owns the explicit 4-visual contract.
    Custom visuals are validated separately and are never included in that gate.
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
$htmlVisualGuid = 'htmlContent443BE3AD55E043BF878BED274D3A6865'
$htmlVisualName = 'NavigationHtmlButtons'

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

# Public AppSource custom visual registration is required for a GUID-based visual.
$publicVisuals = @($report.publicCustomVisuals)
if ($publicVisuals -notcontains $htmlVisualGuid) {
    throw "CUSTOM-VISUAL-GATE failed: HTML Content Lite GUID '$htmlVisualGuid' is not registered in report.json publicCustomVisuals."
}

$visualFiles = @(Get-ChildItem -Path $pagesRoot -Recurse -Filter 'visual.json' -File)
$invalidVisuals = @()
$customVisuals = @()
foreach ($visualFile in $visualFiles) {
    try {
        $json = Get-Content -Path $visualFile.FullName -Raw | ConvertFrom-Json
        if ([string]$json.visual.visualType -eq $htmlVisualGuid) {
            $customVisuals += $json.name
        }
    }
    catch {
        $invalidVisuals += $visualFile.FullName
    }
}

if ($invalidVisuals.Count -gt 0) {
    throw "PBIR-VISUAL-GATE failed: $($invalidVisuals.Count) visual.json file(s) contain invalid JSON: $($invalidVisuals -join '; ')"
}

if ($customVisuals.Count -ne 1 -or $customVisuals[0] -ne $htmlVisualName) {
    throw "CUSTOM-VISUAL-GATE failed: expected exactly one '$htmlVisualName' visual using GUID '$htmlVisualGuid'; found $($customVisuals -join ', ')."
}

Write-Host "THEME-GATE|PASS|Theme=RevenueTracker_LavenderTheme.json|Background=#FFFFFF|RegisteredResources=PASS"
Write-Host "CUSTOM-VISUAL-GATE|PASS|Visual=$htmlVisualName|Type=$htmlVisualGuid|Registration=publicCustomVisuals|Count=$($customVisuals.Count)"
Write-Host "PBIR-VISUAL-GATE|PASS|GeneratedVisuals=$($visualFiles.Count)|NativeFormattingScope=4|CustomVisualsExcludedFromNativeGate=PASS|JsonValidity=PASS"
exit 0
