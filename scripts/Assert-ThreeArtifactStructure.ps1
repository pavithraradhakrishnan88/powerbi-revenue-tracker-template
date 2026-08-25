#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GeneratedRoot,
    [Parameter(Mandatory=$true)][ValidateSet('report','semantic-model','pbip','assembly')][string]$Gate
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($GeneratedRoot); $report=Join-Path $root 'RevenueTracker.Report'; $model=Join-Path $root 'RevenueTracker.SemanticModel'; $pbip=Join-Path $root 'RevenueTracker.pbip'
if($Gate -eq 'report' -or $Gate -eq 'assembly'){
 if(!(Test-Path $report -PathType Container)){throw 'STRUCTURE-REPORT-GATE failed: RevenueTracker.Report is missing.'}
 foreach($p in @((Join-Path $report '.platform'),(Join-Path $report 'definition.pbir'),(Join-Path $report 'definition/version.json'),(Join-Path $report 'definition/report.json'),(Join-Path $report 'definition/pages/pages.json'))){if(!(Test-Path $p -PathType Leaf)){throw "STRUCTURE-REPORT-GATE failed: missing '$p'."}}
 $pbir=Get-Content -Raw (Join-Path $report 'definition.pbir')|ConvertFrom-Json;if([string]$pbir.version -ne '4.0'){throw 'STRUCTURE-REPORT-GATE failed: definition.pbir version must be 4.0.'}
 $version=Get-Content -Raw (Join-Path $report 'definition/version.json')|ConvertFrom-Json;if([string]$version.version -ne '2.0.0'){throw 'STRUCTURE-REPORT-GATE failed: definition/version.json version must be 2.0.0.'}
 $pages=Get-Content -Raw (Join-Path $report 'definition/pages/pages.json')|ConvertFrom-Json;if(@($pages.pageOrder).Count -eq 0){throw 'STRUCTURE-REPORT-GATE failed: pageOrder is empty.'}
 foreach($pageName in @($pages.pageOrder)){ $page=Join-Path $report "definition/pages/$pageName";if(!(Test-Path (Join-Path $page 'page.json'))){throw "STRUCTURE-REPORT-GATE failed: page.json missing for '$pageName'."};$visuals=Join-Path $page 'visuals';if(Test-Path $visuals){foreach($v in @(Get-ChildItem $visuals -Directory)){ $vj=Join-Path $v.FullName 'visual.json';if(!(Test-Path $vj)){throw "STRUCTURE-REPORT-GATE failed: visual.json missing in '$($v.Name)'."};Get-Content -Raw $vj|ConvertFrom-Json|Out-Null }}}
 Write-Host "STRUCTURE-REPORT-GATE|PASS|pages=$(@($pages.pageOrder).Count)|versionJson=2.0.0|json=valid|platform=present";if($Gate -eq 'report'){exit 0}
}
if($Gate -eq 'semantic-model' -or $Gate -eq 'assembly'){
 if(!(Test-Path $model -PathType Container)){throw 'STRUCTURE-SEMANTIC-GATE failed: RevenueTracker.SemanticModel is missing.'};foreach($p in @((Join-Path $model '.platform'),(Join-Path $model 'definition/tables'),(Join-Path $model 'definition/relationships.tmdl'))){if(!(Test-Path $p)){throw "STRUCTURE-SEMANTIC-GATE failed: missing '$p'."}}
 $tmdls=@(Get-ChildItem $model -Recurse -Filter '*.tmdl' -File);if($tmdls.Count -eq 0){throw 'STRUCTURE-SEMANTIC-GATE failed: no TMDL files found.'};foreach($t in $tmdls){$b=[IO.File]::ReadAllBytes($t.FullName);if($b.Length -ge 3 -and $b[0]-eq 0xEF -and $b[1]-eq 0xBB -and $b[2]-eq 0xBF){throw "STRUCTURE-SEMANTIC-GATE failed: UTF-8 BOM in '$($t.FullName)'."}}
 Write-Host "STRUCTURE-SEMANTIC-GATE|PASS|TmdlFiles=$($tmdls.Count)|platform=present|BOM=absent";if($Gate -eq 'semantic-model'){exit 0}
}
if($Gate -eq 'pbip' -or $Gate -eq 'assembly'){
 if(!(Test-Path $pbip -PathType Leaf)){throw 'STRUCTURE-PBIP-GATE failed: RevenueTracker.pbip is missing.'};$p=Get-Content -Raw $pbip|ConvertFrom-Json;if([string]$p.version -ne '1.0'){throw 'STRUCTURE-PBIP-GATE failed: .pbip version must be 1.0.'};if($p.artifacts.Count -lt 1 -or [string]$p.artifacts[0].report.path -ne 'RevenueTracker.Report'){throw 'STRUCTURE-PBIP-GATE failed: report reference is missing.'};Write-Host 'STRUCTURE-PBIP-GATE|PASS|json=valid|reportRef=present';if($Gate -eq 'pbip'){exit 0}
}
$pbir=Get-Content -Raw (Join-Path $report 'definition.pbir')|ConvertFrom-Json;if([string]$pbir.datasetReference.byPath.path -ne '../RevenueTracker.SemanticModel'){throw "THREE-ARTIFACT-ASSEMBLY-GATE failed: unexpected datasetReference '$($pbir.datasetReference.byPath.path)'."};$resolved=[IO.Path]::GetFullPath((Join-Path $report $pbir.datasetReference.byPath.path));$expected=[IO.Path]::GetFullPath($model);if($resolved.TrimEnd('\\') -ine $expected.TrimEnd('\\')){throw 'THREE-ARTIFACT-ASSEMBLY-GATE failed: datasetReference does not resolve to assembled semantic model.'};Write-Host 'THREE-ARTIFACT-ASSEMBLY-GATE|PASS|Report=present|SemanticModel=present|PBIP=present|DatasetReference=coherent|versionJson=present'
