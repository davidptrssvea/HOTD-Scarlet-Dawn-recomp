param([string]$Case,[int]$WatchOwner,[string]$Download)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$updater=Join-Path $root 'ui/hotd-update.ps1'
if (![IO.File]::Exists($updater)) { $updater=Join-Path $root 'scarlet-update.ps1' }
. $updater

if ($Case) {
    $owner=[Diagnostics.Process]::GetProcessById($WatchOwner)
    try {
        $cancel=Join-Path $Case 'cancel.txt'
        if ($Download) {
            Receive-HotdUpdateArchive $Download (Join-Path $Case 'installer.zip') $owner $cancel
        } else {
            Invoke-HotdStagedBuild (Join-Path $Case 'test-setup.ps1') $Case $Case $true $Case $owner $cancel
        }
        exit 0
    } catch [OperationCanceledException] {
        exit 42
    } finally { $owner.Dispose() }
}

function Assert($Condition,[string]$Message) { if (!$Condition) { throw $Message } }
function Wait-For([scriptblock]$Check,[string]$Failure) {
    $age=[Diagnostics.Stopwatch]::StartNew()
    while ($age.Elapsed.TotalSeconds -lt 12) {
        if (& $Check) { return }
        Start-Sleep -Milliseconds 80
    }
    throw $Failure
}
function Start-TestWorker([string]$Fixture,[string]$Url) {
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=Get-HotdPowerShell
    $info.Arguments='-NoProfile -ExecutionPolicy Bypass -STA -File "{0}" -Case "{1}" -WatchOwner {2}' -f $PSCommandPath,$Fixture,$PID
    if ($Url) { $info.Arguments+=' -Download "'+$Url+'"' }
    $info.UseShellExecute=$false
    $info.CreateNoWindow=$true
    return [Diagnostics.Process]::Start($info)
}

$base=Join-Path ([IO.Path]::GetTempPath()) ('HOTD updater check '+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($base)

Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
foreach ($mode in 'Button','Close','Ready') {
    $fixture=Join-Path $base $mode
    [void][IO.Directory]::CreateDirectory($fixture)
    $status=Join-Path $fixture 'status.txt'
    Set-HotdUpdateStatus $status 'Verifying the installer...'
    Set-HotdUpdateStatus $status 'Installing build tools...'
    $ownerWindow=[Windows.Window]::new()
    $ownerWindow.Topmost=$true
    $ownerWindow.ShowActivated=$false
    $ownerWindow.Left=-10000; $ownerWindow.Top=-10000
    $ownerWindow.Show()
    $dialogCheck=${function:Show-HotdUpdateDialog}
    $observed=@{Error=$null;Shown=$false}
    $checkDialog={
        param($Parent,$Dialog)
        $check=[Windows.Threading.DispatcherTimer]::new()
        $check.Interval=[TimeSpan]::FromMilliseconds(1000)
        $check.Add_Tick({
            $check.Stop()
            try {
                Assert (!$Parent.Topmost -and !$Dialog.Topmost) 'An updater window stayed above other apps.'
                $elements=$Dialog.Content.Children
                Assert ($elements[0].Text -eq 'Installing build tools...') 'Live progress did not reach the dialog.'
                Assert ($elements[2].Text -like 'Elapsed 00:00:0?') 'Elapsed time did not reach the dialog.'
                if ($mode -eq 'Ready') {
                    Set-HotdUpdateStatus $status 'Ready'
                    $observed.Shown=$true
                    return
                }
                if ($mode -eq 'Close') { $Dialog.Close() }
                else { $elements[3].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)) }
                Assert ([IO.File]::Exists((Join-Path $fixture 'cancel.txt'))) "$mode did not request cancellation."
                $observed.Shown=$true
            } catch { $observed.Error=$_ }
            finally { if ($mode -ne 'Ready' -or $observed.Error) { Set-HotdUpdateStatus $status 'Cancelled' } }
        }.GetNewClosure())
        $check.Start()
        try { & $dialogCheck $Parent $Dialog }
        finally { $check.Stop() }
    }.GetNewClosure()
    try {
        $current=[Diagnostics.Process]::GetCurrentProcess()
        $signal=Show-HotdUpdateProgress $ownerWindow $current $fixture 'Updater test' $checkDialog ${function:Read-HotdUpdateStatus}
        if ($observed.Error) { throw $observed.Error }
        if ($mode -eq 'Ready') {
            Assert ($observed.Shown -and $signal.Install -and [IO.File]::Exists((Join-Path $fixture 'apply.txt'))) 'The installed launcher did not acknowledge the staged update.'
        } else {
            Assert ($observed.Shown -and $signal.CancelRequested -and $signal.Close -and !$signal.Install) 'Cancellation did not close the progress dialog normally.'
        }
    } finally { $current.Dispose(); $ownerWindow.Close() }
}
Write-Host 'PASS: progress and elapsed time are visible, both windows are unpinned and both Cancel and Close abort the update.'

