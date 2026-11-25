param([string]$UpdateRequest)

function Get-HotdUpdateGame {
    @{ Repo='HOTD-Scarlet-Dawn-recomp'; Bundle='ScarletDawn-Local-Builder'; Launcher='Play Scarlet Dawn.exe' }
}

function ConvertTo-HotdVersion([string]$Tag) {
    if ($Tag -match '^v\d{1,5}\.\d{1,5}\.\d{1,5}$') { [version]$Tag.Substring(1) }
}

function Get-HotdPackageSHA256([string]$Path) {
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::OpenRead($Path)
        try { [BitConverter]::ToString($hash.ComputeHash($stream)).Replace('-', '') }
        finally { $stream.Dispose() }
    } finally { $hash.Dispose() }
}

function Get-HotdReleasePackage($Game, $Release) {
    if ($Release.tag_name -notmatch '^v\d{1,5}\.\d{1,5}\.\d{1,5}$' -or $Release.draft -or $Release.prerelease) {
        throw 'GitHub did not return a stable release.'
    }
    $name = "$($Game.Bundle)-$($Release.tag_name).zip"
    $assets = @($Release.assets | Where-Object name -CEQ $name)
    $url = "https://github.com/davidptrssvea/$($Game.Repo)/releases/download/$($Release.tag_name)/$name"
    if ($assets.Count -ne 1 -or $assets[0].browser_download_url -cne $url -or
        $assets[0].digest -notmatch '^sha256:[0-9a-f]{64}$' -or $assets[0].size -le 0 -or $assets[0].size -gt 50MB) {
        throw 'The release has no verifiable installer ZIP.'
    }
    @{ Tag=[string]$Release.tag_name; Url=$url; Hash=$assets[0].digest.Substring(7); Size=[long]$assets[0].size }
}

function Expand-HotdUpdateBundle([string]$Zip, [string]$Directory, [string]$Bundle) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Zip)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $total = 0L
    try {
        if ($archive.Entries.Count -gt 10000) { throw 'Too many files in the installer ZIP.' }
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName
            $parts = $name.TrimEnd('/').Split('/')
            if ($parts[0] -cne $Bundle -or $name -match '[\\:]' -or
                @($parts | Where-Object { !$_.Length -or $_ -match '[. ]$' -or $_ -match '^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(\.|$)' }).Count) {
                throw "Invalid path in installer ZIP: $name"
            }
            if (!$entry.Name) { continue }
            if ($parts.Count -lt 2 -or !$seen.Add($name)) { throw "Duplicate or invalid ZIP entry: $name" }
            $total += $entry.Length
            if ($total -gt 200MB) { throw 'The installer ZIP expands beyond the supported limit.' }
            $target = Join-Path $Directory $name
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target)
        }
    } finally { $archive.Dispose() }
    $root = Join-Path $Directory $Bundle
    if (!(Test-Path -LiteralPath (Join-Path $root 'setup.ps1') -PathType Leaf)) { throw 'Setup is missing from the ZIP.' }
    $root
}

function Replace-HotdUpdateFile([string]$Source, [string]$Target, [string]$Backup) {
    for ($attempt=0; ; $attempt++) {
        try {
            if ($Backup) { [IO.File]::Replace($Source,$Target,$Backup) }
            else { [IO.File]::Replace($Source,$Target,[NullString]::Value) }
            return
        } catch {
            $cause = $_.Exception.GetBaseException()
            $code = $cause.HResult.ToString('X8')
            # ReplaceFile can partially rename files on failure. Retry only with the original paths intact.
            if ($code -notin '80070020','80070021','80070497' -or $attempt -ge 10 -or
                ![IO.File]::Exists($Source) -or ![IO.File]::Exists($Target) -or
                ($Backup -and [IO.File]::Exists($Backup))) {
                throw [IO.IOException]::new("Could not replace '$Target' (0x$code). $($cause.Message)", $cause)
            }
            Start-Sleep -Milliseconds 250
        }
    }
}

