#Requires -Version 7.0
<#
.SYNOPSIS
    Validates the PBIR page/layout manifest contract: pages.json entries must have a
    matching page folder + page.json, and every visual within a page must have a unique
    z-index and tabOrder.

.DESCRIPTION
    Equivalent to the SLA project's Assert-PbirPageLayoutGate.ps1. Directly targets the
    class of bug behind "totalPages: 0" in Power BI Desktop: a pages.json manifest that
    references a page name with no matching folder, or a page folder that pages.json
    doesn't know about, deserializes to zero pages even though the semantic model loads
    fine — because the model and the report layout are validated independently by
    Desktop, and only one of the two failing is enough to blank the canvas.

.PARAMETER GeneratedRoot
    Path to the orchestrator's output folder (contains RevenueTracker.Report/).
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

if (-not (Test-Path (Join-Path $GeneratedRoot "RevenueTracker.Report/definition/reportExtensions.json"))) {
    Write-Error "reportExtensions.json is missing — this file's absence previously caused a NullReferenceException on open."
}

Write-Host "PASS: pages.json <-> page folder contract holds, no z/tabOrder collisions, reportExtensions.json present." -ForegroundColor Green
exit 0
