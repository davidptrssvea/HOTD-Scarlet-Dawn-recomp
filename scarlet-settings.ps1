$ScarletStereoName = 'Hodzero-CodexStereo_P.pak'
$ScarletStereoHash = '1D3FFBA7E20A81B5551FE8120C05ACE197E274A27A0A9F3F80439EF17FC001F9'
$ScarletStereoAcf = '44B012215BCCB0B56C1F10C088C72CCCEBF379E011205C6F3395438CA14CF64E'
$ScarletOriginalAcf = '67E5808A0B3742D2A351DD54FA4C0C673C54DF2E8D30BB0E6BA690FDE8AB1812'

function Get-ScarletPresets {
    [ordered]@{
        'Performance' = @{ Resolution='1280x720'; Scale=75; Quality=0; VSync=$false }
        'Balanced'    = @{ Resolution='1600x900'; Scale=85; Quality=1; VSync=$false }
        'Quality'     = @{ Resolution='1920x1080'; Scale=100; Quality=3; VSync=$false }
    }
}

function Get-ScarletAdvancedOptions {
    [ordered]@{
        FrameCap         = [ordered]@{'30'='30 FPS';'45'='45 FPS';'60'='60 FPS'}
        AntiAliasing     = [ordered]@{'-1'='Preset';'0'='Off';'2'='Low';'4'='High'}
        Shadows          = [ordered]@{'-1'='Preset';'0'='Off';'1'='Low';'2'='Medium';'3'='High'}
        TextureDetail    = [ordered]@{'-1'='Preset';'0'='Low';'1'='Medium';'2'='High';'3'='Epic'}
        TexturePool      = [ordered]@{'-1'='Preset';'512'='512 MB';'768'='768 MB';'1024'='1024 MB';'1536'='1536 MB';'2048'='2048 MB';'3072'='3072 MB';'4096'='4096 MB'}
        Effects          = [ordered]@{'-1'='Preset';'0'='Low';'1'='Medium';'2'='High';'3'='Epic'}
        Occlusion        = [ordered]@{'-1'='Preset';'0'='Off';'1'='Low';'3'='High'}
        Reflections      = [ordered]@{'-1'='Preset';'0'='Off';'1'='Low';'2'='Medium';'3'='High'}
        VolumetricFog    = [ordered]@{'-1'='Preset';'0'='Off';'1'='On'}
        Bloom            = [ordered]@{'-1'='Preset';'0'='Off';'3'='Low';'5'='High'}
        DepthOfField     = [ordered]@{'-1'='Preset';'0'='Off';'1'='Low';'2'='High'}
        MotionBlur       = [ordered]@{'0'='Off';'3'='On'}
    }
}

function Get-ScarletAdvancedDefaults {
    $defaults=@{}
    foreach ($key in (Get-ScarletAdvancedOptions).Keys) { $defaults[$key]=-1 }
    $defaults.FrameCap=60
    $defaults.MotionBlur=0
    $defaults
}

function Get-ScarletReticleStyles {
    [ordered]@{'Original'='Original';'Off'='Off';'Dot'='Dot';'Cross'='Cross';'Ring'='Ring';'RingDot'='Ring + dot';'OpenCross'='Open cross'}
}

function Get-ScarletReticleColors {
    [ordered]@{'White'='#FFFFFF';'Red'='#FF5050';'Green'='#74FF79';'Cyan'='#5DEAFF';'Amber'='#FFD65B'}
}

function Set-ScarletFile([string]$Path, [string]$Text) {
    Set-ScarletBytes $Path ([Text.Encoding]::UTF8.GetBytes($Text))
}

function Set-ScarletBytes([string]$Path, [byte[]]$Bytes) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    $next = "$Path.$([guid]::NewGuid().ToString('N')).new"
    try {
        [IO.File]::WriteAllBytes($next, $Bytes)
        if ([IO.File]::Exists($Path)) {
            [IO.File]::Replace($next, $Path, "$Path.previous")
        } else {
            [IO.File]::Move($next, $Path)
        }
    } finally {
        if ([IO.File]::Exists($next)) { [IO.File]::Delete($next) }
    }
}

function Get-ScarletSHA256([string]$Path) {
    $hash = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try { [BitConverter]::ToString($hash.ComputeHash($stream)).Replace('-','') }
    finally { $stream.Dispose(); $hash.Dispose() }
}

function Get-ScarletSettings([string]$Root) {
    $settings = @{ Resolution='1280x720'; Scale=75; Quality=0; Display='Windowed'; VSync=$false; StereoFix=[IO.File]::Exists((Join-Path $Root ('Local/Audio/'+$ScarletStereoName)))
        InputMode='Mouse'; Gun1='auto'; Gun2='disabled'; BorderWidth=50; OffscreenReload=$true
        SindenSwitchWeaponOnReload=$false; MuteCreditSounds=$false
        ReticleStyle='Original'; ReticleSize=2; ReticleColor='White'; GamepadSensitivity=100 }
    $defaults=Get-ScarletAdvancedDefaults
    foreach ($key in $defaults.Keys) { $settings[$key]=$defaults[$key] }
    $path = Join-Path $Root 'Local/Settings.json'
    if ([IO.File]::Exists($path)) {
        $saved = [IO.File]::ReadAllText($path) | ConvertFrom-Json
        foreach ($name in @($settings.Keys)) {
            $property = $saved.PSObject.Properties[$name]
            if ($null -ne $property) { $settings[$name] = $property.Value }
        }
    }
    Assert-ScarletSettings $settings
    $settings
}

