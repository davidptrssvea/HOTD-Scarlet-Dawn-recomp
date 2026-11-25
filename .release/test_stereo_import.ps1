param([string]$VerifiedAudio)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scarlet-settings.ps1')
function Assert($value,[string]$message){if(!$value){throw $message}}
function Put([string]$path,[byte[]]$bytes){[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path));[IO.File]::WriteAllBytes($path,$bytes)}
function Text([string]$path,[string]$value){Put $path ([Text.Encoding]::UTF8.GetBytes($value))}
function Matches([string]$path,[string]$hash){[IO.File]::Exists($path) -and (Get-ScarletSHA256 $path) -eq $hash}
function Hash([byte[]]$bytes){$sha=[Security.Cryptography.SHA256]::Create();try{[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','')}finally{$sha.Dispose()}}
if($VerifiedAudio){
 $original=[IO.File]::ReadAllBytes((Join-Path $VerifiedAudio 'NewProject.original.acf'))
 $stereo=[IO.File]::ReadAllBytes((Join-Path $VerifiedAudio 'NewProject.stereo.acf'))
 $pak=[IO.File]::ReadAllBytes((Join-Path $VerifiedAudio $ScarletStereoName))
 Assert ((Hash $original) -eq $ScarletOriginalAcf -and (Hash $stereo) -eq $ScarletStereoAcf -and (Hash $pak) -in $ScarletStereoHash,$ScarletLegacyStereoHash) 'The supplied real audio fixture is unsupported'
 # This fixture checks import independently of generation/migration.
 $ScarletStereoHash=Hash $pak
 $ScarletLegacyStereoHash='0000000000000000000000000000000000000000000000000000000000000000'
}else{
 # Synthetic, non-game bytes exercise the same verification/IO paths in CI.
 $original=[Text.Encoding]::UTF8.GetBytes('synthetic original ACF')
 $stereo=[Text.Encoding]::UTF8.GetBytes('synthetic stereo ACF')
 $pak=[Text.Encoding]::UTF8.GetBytes('synthetic stereo PAK')
 $ScarletOriginalAcf=Hash $original;$ScarletStereoAcf=Hash $stereo;$ScarletStereoHash=Hash $pak
}
$base=Join-Path ([IO.Path]::GetTempPath()) ('Scarlet-stereo-'+[guid]::NewGuid().ToString('N'))
$env:LOCALAPPDATA=Join-Path $base 'local-appdata'
$acf='Game/Hodzero/Content/Hodzero_V1/ADX/NewProject.acf';$patch='Game/Hodzero/Content/Paks/'+$ScarletStereoName
function App([string]$name){$r=Join-Path $base $name;Put (Join-Path $r $acf) $original;Text (Join-Path $r 'Game/Hodzero/Content/Paks/unrelated.pak') 'leave me alone';$r}
function CheckCache([string]$r){foreach($pair in @(@('NewProject.original.acf',$ScarletOriginalAcf),@('NewProject.stereo.acf',$ScarletStereoAcf),@($ScarletStereoName,$ScarletStereoHash))){Assert (Matches (Join-Path $r ('Local/Audio/'+$pair[0])) $pair[1]) ('Missing or incorrect cache: '+$pair[0])}}
$dumpOuter=Join-Path $base ('own dump '+[char]0xe5);$dump=Join-Path $dumpOuter 'WindowsNoEditor'
Put (Join-Path $dump 'Hodzero/Content/Hodzero_V1/ADX/NewProject.acf') $original
Put (Join-Path $dump 'Hodzero/Content/Hodzero_V1/ADX/NewProject.stereo.acf') $stereo
Put (Join-Path $dump ('Hodzero/Content/Paks/'+$ScarletStereoName)) $pak
Text (Join-Path $dump 'Hodzero/Binaries/Win64/Hodzero-Win64-Shipping.exe') 'synthetic game executable'
Text (Join-Path $dump 'Hodzero/Content/Paks/Hodzero-WindowsNoEditor.pak') 'synthetic main pack'
[void][IO.Directory]::CreateDirectory((Join-Path $dump 'Engine/Binaries'))
$before=@{};foreach($p in Get-ChildItem -LiteralPath $dump -File -Recurse){$before[$p.FullName]=Get-ScarletSHA256 $p.FullName}
$r=App 'explicit';Import-ScarletStereoFiles $r @($dumpOuter);CheckCache $r
$times=@{};foreach($p in Get-ChildItem -LiteralPath (Join-Path $r 'Local/Audio') -File){$times[$p.FullName]=$p.LastWriteTimeUtc.Ticks}
Import-ScarletStereoFiles $r @($dumpOuter)
foreach($p in Get-ChildItem -LiteralPath (Join-Path $r 'Local/Audio') -File){Assert ($times[$p.FullName] -eq $p.LastWriteTimeUtc.Ticks) 'Valid cached audio was rewritten'}
Sync-ScarletStereo $r $true;Assert ((Matches (Join-Path $r $acf) $ScarletStereoAcf) -and (Matches (Join-Path $r $patch) $ScarletStereoHash)) 'Stereo was not applied'
Sync-ScarletStereo $r $false;Assert ((Matches (Join-Path $r $acf) $ScarletOriginalAcf) -and ![IO.File]::Exists((Join-Path $r $patch))) 'Original audio was not restored'
Assert ([IO.File]::ReadAllText((Join-Path $r 'Game/Hodzero/Content/Paks/unrelated.pak')) -eq 'leave me alone') 'Unrelated PAK changed'

$r=App 'automatic-game'
Put (Join-Path $r 'Game/Hodzero/Content/Hodzero_V1/ADX/NewProject.acf.original') $original
Put (Join-Path $r 'Game/Hodzero/Content/Hodzero_V1/ADX/NewProject.acf') $stereo
Put (Join-Path $r $patch) $pak
# No explicit import: the actual launch synchronization discovers the installed fix.
Sync-ScarletStereo $r $true;CheckCache $r
Sync-ScarletStereo $r $false;Assert (Matches (Join-Path $r $acf) $ScarletOriginalAcf) 'Game-folder original backup not restored'
Sync-ScarletStereo $r $true;Assert (Matches (Join-Path $r $acf) $ScarletStereoAcf) 'Cached stereo not reusable after removal from Paks'

$r=App 'remembered';Set-ScarletFile (Join-Path $r 'Local/dump-path.txt') $dumpOuter
Sync-ScarletStereo $r $true;CheckCache $r
# A stale dump path must not stop cached audio from working.
Set-ScarletFile (Join-Path $r 'Local/dump-path.txt') (Join-Path $base 'no-longer-connected')
Sync-ScarletStereo $r $false;Sync-ScarletStereo $r $true

$r=App 'invalid';Text (Join-Path $r 'Game/Hodzero/Content/Hodzero_V1/ADX/NewProject.stereo.acf') 'not verified'
Put (Join-Path $r $patch) $pak
$failed=$false;try{Sync-ScarletStereo $r $true}catch{$failed=$true}
Assert ($failed -and (Matches (Join-Path $r $acf) $ScarletOriginalAcf)) 'Unverified ACF accepted or active audio changed on failure'
Assert (![IO.File]::Exists((Join-Path $r 'Local/Audio/NewProject.stereo.acf'))) 'Unverified ACF imported'

$r=App 'invalid-game-pak';Text (Join-Path $r $patch) 'unknown patch';Set-ScarletFile (Join-Path $r 'Local/dump-path.txt') $dump
$failed=$false;try{Sync-ScarletStereo $r $true}catch{$failed=$true}
Assert ($failed -and (Matches (Join-Path $r $acf) $ScarletOriginalAcf) -and [IO.File]::ReadAllText((Join-Path $r $patch)) -eq 'unknown patch') 'Unknown installed PAK was overwritten'

$r=App 'unknown-current';Text (Join-Path $r $acf) 'unknown active ACF';Set-ScarletFile (Join-Path $r 'Local/dump-path.txt') $dump
$failed=$false;try{Sync-ScarletStereo $r $true}catch{$failed=$true}
Assert ($failed -and [IO.File]::ReadAllText((Join-Path $r $acf)) -eq 'unknown active ACF') 'Unknown active audio configuration was overwritten'

$r=App 'repair-cache';Text (Join-Path $r 'Local/Audio/NewProject.stereo.acf') 'damaged cached file'
Import-ScarletStereoFiles $r @($dump);CheckCache $r
Assert ([IO.File]::ReadAllText((Join-Path $r 'Local/Audio/NewProject.stereo.acf.previous')) -eq 'damaged cached file') 'Damaged cache backup was not kept'

# Run the real Setup against a small isolated fake game; no game binary is run.
# Only expected hashes and final game-process preparation are fixture-specific.
$package=Join-Path $base 'builder';[void][IO.Directory]::CreateDirectory($package)
$manifest=Get-Content -LiteralPath (Join-Path $repo 'package-manifest.json') -Raw | ConvertFrom-Json
foreach($name in @($manifest.files.path)+@('package-manifest.json','setup.ps1','Setup.cmd')){Copy-Item -LiteralPath (Join-Path $repo $name) -Destination (Join-Path $package $name)}
$settings=Join-Path $package 'scarlet-settings.ps1'
[IO.File]::AppendAllText($settings,"`n`$ScarletOriginalAcf='$ScarletOriginalAcf'`n`$ScarletStereoAcf='$ScarletStereoAcf'`n`$ScarletStereoHash='$ScarletStereoHash'`n`$ScarletLegacyStereoHash='$ScarletLegacyStereoHash'`nfunction New-ScarletStartInfo([string]`$Root,`$Settings){Sync-ScarletStereo `$Root `$Settings.StereoFix}`n")
$specPath=Join-Path $package 'scarlet-aim-patch.json';$spec=Get-Content -LiteralPath $specPath -Raw | ConvertFrom-Json
$spec.SourceSHA256=Get-ScarletSHA256 (Join-Path $dump 'Hodzero/Binaries/Win64/Hodzero-Win64-Shipping.exe')
[IO.File]::WriteAllText($specPath,($spec | ConvertTo-Json -Depth 20))
foreach($row in $manifest.files){$row.sha256=Get-ScarletSHA256 (Join-Path $package $row.path)}
[IO.File]::WriteAllText((Join-Path $package 'package-manifest.json'),($manifest | ConvertTo-Json -Depth 10))
$ps=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell/v1.0/powershell.exe'
function Setup([string]$r,[string]$source){
 $params=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $package 'setup.ps1'),'-InstallDir',$r)
 if($source){$params+=@('-DumpPath',$source)}
 $output=& $ps @params 2>&1
 if($LASTEXITCODE){throw ($output -join "`n")}
}
$r=Join-Path $base 'fresh-install';Setup $r $dumpOuter;CheckCache $r
Assert ([IO.File]::ReadAllText((Join-Path $r 'Local/dump-path.txt')).Trim() -eq $dump) 'Fresh Setup did not remember the resolved dump'
Assert (Matches (Join-Path $r $acf) $ScarletStereoAcf) 'Fresh Setup did not activate a complete verified stereo pair'

$partial=Join-Path $base 'partial-dump'
foreach($p in Get-ChildItem -LiteralPath $dump -File -Recurse){$relative=$p.FullName.Substring($dump.Length+1);if($p.Name -eq 'NewProject.stereo.acf'){continue};Put (Join-Path $partial $relative) ([IO.File]::ReadAllBytes($p.FullName))}
[void][IO.Directory]::CreateDirectory((Join-Path $partial 'Engine/Binaries'))
$r=Join-Path $base 'partial-fix-install';Setup $r $partial
Assert (Matches (Join-Path $r $acf) $ScarletOriginalAcf) 'An incomplete stereo pair broke a fresh original-audio install'

$bad=Join-Path $base 'mismatched-dump'
foreach($p in Get-ChildItem -LiteralPath $dump -File -Recurse){Put (Join-Path $bad $p.FullName.Substring($dump.Length+1)) ([IO.File]::ReadAllBytes($p.FullName))}
Put (Join-Path $bad 'Hodzero/Content/Hodzero_V1/ADX/NewProject.acf') $stereo
Text (Join-Path $bad ('Hodzero/Content/Paks/'+$ScarletStereoName)) 'unverified stereo PAK'
[void][IO.Directory]::CreateDirectory((Join-Path $bad 'Engine/Binaries'))
$r=Join-Path $base 'mismatched-install';$failed=$false;try{Setup $r $bad}catch{$failed=$true}
Assert ($failed -and ![IO.Directory]::Exists((Join-Path $r 'Game'))) 'Fresh Setup installed stereo ACF without the verified matching PAK'

$r=App 'existing-install';Text (Join-Path $r 'Game/Hodzero/Binaries/Win64/Hodzero-Win64-Shipping.exe') 'synthetic game executable';Text (Join-Path $r 'Game/Hodzero/Content/Paks/Hodzero-WindowsNoEditor.pak') 'synthetic main pack'
Setup $r $dumpOuter;CheckCache $r
Assert ([IO.File]::ReadAllText((Join-Path $r 'Local/dump-path.txt')).Trim() -eq $dump) 'Existing Setup ignored the selected dump'

$r=App 'existing-patched-game';Text (Join-Path $r 'Game/Hodzero/Binaries/Win64/Hodzero-Win64-Shipping.exe') 'synthetic game executable';Text (Join-Path $r 'Game/Hodzero/Content/Paks/Hodzero-WindowsNoEditor.pak') 'synthetic main pack'
Put (Join-Path $r 'Game/Hodzero/Content/Hodzero_V1/ADX/NewProject.acf') $stereo
Put (Join-Path $r 'Game/Hodzero/Content/Hodzero_V1/ADX/NewProject.acf.original') $original
Put (Join-Path $r $patch) $pak
Setup $r $null;CheckCache $r
foreach($path in $before.Keys){Assert ((Get-ScarletSHA256 $path) -eq $before[$path]) 'Source dump was modified'}
"PASS automatic game/dump import, original/stereo switching, cache repair, invalid-file rejection, fresh/existing Setup, remembered Unicode source and untouched dump ($base)"
