param(
  [Parameter(Mandatory=$true)][string]$ExpectedVersion,
  [Parameter(Mandatory=$true)][string]$ExpectedRelease,
  [Parameter(Mandatory=$true)][string]$DiagnosticsRoot
)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Path $DiagnosticsRoot -Force | Out-Null
$diag=Join-Path $DiagnosticsRoot 'desktop-environment.json'
$log=Join-Path $DiagnosticsRoot 'desktop-install.log'

function Save-Diagnostic($obj){$obj|ConvertTo-Json -Depth 10|Set-Content $diag -Encoding utf8}
function Get-DesktopCandidates {
  $paths=@('C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe','C:\Program Files\Microsoft Power BI Desktop RS\bin\PBIDesktop.exe','C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktopStore.exe')
  $paths += @(Get-ChildItem 'C:\Program Files' -Filter 'PBIDesktop.exe' -File -Recurse -ErrorAction SilentlyContinue|Select-Object -ExpandProperty FullName)
  foreach($p in ($paths|Sort-Object -Unique)){if(Test-Path $p -PathType Leaf){$i=Get-Item $p;[pscustomobject]@{Path=$p;ProductVersion=$i.VersionInfo.ProductVersion;FileVersion=$i.VersionInfo.FileVersion}}}
}
$state=[ordered]@{ExpectedVersion=$ExpectedVersion;ExpectedRelease=$ExpectedRelease;Source=$null;Path=$null;ProductVersion=$null;Installer=$null;InstallerVersion=$null;SignatureStatus=$null;Signer=$null;InstallerExitCode=$null;Error=$null}
try {
  $desktop=@(Get-DesktopCandidates)|Where-Object ProductVersion -eq $ExpectedVersion|Select-Object -First 1
  if($desktop){$state.Source='Installed';$state.Path=$desktop.Path;$state.ProductVersion=$desktop.ProductVersion;Save-Diagnostic ([pscustomobject]$state);Write-Host "DESKTOP-ENVIRONMENT-GATE|PASS|Source=Installed|ProductVersion=$($desktop.ProductVersion)|Path=$($desktop.Path)";Write-Host "DESKTOP-VERSION-GATE|PASS|Version=$ExpectedVersion|Release=$ExpectedRelease";exit 0}

  Write-Host "DESKTOP-ENVIRONMENT-GATE|INSTALL|RequiredVersion=$ExpectedVersion|Source=MicrosoftArchive"
  $archiveUrl='https://learn.microsoft.com/en-us/power-bi/fundamentals/desktop-latest-update-archive'
  $archive=Invoke-WebRequest -Uri $archiveUrl -UseBasicParsing
  $archiveHtml=$archive.Content
  # Validate the historical release using the archive heading, but do not require the
  # archive page to expose the binary URL itself.
  if($archiveHtml -notmatch [regex]::Escape("July 2026 update (version $ExpectedVersion)")){throw "Microsoft archive does not identify July 2026 version $ExpectedVersion."}

  # Microsoft Learn may expose the historical installer through a redirect/link form.
  # Follow only links whose final host is Microsoft's download host and whose filename
  # is the Desktop x64 installer. Never substitute a third-party mirror.
  $urls=@()
  $links=@($archive.Links|Where-Object {$_.href -and $_.href -match 'download\.microsoft\.com' -and $_.href -match 'PBIDesktopSetup.*\.exe'}|Select-Object -ExpandProperty href)
  $urls += $links
  if($urls.Count -eq 0){
    $urls += [regex]::Matches($archiveHtml,'https://download\.microsoft\.com/[^\"''<>\s]+PBIDesktopSetup[^\"''<>\s]*\.exe')|ForEach-Object Value
  }
  $urls=$urls|Sort-Object -Unique
  if($urls.Count -eq 0){
    # The Download Center is used only as a Microsoft-owned resolver. Do not reject it
    # merely because the current page omits the historical version text.
    $dc='https://www.microsoft.com/en-us/download/details.aspx?id=58494'
    $dc=Invoke-WebRequest -Uri $dc -UseBasicParsing
    $urls += [regex]::Matches($dc.Content,'https://download\.microsoft\.com/[^\"''<>\s]+PBIDesktopSetup[^\"''<>\s]*\.exe')|ForEach-Object Value
    $urls=$urls|Sort-Object -Unique
  }
  if($urls.Count -eq 0){throw 'No Microsoft-hosted Power BI Desktop installer URL could be resolved from the Microsoft archive/Download Center.'}

  $installer=Join-Path $DiagnosticsRoot 'PBIDesktopSetup_x64.exe'
  $state.Installer=$urls[0]
  Invoke-WebRequest -Uri $urls[0] -OutFile $installer -UseBasicParsing
  $sig=Get-AuthenticodeSignature $installer
  $state.SignatureStatus=[string]$sig.Status;$state.Signer=if($sig.SignerCertificate){$sig.SignerCertificate.Subject}else{$null}
  if($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft'){throw "Installer Authenticode validation failed: Status=$($sig.Status); Signer=$($state.Signer)"}
  $iv=(Get-Item $installer).VersionInfo.ProductVersion;$state.InstallerVersion=$iv
  if($iv -ne $ExpectedVersion){throw "Downloaded installer ProductVersion=$iv; expected $ExpectedVersion."}
  $p=Start-Process -FilePath $installer -ArgumentList '/quiet','/norestart','ACCEPT_EULA=1',"/log=$log" -PassThru -Wait -NoNewWindow
  $state.InstallerExitCode=$p.ExitCode
  if($p.ExitCode -notin @(0,3010,1641)){throw "Installer exit code $($p.ExitCode)."}

  $desktop=@(Get-DesktopCandidates)|Where-Object ProductVersion -eq $ExpectedVersion|Select-Object -First 1
  if(-not $desktop){throw "Exact $ExpectedVersion was not detected after installation."}
  $state.Source='MicrosoftArchive';$state.Path=$desktop.Path;$state.ProductVersion=$desktop.ProductVersion;Save-Diagnostic ([pscustomobject]$state)
  Write-Host "DESKTOP-ENVIRONMENT-GATE|PASS|Source=MicrosoftArchive|ProductVersion=$($desktop.ProductVersion)|Path=$($desktop.Path)";Write-Host "DESKTOP-VERSION-GATE|PASS|Version=$ExpectedVersion|Release=$ExpectedRelease"
}catch{
  $state.Error=$_.Exception.Message;Save-Diagnostic ([pscustomobject]$state);Write-Host "DESKTOP-ENVIRONMENT-GATE|FAIL|RequiredVersion=$ExpectedVersion|Release=$ExpectedRelease|Diagnostics=$diag";throw
}