function Install-HotdManagedFiles([string]$Stage, [string]$Root, [string]$Backup, [string[]]$Paths) {
    $applied = [Collections.Generic.List[object]]::new()
    try {
        foreach ($relative in $Paths) {
            $target = Join-Path $Root $relative
            $saved = Join-Path $Backup $relative
            $source = Join-Path $Stage $relative
            $directory = [IO.Path]::GetDirectoryName($target)
            for ($parent = $directory; $parent -and $parent -ne $Root; $parent = [IO.Path]::GetDirectoryName($parent)) {
                if ([IO.Directory]::Exists($parent) -and ([IO.File]::GetAttributes($parent) -band [IO.FileAttributes]::ReparsePoint)) {
                    throw "Move the linked installation folder before updating: $parent"
                }
            }
            [void][IO.Directory]::CreateDirectory($directory)
            $existing = [IO.File]::Exists($target)
            if ($existing) {
                if ([IO.File]::GetAttributes($target) -band [IO.FileAttributes]::ReparsePoint) {
                    throw "Move the linked program file before updating: $target"
                }
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($saved))
                try { Replace-HotdUpdateFile $source $target $saved }
                catch {
                    # Windows may have already renamed the original to the backup path.
                    if ([IO.File]::Exists($saved)) {
                        $applied.Add(@{ Target=$target; Saved=$saved; Existing=$true })
                    }
                    throw
                }
            } else { [IO.File]::Move($source, $target) }
            $applied.Add(@{ Target=$target; Saved=$saved; Existing=$existing })
        }
    } catch {
        $failure = $_
        $rollback = @()
        for ($i = $applied.Count-1; $i -ge 0; $i--) {
            $item = $applied[$i]
            try {
                if ($item.Existing) {
                    if ([IO.File]::Exists($item.Target)) {
                        $failed = $item.Saved + '.failed'
                        Replace-HotdUpdateFile $item.Saved $item.Target $failed
                        [IO.File]::Delete($failed)
                    }
                    else { [IO.File]::Move($item.Saved, $item.Target) }
                } else { [IO.File]::Delete($item.Target) }
            } catch { $rollback += $_.Exception.Message }
        }
        if ($rollback.Count) { throw "Update failed: $failure. Backup: $Backup. Restore errors: $($rollback -join ', ')" }
        throw $failure
    }
}

function Get-HotdPowerShell {
    Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell/v1.0/powershell.exe'
}

function Get-ScarletProgramFiles {
    @('Launcher.cs','Play Scarlet Dawn.exe','README.md','RELEASE-NOTES.md',
      'ScarletLightgun.dll','build-scarlet-lightgun-patch.py','scarlet-aim.S',
      'scarlet-aim-patch.json','scarlet-lightgun-patch.json','scarlet-lightgun.c',
      'scarlet-menu.ps1','scarlet-menu.xaml','scarlet-reticle.h',
      'scarlet-settings.ps1','scarlet-update.ps1','scarlet-version.txt')
}

function Confirm-ScarletProgramPackage([string]$Bundle, [string]$Tag) {
    $manifest=[IO.File]::ReadAllText((Join-Path $Bundle 'package-manifest.json')) | ConvertFrom-Json
    $required=@(Get-ScarletProgramFiles)
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($manifest.format -ne 1 -or $manifest.version -cne $Tag) { throw 'Unexpected installer manifest version.' }
    foreach ($entry in $manifest.files) {
        $name=[string]$entry.path
        if ($name -cnotin $required -or !$seen.Add($name) -or $entry.sha256 -notmatch '^[0-9a-f]{64}$') {
            throw 'Invalid installer manifest entry.'
        }
        $file=Join-Path $Bundle $name
        if (![IO.File]::Exists($file) -or (Get-HotdPackageSHA256 $file) -ne $entry.sha256) {
            throw "Installer file failed verification: $name"
        }
    }
    if ($seen.Count -ne $required.Count -or [IO.File]::ReadAllText((Join-Path $Bundle 'scarlet-version.txt')).Trim() -cne $Tag) {
        throw 'The installer is incomplete.'
    }
    $required
}

