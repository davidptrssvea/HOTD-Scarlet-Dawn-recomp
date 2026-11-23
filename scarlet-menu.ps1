[CmdletBinding()]
param([switch]$ValidateOnly, [switch]$PrepareOnly,
      [ValidateSet('Menu','Settings','Play')][string]$StartMode='Menu')
# HOTD Game Library

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scarlet-settings.ps1')
$root = $PSScriptRoot

if ($ValidateOnly -or $PrepareOnly) {
    $current = Get-ScarletSettings $root
    if ($PrepareOnly) {
        $launch = New-ScarletStartInfo $root $current
        [pscustomobject]@{
            FileName=$launch.Process.FileName
            Arguments=$launch.Process.Arguments
            WorkingDirectory=$launch.Process.WorkingDirectory
            Log=$launch.Log
        } | ConvertTo-Json
    } else {
        $current | ConvertTo-Json
    }
    return
}
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Enumerate mouse-class Raw Input devices; stable device paths are the saved IDs.
if (-not ('ScarletRawDevices' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class ScarletRawDevices {
    [StructLayout(LayoutKind.Sequential)] struct Device { public IntPtr Handle; public uint Type; }
    [DllImport("user32.dll")] static extern uint GetRawInputDeviceList([Out] Device[] devices, ref uint count, uint size);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern uint GetRawInputDeviceInfo(IntPtr device, uint command, StringBuilder data, ref uint size);
    public static string[] Paths() {
        uint count=0, size=(uint)Marshal.SizeOf(typeof(Device));
        if(GetRawInputDeviceList(null,ref count,size)==uint.MaxValue) throw new System.ComponentModel.Win32Exception();
        var devices=new Device[count];
        uint got=GetRawInputDeviceList(devices,ref count,size);
        if(got==uint.MaxValue) throw new System.ComponentModel.Win32Exception();
        var paths=new List<string>();
        for(int i=0;i<got;i++) if(devices[i].Type==0) {
            uint chars=0; GetRawInputDeviceInfo(devices[i].Handle,0x20000007,null,ref chars);
            if(chars==0)continue;
            var path=new StringBuilder((int)chars+1);chars++;
            if(GetRawInputDeviceInfo(devices[i].Handle,0x20000007,path,ref chars)!=uint.MaxValue)paths.Add(path.ToString());
        }
        return paths.ToArray();
    }
}
'@
}
function Get-ScarletRawDevices {
    $index=0
    foreach($path in [ScarletRawDevices]::Paths()) {
        $index++
        $parts=$path -split '#'
        $description='Mouse / Lightgun'
        if($parts.Length -ge 3) {
            $key='Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\'+($parts[0] -replace '^\\\?\?\\','' -replace '^\\\\\?\\','')+'\'+$parts[1]+'\'+$parts[2]
            $value=Get-ItemProperty -LiteralPath $key -Name DeviceDesc -ErrorAction SilentlyContinue
            if($value.DeviceDesc){$description=($value.DeviceDesc -split ';')[-1]}
        }
        [pscustomobject]@{ Path=$path; Name="Device $index - $description" }
    }
}
[void][IO.Directory]::CreateDirectory((Join-Path $root 'Local'))

[xml]$xaml = [IO.File]::ReadAllText((Join-Path $root 'scarlet-menu.xaml'))
$window = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
$controls = @{}
foreach ($node in $xaml.SelectNodes('//*[@Name]')) {
    $controls[[string]$node.Name] = $window.FindName([string]$node.Name)
}
$settings = Get-ScarletSettings $root
$presets = Get-ScarletPresets
$controls.Resolution.ItemsSource = @('960x540','1280x720','1600x900','1920x1080','2560x1440','3840x2160')
$controls.Scale.ItemsSource = @(50,67,75,85,100)
$controls.Quality.ItemsSource = @('Low','Medium','High','Epic')
$controls.Display.ItemsSource = @('Windowed','Borderless')
$controls.Preset.ItemsSource = @($presets.Keys)
$controls.Preset.SelectedIndex = 0

$fillCombo = {
    param($Control, $Choices)
    $Control.Items.Clear()
    foreach ($choice in $Choices) {
        $item = [Windows.Controls.ComboBoxItem]::new()
        $item.Tag=$choice.Code
        $item.Content=$choice.Label
        [void]$Control.Items.Add($item)
    }
}
$selectCombo = {
    param($Control, $Code)
    foreach ($item in $Control.Items) {
        if ($item.Tag -eq $Code) { $Control.SelectedItem=$item; return }
    }
}
$inputModes = [ordered]@{ Mouse='Mouse'; Sinden='Sinden (Windows mouse)'; RawInput='Lightgun (Raw Input)' }
& $fillCombo $controls.InputMode @($inputModes.Keys | ForEach-Object { @{Code=$_;Label=$inputModes[$_]} })
& $fillCombo $controls.BorderWidth @(
    @{Code=0;Label='Off'}
    @{Code=25;Label='Extra Thin (0.75%)'}
    @{Code=50;Label='Thin (1.5%)'}
    @{Code=75;Label='Medium (2.25%)'}
    @{Code=100;Label='Original (3%)'}
)
$reticles = Get-ScarletReticleStyles
$reticleColors = Get-ScarletReticleColors
& $fillCombo $controls.ReticleStyle @($reticles.Keys | ForEach-Object { @{Code=$_;Label=$reticles[$_]} })
& $fillCombo $controls.ReticleColor @($reticleColors.Keys | ForEach-Object { @{Code=$_;Label=$_} })
& $fillCombo $controls.ReticleSize @(@{Code=1;Label='Small'},@{Code=2;Label='Medium'},@{Code=3;Label='Large'})
$reticleGeometry = @{
    Dot='M 3,1 A 2,2 0 1 0 3,5 A 2,2 0 1 0 3,1 Z'
    Cross='M 0,12 L 24,12 M 12,0 L 12,24'
    Ring='M 12,0 A 12,12 0 1 0 12,24 A 12,12 0 1 0 12,0 Z'
    RingDot='M 12,0 A 12,12 0 1 0 12,24 A 12,12 0 1 0 12,0 Z M 12,10 A 2,2 0 1 0 12,14 A 2,2 0 1 0 12,10 Z'
    OpenCross='M 0,12 L 8,12 M 16,12 L 24,12 M 12,0 L 12,8 M 12,16 L 12,24'
}
$updateReticlePreview = {
    $style=$controls.ReticleStyle.SelectedItem.Tag
    $show=$reticleGeometry.ContainsKey([string]$style)
    $controls.ReticleSize.IsEnabled=$controls.ReticleColor.IsEnabled=$show
    $controls.ReticlePreview.Visibility=if ($show) { 'Visible' } else { 'Collapsed' }
    $controls.ReticlePreviewText.Text=if (!$show) { [string]$style } else { '' }
    if (!$show) { return }
    $size=@(16,24,34)[[Math]::Max(0,[int]$controls.ReticleSize.SelectedItem.Tag-1)]
    $color=$controls.ReticleColor.SelectedItem.Tag
    if (!$color) { $color='White' }
    $brush=[Windows.Media.BrushConverter]::new().ConvertFromString($reticleColors[$color])
    $controls.ReticlePreview.Width=$controls.ReticlePreview.Height=if ($style -eq 'Dot') { [Math]::Max(4,$size/4) } else { $size }
    $controls.ReticlePreview.Data=[Windows.Media.Geometry]::Parse($reticleGeometry[$style])
    $controls.ReticlePreview.Stroke=$brush
    $controls.ReticlePreview.Fill=if ($style -eq 'Dot') { $brush } else { $null }
}
foreach ($field in 'ReticleStyle','ReticleSize','ReticleColor') {
    $controls[$field].Add_SelectionChanged({ & $updateReticlePreview })
}
$advanced = Get-ScarletAdvancedOptions
$advancedDefaults = Get-ScarletAdvancedDefaults
foreach ($field in $advanced.Keys) {
    $choices = $advanced[$field]
    & $fillCombo $controls["Adv$field"] @($choices.Keys | ForEach-Object { @{Code=[int]$_;Label=$choices[$_]} })
}
$loadGunDevices = {
    $devices = @(
        [pscustomobject]@{Path='auto';Name='Auto (absolute lightgun)'}
        [pscustomobject]@{Path='disabled';Name='Disabled'}
    )
    try { $devices += @(Get-ScarletRawDevices) }
    catch { $controls.Status.Text='Could not list Raw Input devices.' }
    foreach ($saved in $settings.Gun1,$settings.Gun2) {
        if ($saved -notin $devices.Path) {
            $devices += [pscustomobject]@{Path=$saved;Name='Saved device (disconnected)'}
        }
    }
    $choices = @($devices | ForEach-Object { @{Code=$_.Path;Label=$_.Name} })
    & $fillCombo $controls.Gun1 $choices
    & $fillCombo $controls.Gun2 $choices
    & $selectCombo $controls.Gun1 $settings.Gun1
    & $selectCombo $controls.Gun2 $settings.Gun2
}
$controls.InputMode.Add_SelectionChanged({
    $mode=$controls.InputMode.SelectedItem.Tag
    $controls.GunPanel.Visibility=if ($mode -eq 'RawInput') { 'Visible' } else { 'Collapsed' }
    $controls.LightgunPanel.Visibility=if ($mode -and $mode -ne 'Mouse') { 'Visible' } else { 'Collapsed' }
    $controls.SindenSwitchWeaponOnReload.Visibility=if ($mode -eq 'Sinden') { 'Visible' } else { 'Collapsed' }
    $controls.ModeGuide.Text = if ($mode -eq 'RawInput') {
        'Auto assigns absolute guns in first-use order. For two players, select a second device and use 2 to join.'
    } elseif ($mode -eq 'Sinden') {
        'Start the Sinden software and calibrate with the border visible. Use 1 or Enter to join.'
    } else { '' }
})

$showPage = {
    param([string]$Name)
    foreach ($page in 'Main','Settings','Advanced','Input') {
        $controls[$page+'Page'].Visibility = if ($Name -eq $page) { 'Visible' } else { 'Collapsed' }
    }
    $controls.Status.Text = ''
}
$loadSettings = {
    $controls.Resolution.SelectedItem=$settings.Resolution
    $controls.Scale.SelectedItem=[int]$settings.Scale
    $controls.Quality.SelectedIndex=[int]$settings.Quality
    $controls.Display.SelectedItem=$settings.Display
    $controls.VSync.IsChecked=$settings.VSync
    $controls.AudioFix.IsChecked=$settings.StereoFix
    & $selectCombo $controls.InputMode $settings.InputMode
    & $selectCombo $controls.BorderWidth ([int]$settings.BorderWidth)
    $controls.OffscreenReload.IsChecked=$settings.OffscreenReload
    $controls.SindenSwitchWeaponOnReload.IsChecked=$settings.SindenSwitchWeaponOnReload
    & $selectCombo $controls.ReticleSize $settings.ReticleSize
    & $selectCombo $controls.ReticleColor $settings.ReticleColor
    & $selectCombo $controls.ReticleStyle $settings.ReticleStyle
    & $updateReticlePreview
    & $loadGunDevices
}
$controls.Options.Add_Click({ & $loadSettings; & $showPage 'Settings' })
$controls.AdvancedOpen.Add_Click({
    foreach ($field in $advanced.Keys) { & $selectCombo $controls["Adv$field"] $settings[$field] }
    & $showPage 'Advanced'
    [void]$controls.AdvFrameCap.Focus()
})
$controls.AdvancedBack.Add_Click({
    & $showPage 'Settings'
    [void]$controls.AdvancedOpen.Focus()
})
$controls.AdvancedReset.Add_Click({
    foreach ($field in $advanced.Keys) { & $selectCombo $controls["Adv$field"] $advancedDefaults[$field] }
})
$controls.AdvancedSave.Add_Click({
    try {
        $next=$settings.Clone()
        foreach ($field in $advanced.Keys) { $next[$field]=[int]$controls["Adv$field"].SelectedItem.Tag }
        Save-ScarletSettings $root $next
        foreach ($field in $advanced.Keys) { $settings[$field]=$next[$field] }
        & $showPage 'Settings'
        $controls.Status.Text='Advanced graphics saved'
        [void]$controls.AdvancedOpen.Focus()
    } catch { $controls.Status.Text=$_.Exception.Message }
})
$controls.Cancel.Add_Click({ & $showPage 'Main'; [void]$controls.Options.Focus() })
$controls.InputTest.Add_Click({ & $showPage 'Input' })
$controls.InputBack.Add_Click({ & $showPage 'Main'; [void]$controls.InputTest.Focus() })
$controls.Quit.Add_Click({ $window.Close() })
$controls.ApplyPreset.Add_Click({
    $preset = $presets[[string]$controls.Preset.SelectedItem]
    $controls.Resolution.SelectedItem=$preset.Resolution
    $controls.Scale.SelectedItem=[int]$preset.Scale
    $controls.Quality.SelectedIndex=[int]$preset.Quality
    $controls.VSync.IsChecked=$preset.VSync
})
$controls.Save.Add_Click({
    try {
        $changes = @{
            Resolution=[string]$controls.Resolution.SelectedItem
            Scale=[int]$controls.Scale.SelectedItem
            Quality=[int]$controls.Quality.SelectedIndex
            Display=[string]$controls.Display.SelectedItem
            VSync=[bool]$controls.VSync.IsChecked
            StereoFix=[bool]$controls.AudioFix.IsChecked
            InputMode=[string]$controls.InputMode.SelectedItem.Tag
            BorderWidth=[int]$controls.BorderWidth.SelectedItem.Tag
            OffscreenReload=[bool]$controls.OffscreenReload.IsChecked
            SindenSwitchWeaponOnReload=[bool]$controls.SindenSwitchWeaponOnReload.IsChecked
            Gun1=[string]$controls.Gun1.SelectedItem.Tag
            Gun2=[string]$controls.Gun2.SelectedItem.Tag
            ReticleStyle=[string]$controls.ReticleStyle.SelectedItem.Tag
            ReticleColor=[string]$controls.ReticleColor.SelectedItem.Tag
            ReticleSize=[int]$controls.ReticleSize.SelectedItem.Tag
        }
        $next=$settings.Clone()
        foreach ($key in $changes.Keys) { $next[$key]=$changes[$key] }
        Save-ScarletSettings $root $next
        foreach ($key in $next.Keys) { $settings[$key]=$next[$key] }
        & $showPage 'Main'
        $controls.Status.Text = 'Settings saved'
        [void]$controls.Options.Focus()
    } catch { $controls.Status.Text=$_.Exception.Message }
})
$controls.Target.Add_MouseMove({
    param($sender,$eventArgs)
    $position=$eventArgs.GetPosition($sender)
    $controls.InputStatus.Text='Pointer {0:0}, {1:0}' -f $position.X,$position.Y
})
$controls.Target.Add_MouseDown({
    param($sender,$eventArgs)
    $position=$eventArgs.GetPosition($sender)
    $controls.InputStatus.Text='{0} button at {1:0}, {2:0}' -f $eventArgs.ChangedButton,$position.X,$position.Y
    [Windows.Controls.Canvas]::SetLeft($controls.Dot,$position.X-6)
    [Windows.Controls.Canvas]::SetTop($controls.Dot,$position.Y-6)
    $controls.Dot.Visibility='Visible'
})
$run = @{ Child=$null; Lock=$null; StartFromLibrary=($StartMode -eq "Play") }
$timer = [Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds(250)
$timer.Add_Tick({
    if (!$run.Child.HasExited) { return }
    $timer.Stop()
    $code=$run.Child.ExitCode
    $run.Child.Dispose()
    $run.Lock.Dispose()
    $run.Child=$run.Lock=$null
    $controls.Play.IsEnabled=$controls.Options.IsEnabled=$controls.GameLibrary.IsEnabled=$true
    $window.WindowState='Normal'
    [void]$window.Activate()
    $controls.Status.Text = if ($code) { "Game exited with code $code. See Local/Logs." } else { 'Game closed' }
})
$controls.Play.Add_Click({
    if ($run.Child) { return }
    try {
        $run.Lock = [IO.File]::Open((Join-Path $root 'Local/Run.lock'),'OpenOrCreate','ReadWrite','None')
        $launch = New-ScarletStartInfo $root $settings
        $run.Child = [Diagnostics.Process]::Start($launch.Process)
        $controls.Play.IsEnabled=$controls.Options.IsEnabled=$controls.GameLibrary.IsEnabled=$false
        $window.WindowState='Minimized'
        $timer.Start()
    } catch {
        if ($run.Lock) { $run.Lock.Dispose(); $run.Lock=$null }
        $controls.Status.Text = $_.Exception.Message
    }
})
$window.Add_Closing({
    param($sender,$eventArgs)
    if ($run.Child) {
        $eventArgs.Cancel=$true
        $controls.Status.Text='Close Scarlet Dawn before exiting the launcher.'
    }
})
$window.Add_PreviewKeyDown({
    param($sender,$eventArgs)
    if ($eventArgs.Key -ne 'Escape' -or @($controls.Values | Where-Object {
        $_ -is [Windows.Controls.ComboBox] -and $_.IsDropDownOpen
    }).Count) { return }
    if ($controls.MainPage.IsVisible) { $window.Close() }
    elseif ($controls.AdvancedPage.IsVisible) { & $showPage 'Settings'; [void]$controls.AdvancedOpen.Focus() }
    else { & $showPage 'Main' }
    $eventArgs.Handled=$true
})
. (Join-Path $root 'scarlet-update.ps1')
$controls.GameLibrary=Add-Hotd4GameSwitcher $window $controls.MainPage $root Scarlet $controls.Play $controls.Options
Add-HotdUpdater $window $controls.MainPage $root
$window.Add_ContentRendered({
    if ($StartMode -eq 'Settings') { & $loadSettings; & $showPage 'Settings'; [void]$controls.Resolution.Focus() }
    elseif ($run.StartFromLibrary) {
        $run.StartFromLibrary=$false
        $controls.Play.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
    } else { [void]$controls.Play.Focus() }
})
[void]$window.ShowDialog()