function Assert-ScarletSettings($Settings) {
    $advanced = Get-ScarletAdvancedOptions
    foreach ($key in $advanced.Keys) {
        if ([string]$Settings[$key] -notin $advanced[$key].Keys) {
            throw "Invalid Scarlet Dawn setting for $key."
        }
    }
    if ($Settings.Resolution -notin '960x540','1280x720','1600x900','1920x1080','2560x1440','3840x2160' -or
        $Settings.Scale -notin 50,67,75,85,100 -or
        $Settings.Quality -notin 0,1,2,3 -or
        $Settings.Display -notin 'Windowed','Borderless' -or
        $Settings.VSync -isnot [bool] -or $Settings.StereoFix -isnot [bool] -or
        $Settings.InputMode -notin 'Mouse','Sinden','RawInput','Gamepad' -or
        $Settings.GamepadSensitivity -notin 50,75,100,125,150,175 -or
        $Settings.ReticleStyle -notin (Get-ScarletReticleStyles).Keys -or
        $Settings.ReticleColor -notin (Get-ScarletReticleColors).Keys -or $Settings.ReticleSize -notin 1,2,3 -or
        $Settings.BorderWidth -notin 0,25,50,75,100 -or $Settings.OffscreenReload -isnot [bool] -or
        $Settings.SindenSwitchWeaponOnReload -isnot [bool] -or $Settings.MuteCreditSounds -isnot [bool] -or
        $Settings.Gun1 -isnot [string] -or $Settings.Gun2 -isnot [string] -or
        !$Settings.Gun1 -or !$Settings.Gun2 -or $Settings.Gun1.Length -gt 1023 -or $Settings.Gun2.Length -gt 1023 -or
        ($Settings.Gun1 -eq $Settings.Gun2 -and $Settings.Gun1 -notin 'auto','disabled')) {
        throw 'Invalid Scarlet Dawn settings.'
    }
}

function Save-ScarletSettings([string]$Root, $Settings) {
    Assert-ScarletSettings $Settings
    Set-ScarletFile (Join-Path $Root 'Local/Settings.json') ($Settings | ConvertTo-Json)
}

function Set-ScarletIni([string]$Path, [System.Collections.IDictionary]$Sections) {
    $lines = if ([IO.File]::Exists($Path)) { [IO.File]::ReadAllLines($Path) } else { @() }
    $destination = [Collections.Generic.List[string]]::new()
    $section = ''
    $seen = @{}
    foreach ($line in @($lines)) {
        if ($line -match '^\s*\[([^\]]+)\]') {
            if ($Sections.Contains($section) -and !$seen[$section]) {
                foreach ($key in $Sections[$section].Keys) {
                    if ($null -ne $Sections[$section][$key]) { $destination.Add("$key=$($Sections[$section][$key])") }
                }
                $seen[$section] = $true
            }
            $section = $Matches[1]
        } elseif ($Sections.Contains($section) -and $line -match '^\s*([^;#=]+?)\s*=' -and
                  $Sections[$section].Contains($Matches[1])) {
            continue
        }
        $destination.Add($line)
    }
    if ($Sections.Contains($section) -and !$seen[$section]) {
        foreach ($key in $Sections[$section].Keys) {
            if ($null -ne $Sections[$section][$key]) { $destination.Add("$key=$($Sections[$section][$key])") }
        }
        $seen[$section] = $true
    }
    foreach ($section in $Sections.Keys) {
        if ($seen[$section]) { continue }
        $destination.Add('')
        $destination.Add("[$section]")
        foreach ($key in $Sections[$section].Keys) {
            if ($null -ne $Sections[$section][$key]) { $destination.Add("$key=$($Sections[$section][$key])") }
        }
    }
    Set-ScarletFile $Path (($destination -join "`r`n") + "`r`n")
}

function Set-ScarletInputDefaults([string]$Path) {
    $sectionName = '/Script/Engine.InputSettings'
    $bindings = [ordered]@{
        P1Start = @('One', 'Enter')
        P1GunTrigger = @('LeftMouseButton')
        P1GunSelect = @('RightMouseButton')
        P1GunSpecial = @('MiddleMouseButton')
    }
    $lines = [Collections.Generic.List[string]]::new()
    if ([IO.File]::Exists($Path)) { $lines.AddRange([IO.File]::ReadAllLines($Path)) }
    $existing = @{}
    $inInputSettings = $false
    $sectionEnd = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s*\[([^\]]+)\]') {
            $inInputSettings = $Matches[1] -eq $sectionName
        }
        if (!$inInputSettings) { continue }
        $sectionEnd = $i + 1
        if ($line -match '^\s*[+.]?ActionMappings\s*=\s*\(\s*ActionName\s*=\s*"?([A-Za-z0-9_]+)"?\s*,') {
            $existing[$Matches[1]] = $true
        }
    }
    $missing = [Collections.Generic.List[string]]::new()
    foreach ($action in $bindings.Keys) {
        if ($existing[$action]) { continue }
        foreach ($key in $bindings[$action]) {
            $missing.Add(('ActionMappings=(ActionName="{0}",Key={1},bShift=False,bCtrl=False,bAlt=False,bCmd=False)' -f $action,$key))
        }
    }
    if ($missing.Count -eq 0) { return }
    if ($sectionEnd -lt 0) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -ne '') { $lines.Add('') }
        $lines.Add("[$sectionName]")
        $sectionEnd = $lines.Count
    }
    $lines.InsertRange($sectionEnd, $missing)
    Set-ScarletFile $Path (($lines -join "`r`n") + "`r`n")
}