function Test-ScarletGameRunning([string]$App) {
    $bin=[IO.Path]::GetFullPath((Join-Path $App 'Game/Hodzero/Binaries/Win64'))
    $running=Get-Process -Name 'Hodzero-Win64-Shipping*' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and [IO.Path]::GetDirectoryName($_.Path) -eq $bin } |
        Select-Object -First 1
    $null -ne $running
}

function Set-HotdUpdateStatus([string]$Status,[string]$Text) {
    $pending=$Status+'.new'
    [IO.File]::WriteAllText($pending,$Text)
    if ([IO.File]::Exists($Status)) { Replace-HotdUpdateFile $pending $Status }
    else { [IO.File]::Move($pending,$Status) }
}

function Read-HotdUpdateStatus([string]$Status) {
    try {
        $share=[IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
        $stream=[IO.File]::Open($Status,'Open','Read',$share)
        try {
            $reader=[IO.StreamReader]::new($stream)
            try { return $reader.ReadToEnd() }
            finally { $reader.Dispose() }
        } finally { $stream.Dispose() }
    } catch [IO.IOException] {}
}

function Assert-HotdUpdatePending([Diagnostics.Process]$Owner,[string]$Cancel) {
    if ([IO.File]::Exists($Cancel) -or $Owner.HasExited) {
        throw [OperationCanceledException]::new('Update cancelled.')
    }
}

function Receive-HotdUpdateArchive([string]$Url,[string]$Zip,[Diagnostics.Process]$Owner,[string]$Cancel) {
    $client=[Net.WebClient]::new()
    try {
        $client.Headers['User-Agent']='HOTD-Local-Builder-Updater/1'
        $download=$client.DownloadFileTaskAsync([uri]$Url,$Zip)
        $elapsed=[Diagnostics.Stopwatch]::StartNew()
        while (!$download.IsCompleted) {
            Assert-HotdUpdatePending $Owner $Cancel
            if ($elapsed.Elapsed.TotalSeconds -ge 90) { throw 'Downloading the installer timed out.' }
            Start-Sleep -Milliseconds 200
        }
        $download.GetAwaiter().GetResult()
    } finally {
        if ($client.IsBusy) { $client.CancelAsync() }
        $client.Dispose()
    }
}

function Invoke-HotdUpdateWorker([string]$Request) {
    $ErrorActionPreference='Stop'
    $job=[IO.File]::ReadAllText($Request) | ConvertFrom-Json
    $work=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Request))
    $status=Join-Path $work 'status.txt'
    $cancel=Join-Path $work 'cancel.txt'
    $app=[IO.Path]::GetFullPath($job.App)
    $game=Get-HotdUpdateGame
    $lock=$owner=$null
    $ready=$false
    try {
        if ([IO.Path]::GetDirectoryName($work) -ne $app -or
            [IO.Path]::GetFileName($work) -notmatch '^\.scarlet-update-[0-9a-f]{10}$' -or
            ![IO.File]::Exists((Join-Path $app $game.Launcher))) {
            throw 'The current Scarlet Dawn installation could not be located.'
        }
        $owner=[Diagnostics.Process]::GetProcessById([int]$job.Owner)
        Assert-HotdUpdatePending $owner $cancel
        $local=Join-Path $app 'Local'
        [void][IO.Directory]::CreateDirectory($local)
        $lock=[IO.File]::Open((Join-Path $local 'Run.lock'),'OpenOrCreate','ReadWrite','None')
        if (Test-ScarletGameRunning $app) { throw 'Close the running game before updating.' }
        $installed=ConvertTo-HotdVersion ([IO.File]::ReadAllText((Join-Path $app 'scarlet-version.txt')).Trim())
        $tag=[string]$job.Package.Tag
        $candidate=ConvertTo-HotdVersion $tag
        $url="https://github.com/davidptrssvea/$($game.Repo)/releases/download/$tag/$($game.Bundle)-$tag.zip"
        if (!$candidate -or !$installed -or $candidate -le $installed -or $job.Package.Url -cne $url -or
            $job.Package.Hash -notmatch '^[0-9a-f]{64}$' -or $job.Package.Size -le 0 -or $job.Package.Size -gt 50MB) {
            throw 'This update does not match the installed version.'
        }
        [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
        $ProgressPreference='SilentlyContinue'
        $zip=Join-Path $work 'builder.zip'
        Set-HotdUpdateStatus $status 'Downloading the installer...'
        Receive-HotdUpdateArchive $url $zip $owner $cancel
        Assert-HotdUpdatePending $owner $cancel
        Set-HotdUpdateStatus $status 'Verifying the installer...'
        if ((Get-Item -LiteralPath $zip).Length -ne $job.Package.Size -or
            (Get-HotdPackageSHA256 $zip) -ne $job.Package.Hash) {
            throw 'Installer ZIP verification failed.'
        }
        Set-HotdUpdateStatus $status 'Extracting and checking the launcher files...'
        $bundle=Expand-HotdUpdateBundle $zip $work $game.Bundle
        $files=@(Confirm-ScarletProgramPackage $bundle $tag)
        $files=@($files | Where-Object { $_ -ne 'scarlet-version.txt' }) + 'scarlet-version.txt'
        Assert-HotdUpdatePending $owner $cancel
        Set-HotdUpdateStatus $status 'Ready'
        $ready = $true
        $handoff=[Diagnostics.Stopwatch]::StartNew()
        while (!$owner.WaitForExit(200)) {
            if ([IO.File]::Exists($cancel)) { throw [OperationCanceledException]::new('Update cancelled.') }
            if ($handoff.Elapsed.TotalSeconds -ge 60) { throw 'Close the game menu and retry the update.' }
        }
        if ([IO.File]::Exists($cancel) -or ![IO.File]::Exists((Join-Path $work 'apply.txt'))) {
            throw [OperationCanceledException]::new('Update cancelled.')
        }
        if (Test-ScarletGameRunning $app) { throw 'Close the running game before updating.' }
        Set-HotdUpdateStatus $status 'Installing the verified launcher files...'
        Install-HotdManagedFiles $bundle $app (Join-Path $work 'backup') $files
        try { Set-HotdUpdateStatus $status "Installed $tag" }
        catch [IO.IOException], [UnauthorizedAccessException] { Write-Verbose $_.Exception.Message }
        try { [IO.File]::Delete($zip) } catch {}
    } catch [OperationCanceledException] {
        $ready=$false
        Set-HotdUpdateStatus $status 'Cancelled'
    } catch {
        $failure = $_
        $message = $failure.Exception.Message + "`n`nUpdate files and logs: $work"
        try {
            [IO.File]::WriteAllText((Join-Path $work 'update-error.log'),
                $failure.Exception.ToString() + "`r`n" + $failure.ScriptStackTrace)
        } catch [IO.IOException], [UnauthorizedAccessException] { Write-Verbose $_.Exception.Message }
        try { Set-HotdUpdateStatus $status ('Error: '+$message) }
        catch [IO.IOException], [UnauthorizedAccessException] { Write-Verbose $_.Exception.Message }
        if ($ready) {
            Add-Type -AssemblyName PresentationFramework
            [void][Windows.MessageBox]::Show($message,'Scarlet Dawn update','OK','Error')
        }
    } finally {
        if ($lock) { $lock.Dispose() }
        if ($owner) { $owner.Dispose() }
    }
    if ($ready -and [IO.File]::Exists((Join-Path $app $game.Launcher))) {
        Start-Process -FilePath (Join-Path $app $game.Launcher) -WorkingDirectory $app -WindowStyle Hidden
    }
}

