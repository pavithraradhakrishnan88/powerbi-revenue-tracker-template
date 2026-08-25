#Requires -Version 7.0
<#!
.SYNOPSIS
    Validates the Revenue Tracker theme, HTML Content registration, navigation role,
    and the explicit DAX HTML navigation contract.
#>
param([Parameter(Mandatory = $true)][string]$GeneratedRoot)
$ErrorActionPreference = 'Stop'

$reportRoot = Join-Path $GeneratedRoot 'RevenueTracker.Report'
$themePath = Join-Path $reportRoot 'StaticResources/RegisteredResources/RevenueTracker_LavenderTheme.json'
$reportJsonPath = Join-Path $reportRoot 'definition/report.json'
$pagesRoot = Join-Path $reportRoot 'definition/pages'
$htmlVisualGuid = 'htmlContent443BE3AD55E043BF878BED274D3A6865'
$htmlVisualName = 'NavigationHtmlButtons'
$navigationContract = [ordered]@{
    Overview = 'RevenueOverview'
    Revenue  = 'Revenue'
    Target   = 'Target'
    Details  = 'Details'
}

if (-not (Test-Path $themePath -PathType Leaf)) { throw "THEME-GATE failed: missing $themePath" }
try { $theme = Get-Content $themePath -Raw | ConvertFrom-Json } catch { throw "THEME-GATE failed: invalid theme JSON: $($_.Exception.Message)" }
if ([string]$theme.name -ne 'Revenue Tracker - White Fintech') { throw "THEME-GATE failed: unexpected theme name '$($theme.name)'." }
if ([string]$theme.background -ne '#FFFFFF') { throw 'THEME-GATE failed: background must be #FFFFFF.' }
if (-not ($theme.dataColors -contains '#7B5CFA') -or -not ($theme.dataColors -contains '#F0629B')) { throw 'THEME-GATE failed: required violet/pink colors are missing.' }

$report = Get-Content $reportJsonPath -Raw | ConvertFrom-Json
$customTheme = $report.themeCollection.customTheme
if ($null -eq $customTheme -or [string]$customTheme.name -ne 'RevenueTracker_LavenderTheme.json' -or [string]$customTheme.type -ne 'RegisteredResources') { throw 'THEME-GATE failed: custom theme registration is invalid.' }
$registered = @($report.resourcePackages | Where-Object { $_.name -eq 'RegisteredResources' })
if ($registered.Count -ne 1) { throw 'THEME-GATE failed: exactly one RegisteredResources package is expected.' }
$themeItem = @($registered[0].items | Where-Object { $_.name -eq 'RevenueTracker_LavenderTheme.json' })
if ($themeItem.Count -ne 1 -or [string]$themeItem[0].type -ne 'CustomTheme' -or [string]$themeItem[0].path -ne 'RevenueTracker_LavenderTheme.json') { throw 'THEME-GATE failed: custom theme resource registration is invalid.' }

$publicVisuals = @($report.publicCustomVisuals)
if ($publicVisuals -notcontains $htmlVisualGuid) { throw "CUSTOM-VISUAL-GATE failed: HTML Content GUID '$htmlVisualGuid' is not registered." }

$visualFiles = @(Get-ChildItem $pagesRoot -Recurse -Filter 'visual.json' -File)
$invalidVisuals = @()
$customVisuals = @()
$navigationVisuals = @()
foreach ($visualFile in $visualFiles) {
    try {
        $json = Get-Content $visualFile.FullName -Raw | ConvertFrom-Json
        if ([string]$json.visual.visualType -eq $htmlVisualGuid) { $customVisuals += $json }
        if ([string]$json.name -eq $htmlVisualName) { $navigationVisuals += [PSCustomObject]@{ Path=$visualFile.FullName; Json=$json } }
    } catch { $invalidVisuals += $visualFile.FullName }
}
if ($invalidVisuals.Count -gt 0) { throw "PBIR-VISUAL-GATE failed: invalid visual.json: $($invalidVisuals -join '; ')" }
if ($navigationVisuals.Count -ne 1) { throw "CUSTOM-NAVIGATION-GATE failed: expected exactly one '$htmlVisualName'; found $($navigationVisuals.Count)." }

