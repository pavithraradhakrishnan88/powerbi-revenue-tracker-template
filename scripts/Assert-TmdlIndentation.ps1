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
            $previous = if ($i -gt 0) { $lines[$i - 1] } else { '' }
            if ($previous -notmatch '^\t\t(summarizeBy|dataType|lineageTag)') {
                throw "TMDL-INDENTATION-GATE failed: $($file.FullName):$($i + 1) sourceColumn has invalid parent indentation."
            }
            if (($line -replace '^\t+','').Length -eq 0) {
                throw "TMDL-INDENTATION-GATE failed: $($file.FullName):$($i + 1) is empty."
            }
            if (($line -replace '^\t','').StartsWith("\t")) {
                # sourceColumn must be a table-column property (two tabs), not a nested child.
                $indent = ($line -replace '^([^\t]*).*','$1').Length
                if ($indent -ne 2) {
                    throw "TMDL-INDENTATION-GATE failed: $($file.FullName):$($i + 1) expected two tabs before sourceColumn, found $indent."
                }
            }
        }
    }
}

Write-Host "TMDL-INDENTATION-GATE|PASS|Files=$($files.Count)|SourceColumnIndentation=2-tabs"