function Show-HotdUpdateDialog($Owner,$Dialog) {
    $wasTopmost=$Owner.Topmost
    $Owner.Topmost=$false
    $Dialog.Topmost=$false
    try { return $Dialog.ShowDialog() }
    finally {
        if ($wasTopmost -and $Owner.IsVisible -and $Owner.IsActive) { $Owner.Topmost=$true }
    }
}

function Show-HotdUpdateProgress($Window,[Diagnostics.Process]$Process,[string]$Work,[string]$Title,
                                 [scriptblock]$ShowDialog,[scriptblock]$ReadStatus) {
    $progress=[Windows.Window]::new()
    $progress.Owner=$Window; $progress.Title=$Title; $progress.Width=530
    $progress.SizeToContent='Height'
    $progress.WindowStartupLocation='CenterOwner'; $progress.ShowInTaskbar=$false; $progress.ResizeMode='NoResize'
    $stack=[Windows.Controls.StackPanel]::new(); $stack.Margin=[Windows.Thickness]::new(20)
    $label=[Windows.Controls.TextBlock]::new(); $label.Text='Downloading and verifying the installer...'; $label.TextWrapping='Wrap'
    $bar=[Windows.Controls.ProgressBar]::new(); $bar.Height=12; $bar.IsIndeterminate=$true; $bar.Margin=[Windows.Thickness]::new(0,14,0,0)
    $cancelButton=[Windows.Controls.Button]::new(); $cancelButton.Content='Cancel update'
    $cancelButton.MinWidth=110; $cancelButton.HorizontalAlignment='Right'; $cancelButton.Margin=[Windows.Thickness]::new(0,16,0,0)
    $elapsed=[Diagnostics.Stopwatch]::StartNew()
    $clock=[Windows.Controls.TextBlock]::new(); $clock.Text='Elapsed 00:00:00'; $clock.Margin=[Windows.Thickness]::new(0,8,0,0)
    [void]$stack.Children.Add($label); [void]$stack.Children.Add($bar)
    [void]$stack.Children.Add($clock); [void]$stack.Children.Add($cancelButton)
    $progress.Content=$stack
    $signal=@{ Close=$false; Install=$false; CancelRequested=$false; Error=$null }
    $cancel=Join-Path $work 'cancel.txt'
    $apply=Join-Path $work 'apply.txt'
    $requestCancel={
        if ($signal.CancelRequested -or $signal.Close) { return }
        try {
            [IO.File]::WriteAllText($cancel,'cancel')
            $signal.CancelRequested=$true
            $cancelButton.IsEnabled=$false
            $label.Text='Cancelling the update...'
        } catch { $label.Text='Could not request cancellation. Try again.' }
    }.GetNewClosure()
    $cancelButton.Add_Click({ & $requestCancel }.GetNewClosure())
    $progress.Add_Closing({
        param($sender,$e)
        if (!$signal.Close) { $e.Cancel=$true; & $requestCancel }
    }.GetNewClosure())
    $progress.Add_PreviewKeyDown({
        param($sender,$e)
        if ($e.Key -eq 'Escape') { $e.Handled=$true; & $requestCancel }
    }.GetNewClosure())
    $poll=[Windows.Threading.DispatcherTimer]::new(); $poll.Interval=[TimeSpan]::FromMilliseconds(400)
    $status=Join-Path $work 'status.txt'
    $poll.Add_Tick({
        $clock.Text='Elapsed '+$elapsed.Elapsed.ToString('hh\:mm\:ss')
        $text=& $ReadStatus $status
        if ($text -eq 'Ready' -and !$signal.CancelRequested) {
            try {
                [IO.File]::WriteAllText($apply,'apply')
                $signal.Install=$true; $signal.Close=$true
            } catch { $label.Text='Waiting to install. You can cancel the update.' }
        }
        elseif ($text -eq 'Cancelled') { $signal.Close=$true }
        elseif ($text -like 'Error:*') { $signal.Error=$text; $signal.Close=$true }
        elseif ($process.HasExited) { $signal.Error="The updater closed early. Update files and logs: $work"; $signal.Close=$true }
        elseif ($text -and !$signal.CancelRequested) { $label.Text=$text }
        if ($signal.Close) { $poll.Stop(); $progress.Close() }
    }.GetNewClosure())
    $poll.Start()
    try { [void](& $ShowDialog $Window $progress) } finally { $poll.Stop() }
    return $signal
}