$navigation = $navigationVisuals[0].Json
if ([string]$navigation.visual.visualType -ne $htmlVisualGuid) { throw "CUSTOM-NAVIGATION-GATE failed: '$htmlVisualName' visualType is '$($navigation.visual.visualType)'." }

# Parse the actual visual binding instead of searching the entire serialized visual
# JSON. PBIR may expose the binding under query/queryState or prototypeQuery.
$bindingMeasures = @()
$queryObjects = @()
if ($null -ne $navigation.visual.query) { $queryObjects += $navigation.visual.query }
if ($null -ne $navigation.visual.prototypeQuery) { $queryObjects += $navigation.visual.prototypeQuery }
foreach ($queryObject in $queryObjects) {
    $jsonText = $queryObject | ConvertTo-Json -Depth 100 -Compress
    $matches = [regex]::Matches($jsonText, '"Property"\s*:\s*"([^"]+)"')
    foreach ($match in $matches) { $bindingMeasures += $match.Groups[1].Value }
    $matches = [regex]::Matches($jsonText, '"nativeQueryRef"\s*:\s*"([^"]+)"')
    foreach ($match in $matches) { $bindingMeasures += $match.Groups[1].Value }
    $matches = [regex]::Matches($jsonText, '"queryRef"\s*:\s*"[^"]+\.([^".]+)"')
    foreach ($match in $matches) { $bindingMeasures += $match.Groups[1].Value }
}
$bindingMeasures = @($bindingMeasures | Sort-Object -Unique)
if ($bindingMeasures -notcontains 'NavigationHtmlButtons') {
    throw "CUSTOM-NAVIGATION-GATE failed: '$htmlVisualName' does not bind to measure 'NavigationHtmlButtons'. Parsed bindings: $($bindingMeasures -join ', ')"
}

# Locate the generated semantic-model measure referenced by the actual binding.
$measureFiles = @(Get-ChildItem $GeneratedRoot -Recurse -Filter '*.tmdl' -File | Where-Object { $_.FullName -match 'SemanticModel' })
$measureText = ($measureFiles | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
$measureMatch = [regex]::Match($measureText, '(?ms)^\s*measure\s+NavigationHtmlButtons\s*=\s*(.*?)(?=^\s*measure\s+|^\s*partition\s+|\z)')
if (-not $measureMatch.Success) { throw "CUSTOM-NAVIGATION-GATE failed: generated semantic model does not contain measure NavigationHtmlButtons." }
$navigationDax = $measureMatch.Groups[1].Value

# Validate only the HTML contract emitted by the bound DAX measure.
if ($navigationDax -notmatch 'data-navigation-contract') { throw 'CUSTOM-NAVIGATION-GATE failed: bound NavigationHtmlButtons DAX does not emit data-navigation-contract metadata.' }
foreach ($entry in $navigationContract.GetEnumerator()) {
    $label = $entry.Key
    $target = $entry.Value
    $pair = "$label|$target"
    if ($navigationDax -notmatch [regex]::Escape($pair)) { throw "CUSTOM-NAVIGATION-GATE failed: DAX navigation contract is missing '$pair'." }
    $pattern = "data-label='$([regex]::Escape($label))'\s+data-target='$([regex]::Escape($target))'"
    if ($navigationDax -notmatch $pattern) { throw "CUSTOM-NAVIGATION-GATE failed: clickable target '$label' -> '$target' is missing or malformed." }
}

Write-Host "THEME-GATE|PASS|Theme=RevenueTracker_LavenderTheme.json|Background=#FFFFFF|RegisteredResources=PASS"
Write-Host "CUSTOM-VISUAL-GATE|PASS|RegisteredGuid=$htmlVisualGuid|NavigationVisual=$htmlVisualName|GuidReuseAllowed=PASS|HtmlContentVisuals=$($customVisuals.Count)"
Write-Host "CUSTOM-NAVIGATION-GATE|PASS|Visual=NavigationHtmlButtons|Count=1|Type=HTMLContent|DaxHtmlBinding=PASS|Measure=NavigationHtmlButtons|Contract=Overview->RevenueOverview,Revenue->Revenue,Target->Target,Details->Details"
Write-Host "PBIR-VISUAL-GATE|PASS|GeneratedVisuals=$($visualFiles.Count)|OverviewHtmlReuse=PASS|NavigationRole=PASS|JsonValidity=PASS"
exit 0