$downloadWork=Join-Path $base 'download'
[void][IO.Directory]::CreateDirectory($downloadWork)
$server=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
$server.Start()
$client=$worker=$null
try {
    $accept=$server.AcceptTcpClientAsync()
    $worker=Start-TestWorker $downloadWork ("http://127.0.0.1:"+$server.LocalEndpoint.Port+'/installer.zip')
    Assert ($accept.Wait(10000)) 'The download worker did not connect.'
    $client=$accept.Result
    $stream=$client.GetStream()
    $response=[Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Length: 999999`r`nConnection: close`r`n`r`nx")
    $stream.Write($response,0,$response.Length)
    [IO.File]::WriteAllText((Join-Path $downloadWork 'cancel.txt'),'cancel')
    Assert ($worker.WaitForExit(8000) -and $worker.ExitCode -eq 42) 'A delayed download could not be cancelled promptly.'
} finally {
    if ($client) { $client.Dispose() }
    $server.Stop()
    if ($worker) { if (!$worker.HasExited) { $worker.Kill() }; $worker.Dispose() }
}
Write-Host 'PASS: the updater cancels a download that is still in progress.'

if (Get-Command Invoke-HotdStagedBuild -ErrorAction SilentlyContinue) {
    $setup=@'
param([string]$DumpPath,[string]$InstallDir,[switch]$StageUpdate,[switch]$OpenXR)
$ErrorActionPreference='Stop'
if (!$StageUpdate -or !$OpenXR -or $DumpPath -ne $InstallDir) { exit 19 }
$powerShell=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell/v1.0/powershell.exe'
$child=Start-Process -FilePath $powerShell -ArgumentList '-NoProfile -Command "Start-Sleep -Seconds 90"' -WindowStyle Hidden -PassThru
[IO.File]::WriteAllText((Join-Path $InstallDir 'ids'),("$PID "+$child.Id))
Write-Output '+ C:/Tools/cmake.exe --build D:/Verify this/build-openxr --target hotd4 --parallel 1'
Write-Host '[16/115] Building C object example.obj'
Start-Sleep -Seconds 90
'@
    foreach ($mode in 'cancel-build','kill-worker') {
        $fixture=Join-Path $base $mode
        [void][IO.Directory]::CreateDirectory($fixture)
        [IO.File]::WriteAllText((Join-Path $fixture 'test-setup.ps1'),$setup)
        $worker=Start-TestWorker $fixture
        $children=@()
        try {
            $status=Join-Path $fixture 'status.txt'
            $ids=Join-Path $fixture 'ids'
            Wait-For { [IO.File]::Exists($ids) -and (Read-HotdUpdateStatus $status) -eq 'Compiling OpenXR (16/115)' } 'Live compiler progress did not appear.'
            $children=@([IO.File]::ReadAllText($ids).Split(' ') | ForEach-Object {[int]$_})
            if ($mode -eq 'kill-worker') { $worker.Kill() }
            else { [IO.File]::WriteAllText((Join-Path $fixture 'cancel.txt'),'cancel') }
            Assert ($worker.WaitForExit(8000)) 'The update worker did not stop.'
            if ($mode -eq 'cancel-build') { Assert ($worker.ExitCode -eq 42) 'The build did not report cancellation.' }
            Wait-For { !(Get-Process -Id $children -ErrorAction SilentlyContinue) } 'Setup or one of its children was left running.'
            Assert ([IO.File]::ReadAllText((Join-Path $fixture 'setup.log')) -match '\[16/115\]') 'A cancelled run lost its build output.'
        } finally {
            if (!$worker.HasExited) { $worker.Kill() }
            $worker.Dispose()
            foreach ($id in $children) { Stop-Process -Id $id -ErrorAction SilentlyContinue }
        }
    }
    Write-Host 'PASS: OpenXR progress appears during compilation, logs survive cancellation and the process tree stops on Cancel or worker termination.'
    $fixture=Join-Path $base 'successful-build'
    [void][IO.Directory]::CreateDirectory($fixture)
    $quickSetup=@'
param([string]$DumpPath,[string]$InstallDir,[switch]$StageUpdate,[switch]$OpenXR)
if (!$StageUpdate -or !$OpenXR -or $DumpPath -ne $InstallDir) { exit 19 }
[IO.File]::WriteAllText((Join-Path $InstallDir 'staged'), 'built')
Write-Host 'Build complete.'
'@
    [IO.File]::WriteAllText((Join-Path $fixture 'test-setup.ps1'),$quickSetup)
    $worker=Start-TestWorker $fixture
    try {
        Assert ($worker.WaitForExit(8000) -and $worker.ExitCode -eq 0) 'A successful staged build did not exit normally.'
        Assert ([IO.File]::Exists((Join-Path $fixture 'staged'))) 'Setup did not receive its original stage and OpenXR switches.'
        Assert ([IO.File]::ReadAllText((Join-Path $fixture 'setup.log')) -match 'Build complete') 'Completed build output was lost.'
    } finally {
        if (!$worker.HasExited) { $worker.Kill() }
        $worker.Dispose()
    }
    Write-Host 'PASS: successful builds finish normally with the original Setup arguments.'
}