function Add-HotdUpdater($Window, $MainPage, [string]$App) {
    $game = Get-HotdUpdateGame
    $versionFile = Join-Path $App 'scarlet-version.txt'
    $tag = try {
        if ([IO.File]::Exists($versionFile)) { [IO.File]::ReadAllText($versionFile).Trim() }
    } catch [IO.IOException], [UnauthorizedAccessException] {
        Write-Verbose $_.Exception.Message
    }
    $installed = ConvertTo-HotdVersion $tag
    $versionLabel = $Window.FindName('InstalledVersion')
    if ($versionLabel) {
        $versionLabel.Text = if ($installed) { "Installed version $tag" } else { 'Installed version unknown' }
        $versionLabel.Visibility = 'Visible'
    }
    $button = [Windows.Controls.Button]::new()
    $button.Name = 'Updates'
    $button.Content = if ($installed) { "Updates ($tag)" } else { 'Updates' }
    $button.Height = 34
    $button.FontSize = 15
    $button.Margin = [Windows.Thickness]::new(0,0,0,6)
    $quit = $Window.FindName('Quit')
    $at = if ($quit -and $MainPage.Children.Contains($quit)) { $MainPage.Children.IndexOf($quit) } else { $MainPage.Children.Count }
    $MainPage.Children.Insert($at, $button)

    Add-Type -AssemblyName System.Net.Http
    $client = [Net.Http.HttpClient]::new()
    $client.Timeout = [TimeSpan]::FromSeconds(12)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('HOTD-Local-Builder-Updater/1')
    $state = @{ Task=$null; Release=$null; Requested=$false }
    $uri = "https://api.github.com/repos/davidptrssvea/$($game.Repo)/releases/latest"
    $timer = [Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $parseVersion = ${function:ConvertTo-HotdVersion}
    $validatePackage = ${function:Get-HotdReleasePackage}
    $powerShell = Get-HotdPowerShell
    $showDialog=${function:Show-HotdUpdateDialog}
    $showProgress=${function:Show-HotdUpdateProgress}
    $readStatus=${function:Read-HotdUpdateStatus}
    $isGameRunning = ${function:Test-ScarletGameRunning}
    $showRelease = {
        if (!$state.Release) { return }
        if (& $isGameRunning $App) {
            [void][Windows.MessageBox]::Show($Window,'Close Scarlet Dawn before updating.','Scarlet Dawn update','OK','Information')
            return
        }
        $release = $state.Release
        $latest = & $parseVersion $release.tag_name
        $dialog = [Windows.Window]::new()
        $dialog.Owner=$Window; $dialog.Title='Scarlet Dawn updates'; $dialog.Width=620; $dialog.Height=510
        $dialog.WindowStartupLocation='CenterOwner'; $dialog.ShowInTaskbar=$false
        $panel=[Windows.Controls.DockPanel]::new(); $panel.Margin=[Windows.Thickness]::new(18)
        $heading=[Windows.Controls.TextBlock]::new()
        $heading.Text = "Installed: $(if ($installed) {$tag} else {'unknown'})     Latest: $($release.tag_name)"
        if ($installed -and $latest -gt $installed) {
            $heading.Text += "`nThe update keeps your game files and settings and reopens the menu."
        }
        $heading.Margin=[Windows.Thickness]::new(0,0,0,12)
        [Windows.Controls.DockPanel]::SetDock($heading,'Top'); [void]$panel.Children.Add($heading)
        $actions=[Windows.Controls.StackPanel]::new()
        $actions.Orientation='Horizontal'; $actions.HorizontalAlignment='Right'
        $actions.Margin=[Windows.Thickness]::new(0,12,0,0)
        [Windows.Controls.DockPanel]::SetDock($actions,'Bottom'); [void]$panel.Children.Add($actions)
        $close=[Windows.Controls.Button]::new(); $close.Content='Close'; $close.MinWidth=80; $close.IsCancel=$true
        if ($installed -and $latest -gt $installed) {
            $apply=[Windows.Controls.Button]::new(); $apply.Content='Download and install'; $apply.MinWidth=150
            $apply.Margin=[Windows.Thickness]::new(0,0,8,0)
            $apply.Add_Click({ $dialog.DialogResult=$true }.GetNewClosure())
            [void]$actions.Children.Add($apply)
        }
        [void]$actions.Children.Add($close)
        $notes=[Windows.Controls.TextBox]::new(); $notes.IsReadOnly=$true; $notes.TextWrapping='Wrap'
        $notes.VerticalScrollBarVisibility='Auto'; $notes.Text=[string]$release.body
        [void]$panel.Children.Add($notes); $dialog.Content=$panel
        if ((& $showDialog $Window $dialog) -ne $true) { return }
        try {
            $package = & $validatePackage $game $release
            $root = $App
            $work = Join-Path $root ('.scarlet-update-'+[guid]::NewGuid().ToString('N').Substring(0,10))
            [void][IO.Directory]::CreateDirectory($work)
            $script = Join-Path $work 'scarlet-update.ps1'
            [IO.File]::Copy((Join-Path $App 'scarlet-update.ps1'), $script)
            $request = Join-Path $work 'request.json'
            [IO.File]::WriteAllText($request, (@{ App=$App; Owner=$PID; Package=$package } | ConvertTo-Json -Compress))
            $info=[Diagnostics.ProcessStartInfo]::new()
            $info.FileName=$powerShell; $info.Arguments='-NoProfile -ExecutionPolicy Bypass -STA -File "{0}" -UpdateRequest "{1}"' -f $script,$request
            $info.WorkingDirectory=$work; $info.UseShellExecute=$false; $info.CreateNoWindow=$true
            $process=[Diagnostics.Process]::Start($info)
            try { $signal=& $showProgress $Window $process $work 'Installing Scarlet Dawn update' $showDialog $readStatus }
            finally { $process.Dispose() }
            if ($signal.Install) { $Window.Close() }
            elseif ($signal.Error) { [void][Windows.MessageBox]::Show($Window,$signal.Error,'Scarlet Dawn update','OK','Error') }
        } catch { [void][Windows.MessageBox]::Show($Window,$_.Exception.Message,'Scarlet Dawn update','OK','Error') }
    }.GetNewClosure()
    $check = {
        if ($state.Task) { return }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $state.Task=$client.GetStringAsync($uri)
        $button.Content='Checking for updates...'
        $timer.Start()
    }.GetNewClosure()
    $timer.Add_Tick({
        if (!$state.Task.IsCompleted) { return }
        $timer.Stop()
        try {
            $release=$state.Task.GetAwaiter().GetResult() | ConvertFrom-Json
            [void](& $validatePackage $game $release)
            $state.Release=$release
            $button.Content=if ($installed -and (& $parseVersion $release.tag_name) -gt $installed) {
                "Update available ($($release.tag_name))"
            } elseif ($installed) { "Updates ($tag)" } else { "Updates ($($release.tag_name))" }
        } catch { $button.Content='Updates unavailable. Retry' }
        $state.Task=$null
        if ($state.Requested -and $state.Release) { $state.Requested=$false; & $showRelease }
    }.GetNewClosure())
    $button.Add_Click({ if ($state.Release) { & $showRelease } else { $state.Requested=$true; & $check } }.GetNewClosure())
    $Window.Add_ContentRendered({ & $check }.GetNewClosure())
    $Window.Add_Closed({ $timer.Stop(); $client.Dispose() }.GetNewClosure())
}

if ($UpdateRequest) { Invoke-HotdUpdateWorker $UpdateRequest }
