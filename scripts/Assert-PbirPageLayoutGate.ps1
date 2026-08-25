#Requires -Version 7.0
<#
.SYNOPSIS
    Validates the PBIR page/layout manifest contract: pages.json entries must have a
    matching page folder + page.json, and every visual within a page must have a unique
    z-index and tabOrder.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$GeneratedRoot
)

$ErrorActionPreference = "Stop"

$pagesDir = Join-Path $GeneratedRoot "RevenueTracker.Report/definition/pages"
$pagesJsonPath = Join-Path $pagesDir "pages.json"

if (-not (Test-Path $pagesJsonPath)) {
    Write-Error "pages.json not found at $pagesJsonPath"
}

$pagesJson = Get-Content -Path $pagesJsonPath -Raw | ConvertFrom-Json

if ($pagesJson.pageOrder.Count -eq 0) {
    Write-Error "pages.json pageOrder is empty — this is exactly the totalPages:0 failure mode."
}

foreach ($pageName in $pagesJson.pageOrder) {
    $pageFolder = Join-Path $pagesDir $pageName
    $pageJsonPath = Join-Path $pageFolder "page.json"

    if (-not (Test-Path $pageFolder)) {
        Write-Error "pages.json references '$pageName' but no matching folder exists at $pageFolder"
    }
    if (-not (Test-Path $pageJsonPath)) {
        Write-Error "Page folder '$pageName' has no page.json"
    }

    $pageJson = Get-Content -Path $pageJsonPath -Raw | ConvertFrom-Json
    if ($pageJson.name -ne $pageName) {
        Write-Error "page.json 'name' ($($pageJson.name)) does not match its folder/manifest name ($pageName)"
    }

    $visualsDir = Join-Path $pageFolder "visuals"
    if (Test-Path $visualsDir) {
        $zValues = @()
        $tabValues = @()

        Get-ChildItem -Path $visualsDir -Directory | ForEach-Object {
            $visualJsonPath = Join-Path $_.FullName "visual.json"
            if (-not (Test-Path $visualJsonPath)) {
                Write-Error "Visual folder '$($_.Name)' on page '$pageName' has no visual.json"
            }
            $visualJson = Get-Content -Path $visualJsonPath -Raw | ConvertFrom-Json
            $zValues += $visualJson.position.z
            $tabValues += $visualJson.position.tabOrder
        }

        $dupZ = $zValues | Group-Object | Where-Object { $_.Count -gt 1 }
        if ($dupZ.Count -gt 0) {
            Write-Error "Page '$pageName' has duplicate visual z-index value(s): $($dupZ.Name -join ', ')"
        }

        $dupTab = $tabValues | Group-Object | Where-Object { $_.Count -gt 1 }
        if ($dupTab.Count -gt 0) {
            Write-Error "Page '$pageName' has duplicate visual tabOrder value(s): $($dupTab.Name -join ', ')"
        }
    }
}

# reportExtensions.json is optional report metadata. Do not manufacture an empty
# extension file merely to satisfy this structural gate. If absent, that is valid
# when the report has no extension definitions. If present, validate its JSON and
# the reportExtension/1.0.0 root contract before allowing it through.
$reportExtensionsPath = Join-Path $GeneratedRoot "RevenueTracker.Report/definition/reportExtensions.json"
if (Test-Path $reportExtensionsPath) {
    try {
        $extensions = Get-Content -Path $reportExtensionsPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Error "reportExtensions.json is present but is not valid JSON: $($_.Exception.Message)"
    }

    $expectedSchema = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/reportExtension/1.0.0/schema.json"
    if ($null -eq $extensions.'$schema' -or $extensions.'$schema' -ne $expectedSchema) {
        Write-Error "reportExtensions.json has an invalid or missing reportExtension/1.0.0 `$schema."
    }

    if ([string]::IsNullOrWhiteSpace([string]$extensions.name)) {
        Write-Error "reportExtensions.json has a missing or empty 'name'."
    }

    if ($null -ne $extensions.entities -and $extensions.entities -isnot [System.Array]) {
        Write-Error "reportExtensions.json 'entities' must be an array when present."
    }

    Write-Host "PASS: reportExtensions.json is present and passes JSON/schema/content checks." -ForegroundColor Green
}
else {
    Write-Host "PASS: reportExtensions.json absent; no optional report-extension metadata is required." -ForegroundColor Green
}

Write-Host "PASS: pages.json <-> page folder contract holds, no z/tabOrder collisions." -ForegroundColor Green
exit 0
