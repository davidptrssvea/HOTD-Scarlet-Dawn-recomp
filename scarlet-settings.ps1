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
        SindenSwitchWeaponOnReload=$false
        ReticleStyle='Original'; ReticleSize=2; ReticleColor='White' }
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
        $Settings.InputMode -notin 'Mouse','Sinden','RawInput' -or
        $Settings.ReticleStyle -notin (Get-ScarletReticleStyles).Keys -or
        $Settings.ReticleColor -notin (Get-ScarletReticleColors).Keys -or $Settings.ReticleSize -notin 1,2,3 -or
        $Settings.BorderWidth -notin 0,25,50,75,100 -or $Settings.OffscreenReload -isnot [bool] -or
        $Settings.SindenSwitchWeaponOnReload -isnot [bool] -or
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
    if (![IO.File]::Exists($exe) -or ![IO.File]::Exists($mainPak)) { throw 'The local Scarlet Dawn game copy is incomplete.' }
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
    $info.FileName=Get-ScarletPatchedExecutable $Root $exe 'Aim'
    if ($Settings.InputMode -ne 'Mouse' -or $Settings.ReticleStyle -ne 'Original') {
        $info.FileName=Get-ScarletPatchedExecutable $Root $info.FileName 'Lightgun'
        $info.EnvironmentVariables['SCARLET_GUN_MODE'] = $Settings.InputMode
        $info.EnvironmentVariables['SCARLET_GUN_P1'] = $Settings.Gun1
        $info.EnvironmentVariables['SCARLET_GUN_P2'] = $Settings.Gun2
        $info.EnvironmentVariables['SCARLET_GUN_RELOAD'] = [string][int]$Settings.OffscreenReload
        $info.EnvironmentVariables['SCARLET_SINDEN_SWITCH_WEAPON_ON_RELOAD'] = [string][int]($Settings.InputMode -eq 'Sinden' -and $Settings.SindenSwitchWeaponOnReload)
        $info.EnvironmentVariables['SCARLET_GUN_BORDER'] = if ($Settings.InputMode -ne 'Mouse') { [string]$Settings.BorderWidth } else { '0' }
        $info.EnvironmentVariables['SCARLET_RETICLE_STYLE'] = $Settings.ReticleStyle
        $info.EnvironmentVariables['SCARLET_RETICLE_SIZE'] = [string]$Settings.ReticleSize
        $info.EnvironmentVariables['SCARLET_RETICLE_COLOR'] = $Settings.ReticleColor
    }
    $info.Arguments='-launch=pc -NotInstalled -unattended -nosplash {0} -ResX={1} -ResY={2} -UserDir="{3}" -abslog="{4}"' -f $window,$width,$height,$profile,$log
    $info.WorkingDirectory=$game
    $info.UseShellExecute=$false
    $info.CreateNoWindow=$true
    @{ Process=$info; Log=$log }
}
