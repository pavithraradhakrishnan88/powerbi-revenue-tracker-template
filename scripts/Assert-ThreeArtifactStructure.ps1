#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$GeneratedRoot)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($GeneratedRoot)
$report = Join-Path $root 'RevenueTracker.Report'
$model = Join-Path $root 'RevenueTracker.SemanticModel'
$pbip = Join-Path $root 'RevenueTracker.pbip'
foreach ($p in @($report,$model,$pbip)) { if (!(Test-Path $p)) { throw "STRUCTURE-GATE failed: missing required artifact '$p'." } }
foreach ($p in @((Join-Path $report '.platform'),(Join-Path $model '.platform'))) { if (!(Test-Path $p -PathType Leaf)) { throw "STRUCTURE-GATE failed: missing .platform '$p'." } }
$pbirPath = Join-Path $report 'definition.pbir'
$pbir = Get-Content -Raw $pbirPath | ConvertFrom-Json
if ([string]$pbir.version -ne '4.0') { throw 'STRUCTURE-GATE failed: definition.pbir version must be 4.0.' }
if ([string]$pbir.datasetReference.byPath.path -ne '../RevenueTracker.SemanticModel') { throw "STRUCTURE-GATE failed: unexpected datasetReference path '$($pbir.datasetReference.byPath.path)'." }
$pbipJson = Get-Content -Raw $pbip | ConvertFrom-Json
if ([string]$pbipJson.version -ne '1.0') { throw 'STRUCTURE-GATE failed: RevenueTracker.pbip version must be 1.0.' }
if ($pbipJson.artifacts.Count -lt 1 -or [string]$pbipJson.artifacts[0].report.path -ne 'RevenueTracker.Report') { throw 'STRUCTURE-GATE failed: .pbip report reference is missing or incorrect.' }
$pagesJsonPath = Join-Path $report 'definition/pages/pages.json'
if (!(Test-Path $pagesJsonPath)) { throw 'STRUCTURE-GATE failed: pages.json is missing.' }
$pages = Get-Content -Raw $pagesJsonPath | ConvertFrom-Json
if (@($pages.pageOrder).Count -eq 0) { throw 'STRUCTURE-GATE failed: pages.json pageOrder is empty.' }
foreach ($pageName in @($pages.pageOrder)) {
    $page = Join-Path $report "definition/pages/$pageName"
    if (!(Test-Path (Join-Path $page 'page.json'))) { throw "STRUCTURE-GATE failed: page.json missing for '$pageName'." }
    $visuals = Join-Path $page 'visuals'
    if (Test-Path $visuals) { foreach ($v in @(Get-ChildItem $visuals -Directory)) { $vj = Join-Path $v.FullName 'visual.json'; if (!(Test-Path $vj)) { throw "STRUCTURE-GATE failed: visual.json missing in '$($v.Name)'." }; Get-Content -Raw $vj | ConvertFrom-Json | Out-Null } }
}
$tables = Join-Path $model 'definition/tables'
$relationships = Join-Path $model 'definition/relationships.tmdl'
if (!(Test-Path $tables -PathType Container)) { throw 'STRUCTURE-GATE failed: semantic-model tables directory is missing.' }
if (!(Test-Path $relationships -PathType Leaf)) { throw 'STRUCTURE-GATE failed: semantic-model relationships.tmdl is missing.' }
$tmdls = @(Get-ChildItem $model -Recurse -Filter '*.tmdl' -File)
if ($tmdls.Count -eq 0) { throw 'STRUCTURE-GATE failed: no TMDL files found.' }
foreach ($t in $tmdls) { $bytes = [IO.File]::ReadAllBytes($t.FullName); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "STRUCTURE-GATE failed: UTF-8 BOM in '$($t.FullName)'." } }
$resolved = [IO.Path]::GetFullPath((Join-Path $report $pbir.datasetReference.byPath.path))
$expected = [IO.Path]::GetFullPath($model)
if ($resolved.TrimEnd('\') -ine $expected.TrimEnd('\')) { throw 'ASSEMBLY-GATE failed: report datasetReference does not resolve to the assembled semantic model.' }
Write-Host "THREE-ARTIFACT-STRUCTURE-GATE|PASS|Report=present|SemanticModel=present|PBIP=present|Pages=$(@($pages.pageOrder).Count)|TmdlFiles=$($tmdls.Count)"
Write-Host 'THREE-ARTIFACT-ASSEMBLY-GATE|PASS|DatasetReference=coherent|ReportToSemanticModel=resolved'
