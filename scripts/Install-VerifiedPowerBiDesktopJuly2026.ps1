param(
  [Parameter(Mandatory=$true)][string]$ExpectedVersion,
  [Parameter(Mandatory=$true)][string]$ExpectedRelease,
  [Parameter(Mandatory=$true)][string]$DiagnosticsRoot
)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Path $DiagnosticsRoot -Force | Out-Null
$diag=Join-Path $DiagnosticsRoot 'desktop-environment.json'
$log=Join-Path $DiagnosticsRoot 'desktop-install.log'
$processDiag=Join-Path $DiagnosticsRoot 'desktop-install-timeout-processes.json'
$installerTimeoutSeconds=900

$ExpectedInstallerUrl='https://download.microsoft.com/download/8/8/0/880BCA75-79DD-466A-927D-1ABF1F5454B0/PBIDesktopSetup-2026-07_x64.exe'
$ExpectedInstallerSha256='FF265B2DD4A52E77475452DE014ED5BABB4C73B83284FC17ADDA7D774A62C5C4'

function Save-Diagnostic($obj){$obj|ConvertTo-Json -Depth 10|Set-Content $diag -Encoding utf8}
function Get-DesktopCandidates {
  $paths=@(
    'C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe',
    'C:\Program Files\Microsoft Power BI Desktop RS\bin\PBIDesktop.exe',
    'C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktopStore.exe'
  )
  foreach($p in ($paths|Sort-Object -Unique)){
    if(Test-Path $p -PathType Leaf){
      $i=Get-Item $p
      [pscustomobject]@{Path=$p;ProductVersion=$i.VersionInfo.ProductVersion;FileVersion=$i.VersionInfo.FileVersion}
    }
  }
}
function Get-InstallerProcessSnapshot {
  @(Get-Process -Name 'PBIDesktopSetup','msiexec','PBIDesktop','PBIDesktopStore' -ErrorAction SilentlyContinue |
    Select-Object Id,ProcessName,StartTime,CPU,Path)
}
$state=[ordered]@{ExpectedVersion=$ExpectedVersion;ExpectedRelease=$ExpectedRelease;Source=$null;ArchiveValidated=$false;Path=$null;ProductVersion=$null;Installer=$null;InstallerSha256=$null;ExpectedInstallerSha256=$ExpectedInstallerSha256;InstallerVersion=$null;SignatureStatus=$null;Signer=$null;InstallerExitCode=$null;InstallerTimeoutSeconds=$installerTimeoutSeconds;Error=$null}
try {
  if($ExpectedVersion -ne '2.156.951.0' -or $ExpectedRelease -ne '26.07'){throw "Verifier is pinned to July 2026 / 26.07 / 2.156.951.0; received version=$ExpectedVersion release=$ExpectedRelease."}
  $desktop=@(Get-DesktopCandidates)|Where-Object ProductVersion -eq $ExpectedVersion|Select-Object -First 1
  if($desktop){$state.Source='Installed';$state.Path=$desktop.Path;$state.ProductVersion=$desktop.ProductVersion;Save-Diagnostic ([pscustomobject]$state);Write-Host "DESKTOP-ENVIRONMENT-GATE|PASS|Source=Installed|ProductVersion=$($desktop.ProductVersion)|Path=$($desktop.Path)";Write-Host "DESKTOP-VERSION-GATE|PASS|Version=$ExpectedVersion|Release=$ExpectedRelease";exit 0}

  Write-Host "DESKTOP-ENVIRONMENT-GATE|INSTALL|RequiredVersion=$ExpectedVersion|Release=$ExpectedRelease|Source=MicrosoftJulyArchive"
  $archiveUrl='https://learn.microsoft.com/en-us/power-bi/fundamentals/desktop-latest-update-archive'
  $archive=Invoke-WebRequest -Uri $archiveUrl -UseBasicParsing
  if($archive.Content -notmatch [regex]::Escape("July 2026 update (version $ExpectedVersion)")){throw "Microsoft archive does not identify July 2026 version $ExpectedVersion."}
  $state.ArchiveValidated=$true
  Write-Host "DESKTOP-ARCHIVE-GATE|PASS|Release=July 2026|Version=$ExpectedVersion"

  $installer=Join-Path $DiagnosticsRoot 'PBIDesktopSetup_x64.exe'
  $state.Installer=$ExpectedInstallerUrl
  Invoke-WebRequest -Uri $ExpectedInstallerUrl -OutFile $installer -UseBasicParsing
  $actualSha=(Get-FileHash -Path $installer -Algorithm SHA256).Hash.ToUpperInvariant();$state.InstallerSha256=$actualSha
  if($actualSha -ne $ExpectedInstallerSha256){throw "Installer SHA-256 mismatch: actual=$actualSha expected=$ExpectedInstallerSha256."}
  Write-Host "DESKTOP-BINARY-HASH-GATE|PASS|SHA256=$actualSha"

  $sig=Get-AuthenticodeSignature $installer
  $state.SignatureStatus=[string]$sig.Status;$state.Signer=if($sig.SignerCertificate){$sig.SignerCertificate.Subject}else{$null}
  if($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft'){throw "Installer Authenticode validation failed: Status=$($sig.Status); Signer=$($state.Signer)"}
  Write-Host "DESKTOP-AUTHENTICODE-GATE|PASS|Status=$($sig.Status)|Signer=$($state.Signer)"

  $iv=(Get-Item $installer).VersionInfo.ProductVersion;$state.InstallerVersion=$iv
  if($iv -ne $ExpectedVersion){throw "Downloaded installer ProductVersion=$iv; expected $ExpectedVersion."}
  Write-Host "DESKTOP-INSTALLER-VERSION-GATE|PASS|ProductVersion=$iv"

  $p=Start-Process -FilePath $installer -ArgumentList '/quiet','/norestart','ACCEPT_EULA=1',"/log=$log" -PassThru -NoNewWindow
  Write-Host "DESKTOP-INSTALL-GATE|START|TimeoutSeconds=$installerTimeoutSeconds|PID=$($p.Id)"
  $stopwatch=[Diagnostics.Stopwatch]::StartNew()
  while(-not $p.HasExited -and $stopwatch.Elapsed.TotalSeconds -lt $installerTimeoutSeconds){
    Start-Sleep -Seconds 5
    $elapsed=[int]$stopwatch.Elapsed.TotalSeconds
    if(($elapsed % 30) -eq 0){Write-Host "DESKTOP-INSTALL-GATE|POLL|PID=$($p.Id)|ElapsedSeconds=$elapsed|TimeoutSeconds=$installerTimeoutSeconds"}
    $p.Refresh()
  }
  $stopwatch.Stop()

  if(-not $p.HasExited){
    $snapshot=@(Get-InstallerProcessSnapshot)
    $snapshot|ConvertTo-Json -Depth 5|Set-Content $processDiag -Encoding utf8
    if(Test-Path $log -PathType Leaf){Copy-Item $log (Join-Path $DiagnosticsRoot 'desktop-install-timeout.log') -Force}
    Write-Host "DESKTOP-INSTALL-GATE|TIMEOUT|PID=$($p.Id)|ElapsedSeconds=$([int]$stopwatch.Elapsed.TotalSeconds)|TimeoutSeconds=$installerTimeoutSeconds|Log=$log|ProcessDiagnostics=$processDiag"
    try{Stop-Process -Id $p.Id -Force -ErrorAction Stop;Write-Host "DESKTOP-INSTALL-GATE|TERMINATED|PID=$($p.Id)"}catch{Write-Host "DESKTOP-INSTALL-GATE|TERMINATE-WARN|PID=$($p.Id)|Error=$($_.Exception.Message)"}
    $state.Error="Power BI Desktop installer timed out after $installerTimeoutSeconds seconds. Diagnostics: $log; $processDiag"
    Save-Diagnostic ([pscustomobject]$state)
    throw $state.Error
  }

  $p.Refresh();$state.InstallerExitCode=$p.ExitCode
  Write-Host "DESKTOP-INSTALL-GATE|EXIT|ExitCode=$($p.ExitCode)|ElapsedSeconds=$([int]$stopwatch.Elapsed.TotalSeconds)"
  if($p.ExitCode -notin @(0,3010,1641)){throw "Installer exit code $($p.ExitCode)."}
  Write-Host "DESKTOP-INSTALL-GATE|PASS|ExitCode=$($p.ExitCode)"

  $desktop=@(Get-DesktopCandidates)|Where-Object ProductVersion -eq $ExpectedVersion|Select-Object -First 1
  if(-not $desktop){throw "Exact $ExpectedVersion was not detected after installation."}
  $state.Source='MicrosoftJulyArchive';$state.Path=$desktop.Path;$state.ProductVersion=$desktop.ProductVersion;Save-Diagnostic ([pscustomobject]$state)
  Write-Host "DESKTOP-ENVIRONMENT-GATE|PASS|Source=MicrosoftJulyArchive|ProductVersion=$($desktop.ProductVersion)|Path=$($desktop.Path)";Write-Host "DESKTOP-VERSION-GATE|PASS|Version=$ExpectedVersion|Release=$ExpectedRelease"
}catch{
  $state.Error=$_.Exception.Message;Save-Diagnostic ([pscustomobject]$state);Write-Host "DESKTOP-ENVIRONMENT-GATE|FAIL|RequiredVersion=$ExpectedVersion|Release=$ExpectedRelease|Diagnostics=$diag";throw
}
