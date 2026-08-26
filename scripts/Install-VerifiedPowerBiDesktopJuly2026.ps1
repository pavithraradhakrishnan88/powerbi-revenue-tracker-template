param(
  [Parameter(Mandatory=$true)][string]$ExpectedVersion,
  [Parameter(Mandatory=$true)][string]$ExpectedRelease,
  [Parameter(Mandatory=$true)][string]$DiagnosticsRoot
)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Path $DiagnosticsRoot -Force | Out-Null

function Get-DesktopCandidates {
  $paths=@(
    'C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe',
    'C:\Program Files\Microsoft Power BI Desktop RS\bin\PBIDesktop.exe',
    'C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktopStore.exe'
  )
  $paths += @(Get-ChildItem 'C:\Program Files' -Filter 'PBIDesktop.exe' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
  foreach($p in ($paths|Sort-Object -Unique)) {
    if(Test-Path $p -PathType Leaf) {
      $i=Get-Item $p
      [pscustomobject]@{Path=$p;ProductVersion=$i.VersionInfo.ProductVersion;FileVersion=$i.VersionInfo.FileVersion}
    }
  }
}

$candidates=@(Get-DesktopCandidates)
$desktop=$candidates|Where-Object ProductVersion -eq $ExpectedVersion|Select-Object -First 1
if($desktop){
  $desktop|ConvertTo-Json|Set-Content (Join-Path $DiagnosticsRoot 'desktop-environment.json') -Encoding utf8
  Write-Host "DESKTOP-ENVIRONMENT-GATE|PASS|Source=Installed|ProductVersion=$($desktop.ProductVersion)|Path=$($desktop.Path)"
  Write-Host "DESKTOP-VERSION-GATE|PASS|Version=$ExpectedVersion|Release=$ExpectedRelease"
  exit 0
}

$archiveUrl='https://learn.microsoft.com/en-us/power-bi/fundamentals/desktop-latest-update-archive'
$downloadCenter='https://www.microsoft.com/en-us/download/details.aspx?id=58494'
Write-Host "DESKTOP-ENVIRONMENT-GATE|INSTALL|RequiredVersion=$ExpectedVersion|Source=MicrosoftArchive"

$archive=Invoke-WebRequest -Uri $archiveUrl -UseBasicParsing
$archiveHtml=$archive.Content
if($archiveHtml -notmatch [regex]::Escape("July 2026 update (version $ExpectedVersion)")) {
  throw "DESKTOP-ENVIRONMENT-GATE failed: Microsoft July 2026 archive does not identify $ExpectedVersion."
}

# Resolve the archived July link from Microsoft Learn first. The archive is the authoritative
# historical-version index; only Microsoft-hosted download.microsoft.com URLs are accepted.
$urls=@()
$urls += [regex]::Matches($archiveHtml,'https://download\.microsoft\.com/[^\"''<>\s]+PBIDesktopSetup_x64\.exe') | ForEach-Object Value
$urls += [regex]::Matches($archiveHtml,'https://download\.microsoft\.com/[^\"''<>\s]+PBIDesktopSetup\.exe') | ForEach-Object Value
$urls=$urls|Sort-Object -Unique

# Some Microsoft Learn renderings expose the link as an HTML href with a relative/redirect form.
if($urls.Count -eq 0){
  $page=Invoke-WebRequest -Uri $downloadCenter -UseBasicParsing
  $html=$page.Content
  if($html -notmatch [regex]::Escape($ExpectedVersion)) {
    $text=($html -replace '<[^>]+>',' ' -replace '\s+',' ')
    if($text -notmatch [regex]::Escape($ExpectedVersion)){throw "DESKTOP-ENVIRONMENT-GATE failed: Microsoft Download Center did not expose version $ExpectedVersion."}
  }
  $urls += [regex]::Matches($html,'https://download\.microsoft\.com/[^\"''<>\s]+PBIDesktopSetup_x64\.exe') | ForEach-Object Value
  $urls=$urls|Sort-Object -Unique
}
if($urls.Count -eq 0){throw 'DESKTOP-ENVIRONMENT-GATE failed: no Microsoft-hosted archived PBIDesktopSetup_x64.exe URL was exposed.'}

$installer=Join-Path $DiagnosticsRoot 'PBIDesktopSetup_x64.exe'
Invoke-WebRequest -Uri $urls[0] -OutFile $installer -UseBasicParsing
$sig=Get-AuthenticodeSignature $installer
if($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft'){
  throw "DESKTOP-ENVIRONMENT-GATE failed: installer is not validly Microsoft-signed. Status=$($sig.Status); Subject=$($sig.SignerCertificate.Subject)"
}
$installerVersion=(Get-Item $installer).VersionInfo.ProductVersion
if($installerVersion -ne $ExpectedVersion){throw "DESKTOP-ENVIRONMENT-GATE failed: installer ProductVersion=$installerVersion; expected $ExpectedVersion."}

$installLog=Join-Path $DiagnosticsRoot 'desktop-install.log'
$p=Start-Process -FilePath $installer -ArgumentList '/quiet','/norestart','ACCEPT_EULA=1',"/log=$installLog" -PassThru -Wait -NoNewWindow
if($p.ExitCode -notin @(0,3010,1641)){throw "DESKTOP-ENVIRONMENT-GATE failed: installer exit code $($p.ExitCode)."}

$candidates=@(Get-DesktopCandidates)
$desktop=$candidates|Where-Object ProductVersion -eq $ExpectedVersion|Select-Object -First 1
if(-not $desktop){
  $all=($candidates|ForEach-Object { "$($_.ProductVersion) @ $($_.Path)" }) -join '; '
  throw "DESKTOP-ENVIRONMENT-GATE failed: exact $ExpectedVersion was not detected after installation. Detected: $all"
}

$desktop|ConvertTo-Json|Set-Content (Join-Path $DiagnosticsRoot 'desktop-environment.json') -Encoding utf8
[pscustomobject]@{ExpectedVersion=$ExpectedVersion;ExpectedRelease=$ExpectedRelease;Installer=$installer;InstallerVersion=$installerVersion;SignatureStatus=$sig.Status;Signer=$sig.SignerCertificate.Subject;InstallerExitCode=$p.ExitCode;DesktopPath=$desktop.Path;ProductVersion=$desktop.ProductVersion}|ConvertTo-Json|Set-Content (Join-Path $DiagnosticsRoot 'desktop-install-result.json') -Encoding utf8
Write-Host "DESKTOP-ENVIRONMENT-GATE|PASS|Source=MicrosoftArchive|ProductVersion=$($desktop.ProductVersion)|Path=$($desktop.Path)"
Write-Host "DESKTOP-VERSION-GATE|PASS|Version=$ExpectedVersion|Release=$ExpectedRelease"