function Sync-ScarletStereo([string]$Root, [bool]$Enabled) {
    $folder = Join-Path $Root 'Game/Hodzero/Content/Paks'
    if (![IO.Directory]::Exists($folder)) { throw 'The local game copy is missing its Paks folder.' }
    foreach ($path in @($folder, (Join-Path $Root 'Game'))) {
        if ([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) {
            throw 'The local game copy must use ordinary folders.'
        }
    }
    $target = Join-Path $folder $ScarletStereoName
    $patch = Join-Path $Root ("Local/Audio/" + $ScarletStereoName)
    $acf = Join-Path $Root 'Game/Hodzero/Content/Hodzero_V1/ADX/NewProject.acf'
    $replacement = Join-Path $Root $(if ($Enabled) { 'Local/Audio/NewProject.stereo.acf' } else { 'Local/Audio/NewProject.original.acf' })
    $wanted = if ($Enabled) { $ScarletStereoAcf } else { $ScarletOriginalAcf }
    if (![IO.File]::Exists($acf)) { throw 'The local game copy is missing NewProject.acf.' }
    $current = Get-ScarletSHA256 $acf
    if ($current -notin $ScarletStereoAcf,$ScarletOriginalAcf) {
        throw 'NewProject.acf differs from the known stereo and original variants.'
    }
    if ($current -ne $wanted -and (![IO.File]::Exists($replacement) -or (Get-ScarletSHA256 $replacement) -ne $wanted)) {
        throw 'The verified ACF variant is missing from Local/Audio.'
    }
    $exists = [IO.File]::Exists($target)
    if ($exists -and ((Get-ScarletSHA256 $target) -ne $ScarletStereoHash)) {
        throw 'The existing stereo patch differs from the verified copy. Move that patch out of Paks before switching audio.'
    }
    if ($Enabled -and !$exists -and (![IO.File]::Exists($patch) -or (Get-ScarletSHA256 $patch) -ne $ScarletStereoHash)) {
        throw 'The verified stereo patch is missing from Local/Audio.'
    }
    if ($current -ne $wanted) {
        Set-ScarletBytes $acf ([IO.File]::ReadAllBytes($replacement))
    }
    if ($Enabled -and !$exists) {
        Set-ScarletBytes $target ([IO.File]::ReadAllBytes($patch))
    } elseif (!$Enabled -and $exists) {
        [IO.File]::Delete($target)
    }
}


function Read-ScarletCreditExport($Reader, [long[]]$Chunks, [int]$Length, [string]$ExpectedHash,
                                 [int]$CueOffset, [int]$PreviousImport) {
    $export = [byte[]]::new($Length)
    $at = 0
    for ($i = 0; $i -lt $Chunks.Count; $i += 2) {
        $Reader.BaseStream.Position = $Chunks[$i]
        $compressed = $Reader.ReadBytes([int]$Chunks[$i+1])
        if ($compressed.Length -ne $Chunks[$i+1]) { throw 'The original arcade sound package is incomplete.' }
        # Unreal Pak v4 uses zlib blocks. DeflateStream consumes the payload between its header and trailer.
        $inputStream = [IO.MemoryStream]::new($compressed, 2, $compressed.Length - 6, $false)
        $inflate = [IO.Compression.DeflateStream]::new($inputStream, [IO.Compression.CompressionMode]::Decompress)
        try {
            while ($at -lt $export.Length) {
                $read = $inflate.Read($export, $at, $export.Length - $at)
                if (!$read) { break }
                $at += $read
            }
            if ($inflate.ReadByte() -ge 0) { throw 'Unexpected size for the arcade sound export.' }
        } finally { $inflate.Dispose(); $inputStream.Dispose() }
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $actual = [BitConverter]::ToString($sha.ComputeHash($export)).Replace('-','') }
    finally { $sha.Dispose() }
    if ($at -ne $Length -or $actual -ne $ExpectedHash -or $export[$CueOffset-1] -ne 0x20 -or
        [BitConverter]::ToInt32($export, $CueOffset) -ne $PreviousImport) {
        throw 'The game package has an unsupported Start or coin sound export.'
    }
    # Clear the cue argument in this Blueprint only. The same cue can still be used in other menus.
    [Array]::Clear($export, $CueOffset, 4)
    return ,$export
}

function Write-ScarletPakString($Writer, [string]$Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value + [char]0)
    $Writer.Write([int]$bytes.Length)
    $Writer.Write($bytes)
}

function Write-ScarletPakEntry($Writer, [long]$Offset, [byte[]]$Data, [byte[]]$Hash) {
    $Writer.Write($Offset)
    $Writer.Write([long]$Data.Length)
    $Writer.Write([long]$Data.Length)
    $Writer.Write([int]0)
    $Writer.Write($Hash)
    $Writer.Write([byte]0)
    $Writer.Write([int]0)
}

function New-ScarletCreditSoundPak([string]$GamePak) {
    if ((Get-Item -LiteralPath $GamePak).Length -ne 7847593660) {
        throw 'The Start and coin sound option requires the supported Scarlet Dawn Export PAK.'
    }
    $source = [IO.BinaryReader]::new([IO.File]::OpenRead($GamePak))
    $pak = [IO.BinaryWriter]::new([IO.MemoryStream]::new())
    $index = [IO.BinaryWriter]::new([IO.MemoryStream]::new())
    $sha = [Security.Cryptography.SHA1]::Create()
    try {
        $exports = [ordered]@{
            'Hodzero/Content/HodZero/Blueprints/GameMode/BPC_StartButton.uexp' =
                (Read-ScarletCreditExport $source @(65368137,1260) 4933 'AB9C07448970FF62CC18A92AA2491263D88D666FAB614AD6B0D001D526D75133' 2619 -70)
            'Hodzero/Content/HodZero_v1/Blueprints/GameInstance/BP_HodGameInstance.uexp' =
                (Read-ScarletCreditExport $source @(477866073,15885,477881958,5460) 107765 '27E9F4E2700907D3414E727B337C812894C47F5FE278910FE66A467D1FB89A4D' 18824 -429)
        }
        Write-ScarletPakString $index '../../../'
        $index.Write([int]$exports.Count)
        foreach ($name in $exports.Keys) {
            $data = $exports[$name]
            $digest = $sha.ComputeHash($data)
            Write-ScarletPakString $index $name
            Write-ScarletPakEntry $index $pak.BaseStream.Position $data $digest
            Write-ScarletPakEntry $pak 0 $data $digest
            $pak.Write($data)
        }
        $indexOffset = $pak.BaseStream.Position
        $indexData = $index.BaseStream.ToArray()
        $pak.Write($indexData)
        $pak.Write([byte]0)
        $pak.Write([uint32]0x5a6f12e1)
        $pak.Write([int]4)
        $pak.Write([long]$indexOffset)
        $pak.Write([long]$indexData.Length)
        $pak.Write($sha.ComputeHash($indexData))
        return ,$pak.BaseStream.ToArray()
    } finally { $source.Dispose(); $pak.Dispose(); $index.Dispose(); $sha.Dispose() }
}

