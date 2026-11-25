[CmdletBinding()]
param([string]$DumpPath, [string]$InstallDir)

$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'scarlet-settings.ps1')
. (Join-Path $PSScriptRoot 'scarlet-update.ps1')
if (!$InstallDir) { $InstallDir=Join-Path $PSScriptRoot 'ScarletDawn-PC' }
$InstallDir=[IO.Path]::GetFullPath($InstallDir).TrimEnd([IO.Path]::DirectorySeparatorChar)
$tag=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'scarlet-version.txt')).Trim()
$files=@(Confirm-ScarletProgramPackage $PSScriptRoot $tag)
$files=@($files | Where-Object { $_ -ne 'scarlet-version.txt' })+'scarlet-version.txt'
$exe='Hodzero/Binaries/Win64/Hodzero-Win64-Shipping.exe'
$pak='Hodzero/Content/Paks/Hodzero-WindowsNoEditor.pak'
$acf='Hodzero/Content/Hodzero_V1/ADX/NewProject.acf'
$game=Join-Path $InstallDir 'Game'
$local=Join-Path $InstallDir 'Local'
$installed=[IO.File]::Exists((Join-Path $game $exe))
$dump=$null
$expected=([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'scarlet-aim-patch.json')) | ConvertFrom-Json).SourceSHA256
if ($installed) {
    $versionFile=Join-Path $InstallDir 'scarlet-version.txt'
    if ([IO.File]::Exists($versionFile) -and
        (ConvertTo-HotdVersion ([IO.File]::ReadAllText($versionFile).Trim())) -gt (ConvertTo-HotdVersion $tag)) {
        throw 'This package is older than the installed version.'
    }
    if ((Get-ScarletSHA256 (Join-Path $game $exe)) -ne $expected -or ![IO.File]::Exists((Join-Path $game $pak))) {
        throw 'The existing game copy does not match the supported Scarlet Dawn export.'
    }
} else {
    if ([IO.Directory]::Exists($game)) { throw 'Install to a new folder or repair the existing Game folder first.' }
    if (!$DumpPath) {
        Add-Type -AssemblyName System.Windows.Forms
        $picker=[Windows.Forms.FolderBrowserDialog]::new()
        try {
            $picker.Description='Select your extracted Scarlet Dawn Export folder or WindowsNoEditor folder.'
            if ($picker.ShowDialog() -ne 'OK') { return }
            $DumpPath=$picker.SelectedPath
        } finally { $picker.Dispose() }
    }
    $dump=Resolve-ScarletDumpPath $DumpPath
    if (!$dump -or (Get-ScarletSHA256 (Join-Path $dump $exe)) -ne $expected) {
        throw 'Select an extracted Scarlet Dawn Export dump with the supported Windows executable.'
    }
    if (([IO.Path]::GetFullPath($InstallDir)+'\').StartsWith(([IO.Path]::GetFullPath($dump).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Choose an installation folder outside the extracted dump.'
    }
    $serial=Get-ScarletSHA256 (Join-Path $dump $acf)
    if ($serial -notin $ScarletOriginalAcf,$ScarletStereoAcf) { throw 'The dump contains an unsupported NewProject.acf.' }

}

function Copy-ScarletDirectory([string]$Source,[string]$Destination) {
    if (![IO.Directory]::Exists($Source)) { throw "Game data folder is missing: $Source" }
    & robocopy.exe $Source $Destination /E /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -gt 7) { throw "Could not copy game data: $Source (robocopy $LASTEXITCODE)" }
}

if ($installed -and $DumpPath) {
    $dump=Resolve-ScarletDumpPath $DumpPath
    if ((Get-ScarletSHA256 (Join-Path $dump $exe)) -ne $expected) {
        throw 'Select an extracted Scarlet Dawn Export dump with the supported Windows executable.'
    }
}
[void][IO.Directory]::CreateDirectory($local)
$lock=[IO.File]::Open((Join-Path $local 'Run.lock'),'OpenOrCreate','ReadWrite','None')
$work=Join-Path $InstallDir ('.scarlet-setup-'+[guid]::NewGuid().ToString('N'))
try {
    if (Test-ScarletGameRunning $InstallDir) { throw 'Close the running game before installing.' }
    [void][IO.Directory]::CreateDirectory($work)
    if (!$installed) {
        Complete-ScarletStereoFiles $InstallDir @($dump)
        if ($serial -eq $ScarletStereoAcf -and
            (![IO.File]::Exists((Join-Path $local ('Audio/'+$ScarletStereoName))) -or
             (Get-ScarletSHA256 (Join-Path $local ('Audio/'+$ScarletStereoName))) -notin $ScarletStereoHash,$ScarletLegacyStereoHash)) {
            throw 'The supplied stereo patch failed verification.'
        }
        $stagedGame=Join-Path $work 'Game'
        Write-Host 'Copying the local game files...'
        foreach ($folder in 'Engine/Binaries','Hodzero/Content/Hodzero_V1') {
            Copy-ScarletDirectory (Join-Path $dump $folder) (Join-Path $stagedGame $folder)
        }
        foreach ($file in $exe,$pak) {
            $to=Join-Path $stagedGame $file
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to))
            [IO.File]::Copy((Join-Path $dump $file),$to)
        }
        [IO.Directory]::Move($stagedGame,$game)
    }
    # Generate missing stereo resources for existing installations too.
    Complete-ScarletStereoFiles $InstallDir @($dump)
    if ($dump) { Set-ScarletFile (Join-Path $local 'dump-path.txt') $dump }
    $program=Join-Path $work 'program'
    [void][IO.Directory]::CreateDirectory($program)
    foreach ($file in $files) { [IO.File]::Copy((Join-Path $PSScriptRoot $file),(Join-Path $program $file)) }
    Install-HotdManagedFiles $program $InstallDir (Join-Path $work 'backup') $files
    $settings=Get-ScarletSettings $InstallDir
    [void](New-ScarletStartInfo $InstallDir $settings)
    try { Register-Hotd4Installation $InstallDir Scarlet }
    catch { Write-Warning 'The game was installed, but automatic library registration failed. Use Locate installed game in the Game Library.' }
    Write-Host "Installed $tag. Open $(Join-Path $InstallDir 'Play Scarlet Dawn.exe')."
} finally {
    $lock.Dispose()
}
