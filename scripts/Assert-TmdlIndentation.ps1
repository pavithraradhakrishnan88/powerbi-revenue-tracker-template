param(
    [Parameter(Mandatory = $true)]
    [string]$SemanticModelRoot
)

$ErrorActionPreference = 'Stop'
$tablesRoot = Join-Path $SemanticModelRoot 'definition\tables'
if (!(Test-Path $tablesRoot -PathType Container)) {
    throw "TMDL-INDENTATION-GATE failed: missing $tablesRoot"
}

$files = @(Get-ChildItem $tablesRoot -Filter '*.tmdl' -File -Recurse)
if ($files.Count -eq 0) { throw 'TMDL-INDENTATION-GATE failed: no table TMDL files found.' }

foreach ($file in $files) {
    $lines = Get-Content $file.FullName
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^\t+sourceColumn:\s*\S') {
            $leading = ($line -replace '\S.*$', '')
            if ($leading.Length -ne 2) {
                throw "TMDL-INDENTATION-GATE failed: $($file.FullName):$($i + 1) expected two tabs before sourceColumn, found $($leading.Length)."
            }
        }
    }
}

Write-Host "TMDL-INDENTATION-GATE|PASS|Files=$($files.Count)|SourceColumnIndentation=2-tabs"