function Sync-ScarletCreditSounds([string]$GamePak, [bool]$Mute) {
    $target = Join-Path ([IO.Path]::GetDirectoryName($GamePak)) 'Hodzero-CodexCreditSounds_P.pak'
    if ([IO.File]::Exists($target)) {
        if (([IO.File]::GetAttributes($target) -band [IO.FileAttributes]::ReparsePoint) -or
            (Get-ScarletSHA256 $target) -ne '9002CEFB02CFA1D61771CA275C5F43FF25095622513714F98BF87EECA221E33C') {
            throw 'Move the existing Hodzero-CodexCreditSounds_P.pak out of the Paks folder before changing this option.'
        }
        if (!$Mute) { [IO.File]::Delete($target) }
    } elseif ($Mute) {
        Set-ScarletBytes $target (New-ScarletCreditSoundPak $GamePak)
    }
}

function Get-ScarletPatchedExecutable([string]$Root, [string]$Original, [string]$Variant) {
    $manifestPath = Join-Path $Root "scarlet-$($Variant.ToLowerInvariant())-patch.json"
    $patch = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    $bin = [IO.Path]::GetDirectoryName($Original)
    $target = Join-Path $bin "Hodzero-Win64-Shipping-Scarlet$Variant.exe"
    if ($Variant -eq 'Lightgun') {
        $library = Join-Path $bin 'ScarletLightgun.dll'
        if (![IO.File]::Exists($library) -or (Get-ScarletSHA256 $library) -ne $patch.DllSHA256) {
            $bundled = Join-Path $Root 'ScarletLightgun.dll'
            if (![IO.File]::Exists($bundled) -or (Get-ScarletSHA256 $bundled) -ne $patch.DllSHA256) {
                throw 'The verified Scarlet Dawn lightgun library is missing.'
            }
            Set-ScarletBytes $library ([IO.File]::ReadAllBytes($bundled))
        }
    }
    if ([IO.File]::Exists($target) -and (Get-ScarletSHA256 $target) -eq $patch.PatchedSHA256) {
        return $target
    }
    if ((Get-ScarletSHA256 $Original) -ne $patch.SourceSHA256) {
        throw "The Scarlet Dawn executable differs from the build supported by the $Variant patch."
    }

    $source = [IO.File]::ReadAllBytes($Original)
    if ($source.Length -ne $patch.SourceLength) { throw 'The executable size differs from the patch manifest.' }
    $tail = [Convert]::FromBase64String($patch.Append)
    $patched = [byte[]]::new($source.Length + $tail.Length)
    [Buffer]::BlockCopy($source, 0, $patched, 0, $source.Length)
    [Buffer]::BlockCopy($tail, 0, $patched, $source.Length, $tail.Length)
    foreach ($edit in $patch.Edits) {
        $offset = [int]$edit.Offset
        $before = [Convert]::FromBase64String($edit.Before)
        $after = [Convert]::FromBase64String($edit.After)
        if ($offset -lt 0 -or $before.Length -ne $after.Length -or $offset + $before.Length -gt $source.Length -or
            [Convert]::ToBase64String($source, $offset, $before.Length) -cne $edit.Before) {
            throw 'An executable region differs from the patch manifest.'
        }
        [Buffer]::BlockCopy($after, 0, $patched, $offset, $after.Length)
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $digest = [BitConverter]::ToString($sha.ComputeHash($patched)).Replace('-','') }
    finally { $sha.Dispose() }
    if ($digest -ne $patch.PatchedSHA256) { throw 'The generated game executable failed verification.' }
    Set-ScarletBytes $target $patched
    $target
}

