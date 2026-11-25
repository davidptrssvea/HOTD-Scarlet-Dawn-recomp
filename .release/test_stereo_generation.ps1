param([string]$GamePak)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scarlet-settings.ps1')
function Assert($value,[string]$message){if(!$value){throw $message}}
function Hash([byte[]]$bytes){$sha=[Security.Cryptography.SHA256]::Create();try{[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','')}finally{$sha.Dispose()}}
function Put([string]$path,[byte[]]$bytes){[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path));[IO.File]::WriteAllBytes($path,$bytes)}
function Text([string]$path,[string]$text){Put $path ([Text.Encoding]::UTF8.GetBytes($text))}
function Matches([string]$path,[string]$hash){[IO.File]::Exists($path) -and (Get-ScarletSHA256 $path) -eq $hash}
$base=Join-Path ([IO.Path]::GetTempPath()) ('Scarlet-generation-'+[guid]::NewGuid().ToString('N'))
if ($GamePak) { $base=Join-Path ([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($GamePak))) ('HOTDSD-stereo-generation-QA/check-'+[guid]::NewGuid().ToString('N')) }
$env:LOCALAPPDATA=Join-Path $base 'local-appdata'
$acf='Game/Hodzero/Content/Hodzero_V1/ADX/NewProject.acf'
$main='Game/Hodzero/Content/Paks/Hodzero-WindowsNoEditor.pak'
$patch='Game/Hodzero/Content/Paks/'+$ScarletStereoName
if ($GamePak) {
    # Optional private check; real game resources stay outside the repository/release.
    $recipe=Get-ScarletStereoRecipe
    $expected=New-ScarletStereoResources $GamePak
    $original=$expected['NewProject.original.acf']
    $sourceHash=$null
    $sourceStamp=(Get-Item -LiteralPath $GamePak).LastWriteTimeUtc.Ticks
} else {
    # Small synthetic zlib exports; no game assets are used in CI.
    $ini="OutputsLogAtom=False`r`nSoundRendererType=5`r`n+AsrRackConfig=(SoundRendererType=9)`r`nHardware2=synthetic device`r`nHardware3=synthetic device`r`nWASAPI_BitsPerSample=0`r`nWASAPI_SamplingRate=0`r`nWASAPI_NumChannels=0`r`n"
    $fixed="OutputsLogAtom=True`r`nSoundRendererType=1`r`n+AsrRackConfig=(SoundRendererType=1)`r`nHardware2=`r`nHardware3=`r`nWASAPI_BitsPerSample=16`r`nWASAPI_SamplingRate=48000`r`nWASAPI_NumChannels=2`r`n"
    $stereo=[byte[]](10,20,30,40,50,60,70,80)
    $original=[byte[]]$stereo.Clone();$original[2]=99
    [byte[]]$uexp=[byte[]](1,2,3,4)+$stereo+[byte[]](5,6,7,8)
    $modified=[byte[]]$uexp.Clone();$modified[7]=88
    $paths=@('Hodzero/Config/DefaultEngine.ini','Hodzero/Content/HodZero_v1/ADX/NewProject.uasset','Hodzero/Content/HodZero_v1/ADX/NewProject.uexp')
    $data=@([Text.Encoding]::UTF8.GetBytes($ini),[Text.Encoding]::UTF8.GetBytes('synthetic asset'),$uexp)
    $writer=[IO.BinaryWriter]::new([IO.MemoryStream]::new())
    $exports=@()
    foreach($i in 0..2){
        $stream=[IO.MemoryStream]::new()
        $deflate=[IO.Compression.DeflateStream]::new($stream,[IO.Compression.CompressionMode]::Compress,$true)
        $deflate.Write($data[$i],0,$data[$i].Length);$deflate.Dispose()
        [byte[]]$compressed=[byte[]](0x78,0x9c)+$stream.ToArray()+[byte[]](0,0,0,0)
        $exports+=@{path=$paths[$i];length=$data[$i].Length;chunks=@(,@($writer.BaseStream.Position,$compressed.Length));sha256=(Hash $data[$i])}
        $writer.Write($compressed);$stream.Dispose()
    }
    $bytes=$writer.BaseStream.ToArray();$writer.Dispose()
    $GamePak=Join-Path $base 'synthetic-main.pak';Put $GamePak $bytes
    $wanted=[ordered]@{};$wanted[$paths[0]]=[Text.Encoding]::UTF8.GetBytes($fixed);$wanted[$paths[1]]=$data[1];$wanted[$paths[2]]=$modified
    $expected=@{'NewProject.original.acf'=$original;'NewProject.stereo.acf'=$stereo;$ScarletStereoName=(New-ScarletAudioPak $wanted)}
    $recipe=[pscustomobject]@{PakSize=$bytes.Length;Exports=$exports;AcfOffset=4;AcfLength=$stereo.Length;StereoAcfSHA256=(Hash $stereo);OriginalAcfSHA256=(Hash $original);OriginalAcfEdits=@(,@(2,99));EmbeddedEdits=@(,@(7,88));EmbeddedSHA256=(Hash $modified);IniSHA256=(Hash $wanted[$paths[0]]);OutputSHA256=(Hash $expected[$ScarletStereoName])}
    $ScarletStereoHash=$recipe.OutputSHA256;$ScarletStereoAcf=$recipe.StereoAcfSHA256;$ScarletOriginalAcf=$recipe.OriginalAcfSHA256
    $sourceHash=Get-ScarletSHA256 $GamePak
}
$script:ScarletStereoRecipe=$recipe
function LinkGame([string]$name){
    $r=Join-Path $base $name
    Put (Join-Path $r $acf) $original
    $to=Join-Path $r $main;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to))
    New-Item -ItemType HardLink -Path $to -Target $GamePak | Out-Null
    $r
}
function CheckCache([string]$r){foreach($name in $expected.Keys){Assert (Matches (Join-Path $r ('Local/Audio/'+$name)) (Hash $expected[$name])) ("Incorrect generated "+$name)}}
$r=LinkGame 'clean'
Assert (![IO.Directory]::Exists((Join-Path $r 'Local/Audio'))) 'Fixture unexpectedly has patched audio'
Complete-ScarletStereoFiles $r;CheckCache $r
Sync-ScarletStereo $r $true
Assert ((Matches (Join-Path $r $acf) $ScarletStereoAcf) -and (Matches (Join-Path $r $patch) $ScarletStereoHash)) 'Clean data did not activate stereo'
$times=@{};foreach($p in Get-ChildItem -LiteralPath (Join-Path $r 'Local/Audio') -File){$times[$p.FullName]=$p.LastWriteTimeUtc.Ticks}
Complete-ScarletStereoFiles $r
foreach($p in Get-ChildItem -LiteralPath (Join-Path $r 'Local/Audio') -File){Assert ($times[$p.FullName] -eq $p.LastWriteTimeUtc.Ticks) 'Valid cache was rewritten'}
Sync-ScarletStereo $r $false
Assert ((Matches (Join-Path $r $acf) $ScarletOriginalAcf) -and ![IO.File]::Exists((Join-Path $r $patch))) 'Original restore failed'
Text (Join-Path $r 'Local/Audio/NewProject.stereo.acf') 'damaged'
Complete-ScarletStereoFiles $r;CheckCache $r
Assert ([IO.File]::ReadAllText((Join-Path $r 'Local/Audio/NewProject.stereo.acf.previous')) -eq 'damaged') 'Cache repair lost backup'
$r=LinkGame 'no-loose-backup';Put (Join-Path $r $acf) $expected['NewProject.stereo.acf']
Sync-ScarletStereo $r $false;CheckCache $r
Assert (Matches (Join-Path $r $acf) $ScarletOriginalAcf) 'Original ACF not derived from main PAK'
# Verify migration and offline compatibility using a synthetic legacy PAK.
$legacy=[Text.Encoding]::UTF8.GetBytes('synthetic legacy patch')
$ScarletLegacyStereoHash=Hash $legacy
$r=LinkGame 'legacy'
Put (Join-Path $r $patch) $legacy
Put (Join-Path $r $acf) $expected['NewProject.stereo.acf']
Sync-ScarletStereo $r $true;CheckCache $r
Assert (Matches (Join-Path $r $patch) $ScarletStereoHash) 'Legacy patch not migrated'
Assert (Matches (Join-Path $r ($patch+'.previous')) $ScarletLegacyStereoHash) 'Migration lost legacy backup'
$r=Join-Path $base 'legacy-offline'
Put (Join-Path $r $patch) $legacy
Put (Join-Path $r $acf) $original
Put (Join-Path $r 'Local/Audio/NewProject.stereo.acf') $expected['NewProject.stereo.acf']
Sync-ScarletStereo $r $true
Assert (Matches (Join-Path $r $patch) $ScarletLegacyStereoHash) 'Offline legacy installation broken'
$r=LinkGame 'unknown-active-pak';Text (Join-Path $r $patch) 'unrecognized PAK'
$failed=$false;try{Sync-ScarletStereo $r $true}catch{$failed=$true}
Assert ($failed -and [IO.File]::ReadAllText((Join-Path $r $patch)) -eq 'unrecognized PAK' -and (Matches (Join-Path $r $acf) $ScarletOriginalAcf)) 'Unknown active PAK overwritten'
$r=Join-Path $base 'corrupt-source';Put (Join-Path $r $acf) $original
$corrupt=Join-Path $r $main
Text $corrupt 'invalid compressed source'
$badRecipe=$recipe | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$badRecipe.PakSize=(Get-Item -LiteralPath $corrupt).Length
$failed=$false;try{[void](New-ScarletStereoResources $corrupt $badRecipe)}catch{$failed=$true}
Assert $failed 'Invalid compressed resource accepted'
Sync-ScarletStereo $r $false
$failed=$false;try{Sync-ScarletStereo $r $true}catch{$failed=$true}
Assert ($failed -and (Matches (Join-Path $r $acf) $ScarletOriginalAcf) -and ![IO.File]::Exists((Join-Path $r $patch))) 'Failed generation modified active audio'
if ($sourceHash) {
    Assert ((Get-ScarletSHA256 $GamePak) -eq $sourceHash) 'Source PAK modified'
    # Real Setup with synthetic data, and only process preparation stubbed.
    $dump=Join-Path $base 'dump/WindowsNoEditor'
    Put (Join-Path $dump 'Hodzero/Content/Hodzero_V1/ADX/NewProject.acf') $original
    Put (Join-Path $dump 'Hodzero/Content/Paks/Hodzero-WindowsNoEditor.pak') ([IO.File]::ReadAllBytes($GamePak))
    Text (Join-Path $dump 'Hodzero/Binaries/Win64/Hodzero-Win64-Shipping.exe') 'synthetic exe'
    [void][IO.Directory]::CreateDirectory((Join-Path $dump 'Engine/Binaries'))
    $package=Join-Path $base 'builder';[void][IO.Directory]::CreateDirectory($package)
    $manifest=Get-Content -LiteralPath (Join-Path $repo 'package-manifest.json') -Raw | ConvertFrom-Json
    foreach($name in @($manifest.files.path)+@('package-manifest.json','setup.ps1','Setup.cmd')){Copy-Item -LiteralPath (Join-Path $repo $name) -Destination (Join-Path $package $name)}
    $suffix="'"+($recipe | ConvertTo-Json -Depth 10 -Compress).Replace("'","''")+"'"
    $overrides='$script:ScarletStereoRecipe='+$suffix+' | ConvertFrom-Json'+[Environment]::NewLine
    $overrides+="`$ScarletStereoHash='$ScarletStereoHash';`$ScarletStereoAcf='$ScarletStereoAcf';`$ScarletOriginalAcf='$ScarletOriginalAcf'`nfunction New-ScarletStartInfo([string]`$Root,`$Settings){Sync-ScarletStereo `$Root `$Settings.StereoFix}`n"
    [IO.File]::AppendAllText((Join-Path $package 'scarlet-settings.ps1'),("`n"+$overrides))
    $specPath=Join-Path $package 'scarlet-aim-patch.json';$spec=Get-Content -LiteralPath $specPath -Raw | ConvertFrom-Json
    $spec.SourceSHA256=Get-ScarletSHA256 (Join-Path $dump 'Hodzero/Binaries/Win64/Hodzero-Win64-Shipping.exe')
    [IO.File]::WriteAllText($specPath,($spec | ConvertTo-Json -Depth 20))
    foreach($row in $manifest.files){$row.sha256=Get-ScarletSHA256 (Join-Path $package $row.path)}
    [IO.File]::WriteAllText((Join-Path $package 'package-manifest.json'),($manifest | ConvertTo-Json -Depth 10))
    $ps=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell/v1.0/powershell.exe'
    $r=Join-Path $base 'fresh-setup'
    $output=& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $package 'setup.ps1') -InstallDir $r -DumpPath $dump 2>&1
    Assert (!$LASTEXITCODE) ($output -join "`n");CheckCache $r
    Assert (Matches (Join-Path $r $acf) $ScarletStereoAcf) 'Clean Setup did not enable generated stereo'
    $settings=Get-ScarletSettings $r;$settings.StereoFix=$false;Save-ScarletSettings $r $settings
    $output=& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $package 'setup.ps1') -InstallDir $r 2>&1
    Assert (!$LASTEXITCODE) ($output -join "`n")
    Assert (!(Get-ScarletSettings $r).StereoFix -and (Matches (Join-Path $r $acf) $ScarletOriginalAcf)) 'Setup ignored saved original-audio preference'
} else {
    Assert ((Get-Item -LiteralPath $GamePak).LastWriteTimeUtc.Ticks -eq $sourceStamp) 'Real source PAK modified'
    Assert ((Hash (New-ScarletCreditSoundPak $GamePak)) -eq '9002CEFB02CFA1D61771CA275C5F43FF25095622513714F98BF87EECA221E33C') 'Credit-sound patch regressed'
}
"PASS local stereo generation, clean cache, switching, original recovery, validation, repair and Setup ($base)"
