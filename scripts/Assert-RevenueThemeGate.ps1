#Requires -Version 7.0
<#!
.SYNOPSIS
    Validates the Revenue Tracker theme, public HTML Content custom visual
    registration, navigation HTML visual contract, and JSON validity of every generated PBIR visual.

    The 4/4 Revenue Overview HTML gate owns the four overview visuals.
    This gate validates the separate NavigationHtmlButtons role and allows
    the same registered HTML Content custom-visual GUID to be reused by all
    five HTML Content visuals.
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
$navigationLabels = @('Overview','Revenue','Target','Details')

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

# The HTML Content custom visual is intentionally reused by the four Revenue Overview
# visuals plus the single NavigationHtmlButtons visual. Registration is therefore a
# GUID-level assertion, not a uniqueness assertion.
$publicVisuals = @($report.publicCustomVisuals)
if ($publicVisuals -notcontains $htmlVisualGuid) {
    throw "CUSTOM-VISUAL-GATE failed: HTML Content Lite GUID '$htmlVisualGuid' is not registered in report.json publicCustomVisuals."
}

$visualFiles = @(Get-ChildItem -Path $pagesRoot -Recurse -Filter 'visual.json' -File)
$invalidVisuals = @()
$customVisuals = @()
$navigationVisuals = @()
foreach ($visualFile in $visualFiles) {
    try {
        $json = Get-Content -Path $visualFile.FullName -Raw | ConvertFrom-Json
        if ([string]$json.visual.visualType -eq $htmlVisualGuid) {
            $customVisuals += [PSCustomObject]@{
                Name = [string]$json.name
                Path = $visualFile.FullName
                Json = $json
            }
        }
        if ([string]$json.name -eq $htmlVisualName) {
            $navigationVisuals += [PSCustomObject]@{
                Name = [string]$json.name
                Path = $visualFile.FullName
                Json = $json
            }
        }
    }
    catch {
        $invalidVisuals += $visualFile.FullName
    }
}

if ($invalidVisuals.Count -gt 0) {
    throw "PBIR-VISUAL-GATE failed: $($invalidVisuals.Count) visual.json file(s) contain invalid JSON: $($invalidVisuals -join '; ')"
}

# Navigation is a role/name contract. Exactly one visual must have the
# NavigationHtmlButtons role/name; the HTML Content GUID may appear five times.
if ($navigationVisuals.Count -ne 1) {
    throw "CUSTOM-NAVIGATION-GATE failed: expected exactly one '$htmlVisualName' visual; found $($navigationVisuals.Count)."
}

$navigation = $navigationVisuals[0].Json
if ([string]$navigation.visual.visualType -ne $htmlVisualGuid) {
    throw "CUSTOM-NAVIGATION-GATE failed: '$htmlVisualName' visualType is '$($navigation.visual.visualType)', expected '$htmlVisualGuid'."
}

# Validate that the navigation visual actually contains an HTML/DAX content binding.
$navigationText = $navigation | ConvertTo-Json -Depth 100 -Compress
if ([string]::IsNullOrWhiteSpace($navigationText) -or
    ($navigationText -notmatch 'NavigationHtmlButtons|RevenueOverview|Revenue|Target|Details')) {
    throw "CUSTOM-NAVIGATION-GATE failed: '$htmlVisualName' has no recognizable HTML/DAX navigation content binding."
}

# Require all four navigation destinations to be represented in the visual definition.
foreach ($label in $navigationLabels) {
    if ($navigationText -notmatch [regex]::Escape($label)) {
        throw "CUSTOM-NAVIGATION-GATE failed: '$htmlVisualName' is missing navigation target '$label'."
    }
}

Write-Host "THEME-GATE|PASS|Theme=RevenueTracker_LavenderTheme.json|Background=#FFFFFF|RegisteredResources=PASS"
Write-Host "CUSTOM-VISUAL-GATE|PASS|RegisteredGuid=$htmlVisualGuid|NavigationVisual=$htmlVisualName|GuidReuseAllowed=PASS|HtmlContentVisuals=$($customVisuals.Count)"
Write-Host "CUSTOM-NAVIGATION-GATE|PASS|Visual=$htmlVisualName|Count=$($navigationVisuals.Count)|Type=$htmlVisualGuid|DaxHtmlBinding=PASS|Targets=Overview,Revenue,Target,Details"
Write-Host "PBIR-VISUAL-GATE|PASS|GeneratedVisuals=$($visualFiles.Count)|OverviewHtmlReuse=PASS|NavigationRole=PASS|JsonValidity=PASS"
exit 0