function New-ScarletStartInfo([string]$Root, $Settings) {
    Assert-ScarletSettings $Settings
    $game = Join-Path $Root 'Game'
    $exe = Join-Path $game 'Hodzero/Binaries/Win64/Hodzero-Win64-Shipping.exe'
    $mainPak = Join-Path $game 'Hodzero/Content/Paks/Hodzero-WindowsNoEditor.pak'
    $missing = @($exe, $mainPak | Where-Object { ![IO.File]::Exists($_) })
    if ($missing.Count) {
        throw "The local Scarlet Dawn game copy is incomplete. Missing:$([Environment]::NewLine)$($missing -join [Environment]::NewLine)"
    }
    $profile = Join-Path $Root 'Local/Profile'
    $config = Join-Path $profile 'Saved/Config/WindowsNoEditor'
    $width,$height = $Settings.Resolution.Split('x')
    $quality = [int]$Settings.Quality
    $video = [ordered]@{
        ResolutionSizeX=$width; ResolutionSizeY=$height
        LastUserConfirmedResolutionSizeX=$width; LastUserConfirmedResolutionSizeY=$height
        FullscreenMode=if ($Settings.Display -eq 'Windowed') { 2 } else { 1 }
        LastConfirmedFullscreenMode=if ($Settings.Display -eq 'Windowed') { 2 } else { 1 }
        bUseVSync=if ($Settings.VSync) { 'True' } else { 'False' }
        FrameRateLimit=('{0}.000000' -f $Settings.FrameCap); Version=5
    }
    $scalability = [ordered]@{ 'sg.ResolutionQuality'=$Settings.Scale }
    foreach ($name in 'ViewDistance','AntiAliasing','Shadow','PostProcess','Texture','Effects','Foliage') {
        $scalability["sg.${name}Quality"] = $quality
    }
    foreach ($entry in @(
        @{ Field='Shadows'; Group='Shadow' }
        @{ Field='TextureDetail'; Group='Texture' }
        @{ Field='Effects'; Group='Effects' }
    )) {
        if ($Settings[$entry.Field] -ge 0) { $scalability["sg.$($entry.Group)Quality"]=$Settings[$entry.Field] }
    }
    Set-ScarletIni (Join-Path $config 'GameUserSettings.ini') ([ordered]@{
        'ScalabilityGroups'=$scalability
        '/Script/Engine.GameUserSettings'=$video
    })
    $system = [ordered]@{
        'r.ScreenPercentage'=$Settings.Scale
        't.MaxFPS'=$Settings.FrameCap
        'r.VSync'=[int]$Settings.VSync
        'r.Streaming.PoolSize'=if ($Settings.TexturePool -ge 0) { $Settings.TexturePool } else { @(512,768,1024,1536)[$quality] }
        'r.PostProcessAAQuality'=if ($Settings.AntiAliasing -ge 0) { $Settings.AntiAliasing } else { @(0,2,3,4)[$quality] }
        'r.ShadowQuality'=@(0,2,3,5)[[int]$scalability['sg.ShadowQuality']]
        'r.MotionBlurQuality'=$Settings.MotionBlur
        'r.DepthOfFieldQuality'=if ($Settings.DepthOfField -ge 0) { $Settings.DepthOfField } else { @(0,1,1,2)[$quality] }
        'r.AmbientOcclusionLevels'=if ($Settings.Occlusion -ge 0) { $Settings.Occlusion } else { @(0,1,2,3)[$quality] }
        'r.AmbientOcclusionMaxQuality'=if ($Settings.Occlusion -ge 0) { (@{0=0;1=60;3=100})[[int]$Settings.Occlusion] } else { $null }
        'r.SSR.Quality'=if ($Settings.Reflections -ge 0) { $Settings.Reflections } else { $null }
        'r.VolumetricFog'=if ($Settings.VolumetricFog -ge 0) { $Settings.VolumetricFog } else { $null }
        'r.BloomQuality'=if ($Settings.Bloom -ge 0) { $Settings.Bloom } else { $null }
        'r.FullScreenMode'=if ($Settings.Display -eq 'Borderless' -and ($Settings.InputMode -ne 'Mouse' -or $Settings.ReticleStyle -ne 'Original')) { 1 } else { $null }
    }
    Sync-ScarletStereo $Root $Settings.StereoFix
    Sync-ScarletCreditSounds $mainPak $Settings.MuteCreditSounds
    Set-ScarletIni (Join-Path $config 'Engine.ini') ([ordered]@{
        'SystemSettings'=$system
        'ConsoleVariables'=[ordered]@{ 't.MaxFPS'=$Settings.FrameCap; 'r.VSync'=[int]$Settings.VSync }
        'Audio'=[ordered]@{ Channels=if ($Settings.StereoFix) { 2 } }
        '/Script/CriWareRuntime.CriWarePluginSettings'=[ordered]@{
            WASAPI_NumChannels=$(if ($Settings.StereoFix) { 2 })
            WASAPI_SamplingRate=$(if ($Settings.StereoFix) { 48000 })
            WASAPI_BitsPerSample=$(if ($Settings.StereoFix) { 16 })
        }
    })
    Set-ScarletIni (Join-Path $config 'Game.ini') ([ordered]@{
        '/Script/Hodzero.AppGameInstance'=[ordered]@{
            DebugWithoutAMDaemon='true'
            DebugAMCredit='true'
            DebugAMCreditFreePlay='true'
            DevelopSetting_PlayerGunDevice=1
        }
    })
    Set-ScarletInputDefaults (Join-Path $config 'Input.ini')
    $logs = Join-Path $Root 'Local/Logs'
    [void][IO.Directory]::CreateDirectory($logs)
    $log = Join-Path $logs ('Hodzero-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff') + '.log')
    $window = if ($Settings.Display -eq 'Windowed') { '-windowed' } else { '-fullscreen' }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $aim = Get-ScarletPatchedExecutable $Root $exe 'Aim'
    $info.FileName=Get-ScarletPatchedExecutable $Root $aim 'Lightgun'
    $info.EnvironmentVariables['SCARLET_SETTINGS_ROOT'] = $Root
    $info.EnvironmentVariables['SCARLET_GUN_MODE'] = $Settings.InputMode
    $info.EnvironmentVariables['SCARLET_GAMEPAD_SENSITIVITY'] = [string]$Settings.GamepadSensitivity
    $info.EnvironmentVariables['SCARLET_GUN_P1'] = $Settings.Gun1
    $info.EnvironmentVariables['SCARLET_GUN_P2'] = $Settings.Gun2
    $info.EnvironmentVariables['SCARLET_GUN_RELOAD'] = [string][int]$Settings.OffscreenReload
    $info.EnvironmentVariables['SCARLET_SINDEN_SWITCH_WEAPON_ON_RELOAD'] = [string][int]($Settings.InputMode -eq 'Sinden' -and $Settings.SindenSwitchWeaponOnReload)
    $info.EnvironmentVariables['SCARLET_GUN_BORDER'] = if ($Settings.InputMode -in 'Sinden','RawInput') { [string]$Settings.BorderWidth } else { '0' }
    $info.EnvironmentVariables['SCARLET_RETICLE_STYLE'] = $Settings.ReticleStyle
    $info.EnvironmentVariables['SCARLET_RETICLE_SIZE'] = [string]$Settings.ReticleSize
    $info.EnvironmentVariables['SCARLET_RETICLE_COLOR'] = $Settings.ReticleColor
    $info.Arguments='-launch=pc -NotInstalled -unattended -nosplash {0} -ResX={1} -ResY={2} -UserDir="{3}" -abslog="{4}"' -f $window,$width,$height,$profile,$log
    $info.WorkingDirectory=$game
    $info.UseShellExecute=$false
    $info.CreateNoWindow=$true
    @{ Process=$info; Log=$log }
}

# Shared with the other HOTD builders. Keep this section in a managed file so existing updaters can install it.
# WPF event handlers run from dynamic modules, including in the embedded launcher.
function global:Get-HotdLibraryGames {
    'Normal','Special','EX','Scarlet'
}

function global:Get-HotdLibrarySpec([string]$Game) {
    switch ($Game) {
        Normal  { @{Title='The House of the Dead 4'; App='HOTD4_Recomp'; Packages=@('HOTD4-PC','HOTD4','HOTD 4'); Launcher='Play HOTD4.exe'; Menu='hotd4-startmenu.ps1'; Binary='hotd4-desktop.exe'; Accent='#E89869'} }
        Special { @{Title='The House of the Dead 4 Special'; App='HOTD4SP_Recomp'; Packages=@('HOTD4SP-PC','HOTD4 Special','HOTD 4 Special'); EntryScript='hotd4sp-launcher.ps1'; Launcher='HOTD4SP_Recomp/Play HOTD4 Special.exe'; Menu='hotd4sp-startmenu.ps1'; Binary='hotd4sp-desktop.exe'; Accent='#F37580'} }
        EX      { @{Title='The House of the Dead EX'; App='HOTDEX_Recomp'; Packages=@('HOTDEX-PC','HOTD EX'); EntryScript='config_menu.ps1'; Launcher='Play HOTD EX.exe'; Menu='hotdex-startmenu.ps1'; Binary='hotdex-desktop.exe'; Accent='#76D3DB'} }
        Scarlet { @{Title='House of the Dead: Scarlet Dawn'; App=''; Packages=@('ScarletDawn-PC','HOTDSD-PC','Scarlet Dawn'); EntryScript='scarlet-menu.xaml'; Launcher='Play Scarlet Dawn.exe'; Menu='scarlet-menu.ps1'; Binary='scarlet-settings.ps1'; Accent='#DDA1EA'} }
    }
}

function global:Get-HotdLibraryPath {
    Join-Path $env:LOCALAPPDATA 'HOTD4-Launcher/game-library.json'
}

function global:Read-HotdLibraryFile([string]$Path) {
    try {
        if (![IO.File]::Exists($Path)) { return }
        $share=[IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
        $stream=[IO.File]::Open($Path,'Open','Read',$share)
        try {
            $reader=[IO.StreamReader]::new($stream)
            try { return ($reader.ReadToEnd() | ConvertFrom-Json) }
            finally { $reader.Dispose() }
        } finally { $stream.Dispose() }
    } catch { Write-Verbose ('Could not read the game library file: '+$_.Exception.Message) }
}

function global:Read-Hotd4Library([string]$LibraryFile=(Get-HotdLibraryPath)) {
    $result=@{}
    $data=Read-HotdLibraryFile $LibraryFile
    if ($data -and $data.Version -eq 1) {
        foreach ($game in Get-HotdLibraryGames) {
            $property=$data.PSObject.Properties[$game]
            if ($property -and $property.Value -is [string]) { $result[$game]=$property.Value }
        }
    }
    return $result
}

function global:Test-HotdLibraryData([string]$Root,[string]$Game) {
    if ($Game -eq 'Scarlet') {
        $data=Join-Path $Root 'Game/Hodzero'
        return ([IO.File]::Exists((Join-Path $data 'Binaries/Win64/Hodzero-Win64-Shipping.exe')) -and
                [IO.File]::Exists((Join-Path $data 'Content/Paks/Hodzero-WindowsNoEditor.pak')))
    }

    $elf='hod4M.elf'
    switch ($Game) {
        Normal {
            $config=Join-Path $Root 'dump-path.txt'
            if ([IO.File]::Exists($config)) {
                $dump=[IO.File]::ReadAllText($config).Trim()
                if (![IO.Path]::IsPathRooted($dump)) { return $false }
            } elseif ([IO.File]::Exists((Join-Path $Root 'Spela HOTD4 i 4K.cmd'))) {
                $dump=Join-Path $Root 'The House of the Dead 4/disk0'
            } else { return $false }
        }
        Special { $dump=Join-Path $Root 'hotd4sp' }
        EX { $dump=Join-Path $Root 'disk0'; $elf='hodexRI.elf' }
    }
    return ([IO.File]::Exists((Join-Path $dump ('elf/'+$elf))) -and
            [IO.Directory]::Exists((Join-Path $dump 'fs')))
}

function global:Resolve-Hotd4Installation {
    param([string]$Path,[ValidateSet('Normal','Special','EX','Scarlet')][string]$Game)
    if (!$Path) { return }
    $spec=Get-HotdLibrarySpec $Game
    try {
        if (![IO.Path]::IsPathRooted($Path)) { return }
        $selected=[IO.Path]::GetFullPath($Path)
        if ([IO.File]::Exists($selected)) { $selected=[IO.Path]::GetDirectoryName($selected) }
        if ($spec.App -and (Split-Path $selected -Leaf) -eq $spec.App) {
            $selected=[IO.Path]::GetDirectoryName($selected.TrimEnd('\','/'))
        }
        $roots=@($selected; foreach ($package in $spec.Packages) { Join-Path $selected $package })
        foreach ($root in $roots) {
            $app=if ($spec.App) { Join-Path $root $spec.App } else { $root }
            $launcher=Join-Path $root $spec.Launcher
            $menu=Join-Path $app $spec.Menu
            if (![IO.File]::Exists($launcher) -or ![IO.File]::Exists($menu) -or
                ![IO.File]::Exists((Join-Path $app $spec.Binary)) -or !(Test-HotdLibraryData $root $Game)) { continue }
            if ($spec.EntryScript -and ![IO.File]::Exists((Join-Path $app $spec.EntryScript))) { continue }
            $normalCmd=Join-Path $root 'Play HOTD4.cmd'
            if ($Game -eq 'Normal' -and ![IO.File]::Exists($normalCmd) -and
                ![IO.File]::Exists((Join-Path $root 'Spela HOTD4 i 4K.cmd'))) { continue }
            $supportsLibrary=if ($Game -eq 'Scarlet') {
                (Get-Content -LiteralPath $menu -TotalCount 5) -contains '# HOTD Game Library'
            } else { [IO.File]::Exists((Join-Path $app 'hotd-game-library.ps1')) }
            $legacyDirect=$Game -eq 'Normal' -and [IO.File]::Exists($normalCmd) -and
                (Get-Content -LiteralPath $normalCmd -TotalCount 20 -ErrorAction Stop | Select-String -Quiet 'HOTD4_NO_LAUNCHER')
            return [pscustomobject]@{
                Game=$Game; Title=$spec.Title; App=$app; Root=$root; Launcher=$launcher; Accent=$spec.Accent
                CanPlay=($supportsLibrary -or $Game -eq 'EX' -or $legacyDirect)
                CanSettings=($supportsLibrary -or $Game -in 'Special','EX')
            }
        }
    } catch { Write-Verbose ('Could not check an installation: '+$_.Exception.Message) }
}

function global:Register-Hotd4Installation {
    param([string]$RecompDir,[ValidateSet('Normal','Special','EX','Scarlet')][string]$Game,
          [string]$LibraryFile=(Get-HotdLibraryPath))
    $installation=Resolve-Hotd4Installation $RecompDir $Game
    if (!$installation) { throw 'Select a complete HOTD installation with its launcher and game data.' }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($LibraryFile))
    $lock=$null
    $pending=$LibraryFile+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    try {
        for ($attempt=0;$attempt -lt 10;$attempt++) {
            try {
                $lock=[IO.File]::Open(($LibraryFile+'.lock'),'OpenOrCreate','ReadWrite','None')
                break
            } catch [IO.IOException] {
                if ($attempt -eq 9) { throw }
                Start-Sleep -Milliseconds 100
            }
        }
        $data=Read-Hotd4Library $LibraryFile
        if ($data[$Game] -ceq $installation.App) { return }
        $data.Version=1
        $data[$Game]=$installation.App
        [IO.File]::WriteAllText($pending,($data | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($LibraryFile)) {
            [IO.File]::Replace($pending,$LibraryFile,[NullString]::Value)
        } else { [IO.File]::Move($pending,$LibraryFile) }
    } finally {
        if ($lock) { $lock.Dispose() }
        if ([IO.File]::Exists($pending)) { [IO.File]::Delete($pending) }
    }
}

function global:Get-HotdLibraryInstallations {
    param([string]$RecompDir,[ValidateSet('Normal','Special','EX','Scarlet')][string]$CurrentGame,
          [string]$LibraryFile=(Get-HotdLibraryPath))
    $current=Resolve-Hotd4Installation $RecompDir $CurrentGame
    $saved=Read-Hotd4Library $LibraryFile
    $legacy=Read-Hotd4Library (Join-Path $env:LOCALAPPDATA 'HOTD4-Launcher/installations.json')
    $nearby=@($RecompDir)
    if ($current) {
        $nearby+=@($current.Root,(Split-Path $current.Root -Parent))
    } elseif ($RecompDir) {
        $nearby+=Split-Path $RecompDir -Parent
    }

    foreach ($game in Get-HotdLibraryGames) {
        if ($game -eq $CurrentGame -and $current) { $current; continue }
        $history=Read-HotdLibraryFile (Join-Path $env:LOCALAPPDATA ('HOTD-Setup/'+$game+'.json'))
        $remembered=if ($history -and $history.Format -eq 1 -and $history.Edition -ceq $game) { $history.InstallDir }
        foreach ($candidate in @($saved[$game],$legacy[$game],$remembered)+$nearby) {
            $installation=Resolve-Hotd4Installation $candidate $game
            if ($installation) { $installation; break }
        }
    }
}

function global:New-Hotd4GameStartInfo {
    param([string]$RecompDir,[ValidateSet('Normal','Special','EX','Scarlet')][string]$Game,
          [string]$PreviousRecompDir,[ValidateSet('Menu','Play','Settings')][string]$Action='Menu')
    $installation=Resolve-Hotd4Installation $RecompDir $Game
    if (!$installation) { throw 'This installation was moved or is incomplete. Use Locate installed game to find it again.' }
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$installation.Launcher
    $info.WorkingDirectory=[IO.Path]::GetDirectoryName($info.FileName)
    $info.UseShellExecute=$false
    $info.CreateNoWindow=$true
    if ($Action -eq 'Settings' -and $installation.CanSettings) { $info.Arguments='--settings' }
    if ($Action -eq 'Play' -and $installation.CanPlay) { $info.Arguments='--no-launcher' }
    foreach ($key in @($info.EnvironmentVariables.Keys)) {
        if ($key -match '^(HOTD4(?:SP)?_|HOTDEX_|SCARLET_|LINDBERGH_|RECOMP_|TEA_)') {
            $info.EnvironmentVariables.Remove($key)
        }
    }
    if ($PreviousRecompDir -and $info.EnvironmentVariables['PATH']) {
        $previous=$PreviousRecompDir.TrimEnd('\','/')
        $parts=$info.EnvironmentVariables['PATH'] -split ';' | Where-Object { $_.Trim('"').TrimEnd('\','/') -ine $previous }
        $info.EnvironmentVariables['PATH']=$parts -join ';'
    }
    return $info
}

function global:Show-HotdGameLibrary {
    param($Owner,[string]$RecompDir,[string]$CurrentGame,[scriptblock]$Inspect)
    [xml]$markup=@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="The House of the Dead" WindowStartupLocation="CenterOwner" ShowInTaskbar="False"
        ResizeMode="NoResize" SizeToContent="Height" Background="#111419" Foreground="#F2EEEB"
        FontFamily="Segoe UI" UseLayoutRounding="True">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#F2EEEB"/>
      <Setter Property="Background" Value="#252A34"/>
      <Setter Property="BorderBrush" Value="#424956"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="14,7"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Face" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                    Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="5" Padding="{TemplateBinding Padding}">
              <ContentPresenter VerticalAlignment="Center" HorizontalAlignment="Center" RecognizesAccessKey="True"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Face" Property="BorderBrush" Value="#F3BA9E"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Face" Property="BorderBrush" Value="White"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="Face" Property="Opacity" Value=".75"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Grid Margin="24,19,24,19">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Text="Game Library" FontSize="31" FontWeight="Bold" Margin="0,0,0,15"/>
    <ScrollViewer Name="GameScroll" Grid.Row="1" VerticalScrollBarVisibility="Auto">
      <StackPanel Name="Games"/>
    </ScrollViewer>
    <DockPanel Grid.Row="2" Margin="0,12,0,0">
      <Button Name="Back" Content="_Back" DockPanel.Dock="Right" IsCancel="True"/>
      <Button Name="Locate" Content="_Locate installed game..." DockPanel.Dock="Left"/>
      <TextBlock Name="Status" TextWrapping="Wrap" Foreground="#F3BA9E" VerticalAlignment="Center" Margin="10,0"/>
    </DockPanel>
  </Grid>
</Window>
"@
    $window=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($markup))
    if ($Owner) { $window.Owner=$Owner }
    $workArea=[Windows.SystemParameters]::WorkArea
    $window.Width=[Math]::Min(690,$workArea.Width-32)
    $window.MaxHeight=$workArea.Height-24
    $games=$window.FindName('Games')
    $scroll=$window.FindName('GameScroll')
    $scroll.MaxHeight=[Math]::Max(120,$window.MaxHeight-164)
    $status=$window.FindName('Status')
    $state=@{ Selection=$null; Focus=$null }

    $refresh={
        $games.Children.Clear()
        $status.Text=''
        $state.Focus=$null
        foreach ($item in Get-HotdLibraryInstallations $RecompDir $CurrentGame) {
            $card=[Windows.Controls.Border]::new()
            $card.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#1D222B')
            $card.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFromString($item.Accent)
            $card.BorderThickness=[Windows.Thickness]::new(3,0,0,0)
            $card.CornerRadius=[Windows.CornerRadius]::new(6)
            $card.Padding=[Windows.Thickness]::new(12,11,11,11)
            $card.Margin=[Windows.Thickness]::new(0,0,3,7)
            $row=[Windows.Controls.DockPanel]::new()
            $actions=[Windows.Controls.StackPanel]::new()
            $actions.Orientation='Horizontal'
            $actions.VerticalAlignment='Center'
            [Windows.Controls.DockPanel]::SetDock($actions,'Right')
            [void]$row.Children.Add($actions)
            $title=[Windows.Controls.StackPanel]::new()
            $title.VerticalAlignment='Center'
            $title.Margin=[Windows.Thickness]::new(0,0,10,0)
            $name=[Windows.Controls.TextBlock]::new()
            $name.Text=$item.Title
            $name.FontSize=18
            $name.FontWeight='SemiBold'
            $name.TextWrapping='Wrap'
            [void]$title.Children.Add($name)
            if ($item.Game -eq $CurrentGame) {
                $current=[Windows.Controls.TextBlock]::new()
                $current.Text='Current game'
                $current.FontSize=12
                $current.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString($item.Accent)
                [void]$title.Children.Add($current)
            }
            [void]$row.Children.Add($title)
            $options=[ordered]@{}
            if ($item.Game -ne $CurrentGame) { $options.Menu='Menu' }
            if ($item.CanSettings) { $options.Settings='Settings' }
            if ($item.CanPlay) { $options.Play='Play' }
            if ($options.Count -eq 0) { $options.Menu='Menu' }

            foreach ($action in $options.Keys) {
                $button=[Windows.Controls.Button]::new()
                $button.Content=$options[$action]
                $button.Margin=[Windows.Thickness]::new(5,0,0,0)
                $button.Tag=@{ Installation=$item; Action=$action; State=$state; Window=$window }
                $button.ToolTip=switch ($action) {
                    Menu { 'Open the game menu' }
                    Settings { 'Open game settings' }
                    Play { 'Start a game using saved settings' }
                }
                [Windows.Automation.AutomationProperties]::SetName($button,("$($button.Content) - $($item.Title)"))
                if ($action -eq 'Play') {
                    $button.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#783B40')
                    $button.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFromString('#AA5D60')
                    if (!$state.Focus -or $item.Game -eq $CurrentGame) { $state.Focus=$button }
                }
                $button.Add_Click({
                    param($sender,$eventArgs)
                    $target=$sender.Tag
                    $target.State['Selection']=@{ Installation=$target.Installation; Action=$target.Action }
                    $target.Window.Close()
                })
                [void]$actions.Children.Add($button)
            }
            $card.Child=$row
            [void]$games.Children.Add($card)
        }
        if ($games.Children.Count -eq 0) { $status.Text='Locate a complete installation to add it.' }
    }.GetNewClosure()
    & $refresh

    $window.FindName('Locate').Add_Click({
        Add-Type -AssemblyName System.Windows.Forms
        $dialog=[Windows.Forms.FolderBrowserDialog]::new()
        $dialog.Description='Select the installation folder for HOTD4, HOTD4 Special, HOTD EX or Scarlet Dawn.'
        $dialog.ShowNewFolderButton=$false
        try {
            if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return }
            $found=@(foreach ($game in Get-HotdLibraryGames) { Resolve-Hotd4Installation $dialog.SelectedPath $game })
            if (!$found) { throw 'No complete HOTD installation was found in that folder.' }
            foreach ($item in $found) { Register-Hotd4Installation $item.App $item.Game }
            $status.Text=''
            & $refresh
        } catch {
            $status.Text=$_.Exception.Message
        } finally { $dialog.Dispose() }
    }.GetNewClosure())
    $window.Add_ContentRendered({
        $focus=if ($state.Focus) { $state.Focus } else { $window.FindName('Locate') }
        [void]$focus.Focus()
    }.GetNewClosure())

    if ($Inspect) { & $Inspect $window $games; return $state.Selection }
    [void]$window.ShowDialog()
    return $state.Selection
}

function global:Add-Hotd4GameSwitcher {
    param($Window,$MainPage,[string]$RecompDir,[ValidateSet('Normal','Special','EX','Scarlet')][string]$CurrentGame,
          $PlayButton,$SettingsButton)
    try { Register-Hotd4Installation $RecompDir $CurrentGame } catch { Write-Verbose $_.Exception.Message }
    $button=[Windows.Controls.Button]::new()
    $button.Name='GameLibrary'
    $button.Content='Game Library...'
    $button.FontSize=16
    $button.MinHeight=34
    # Put it beside the existing top-level actions without changing the Play default.
    $MainPage.Children.Insert([Math]::Min(1,$MainPage.Children.Count),$button)
    $button.Add_Click({
        try {
            $selected=Show-HotdGameLibrary $Window $RecompDir $CurrentGame
            if (!$selected) { return }
            if ($selected.Installation.Game -eq $CurrentGame) {
                $target=switch ($selected.Action) { Play { $PlayButton }; Settings { $SettingsButton } }
                if ($target) {
                    $target.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                }
                return
            }
            $info=New-Hotd4GameStartInfo $selected.Installation.App $selected.Installation.Game $RecompDir $selected.Action
            $child=[Diagnostics.Process]::Start($info)
            if (!$child) { throw 'Could not open the selected game.' }
            $child.Dispose()
            $Window.Close()
        } catch {
            [void][Windows.MessageBox]::Show($Window,$_.Exception.Message,'Game Library','OK','Error')
        }
    }.GetNewClosure())
    return $button
}
