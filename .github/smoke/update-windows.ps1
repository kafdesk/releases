# Self-update test on Windows (NSIS). Usage:
#   update-windows.ps1 -Mode probe   -Setup <setup.exe>
#   update-windows.ps1 -Mode install -Setup <old setup.exe> -Want <new version>
# Installs into a folder with Cyrillic letters and downloads into a Cyrillic
# temp folder (paths must stay Unicode end to end), starts KafDesk with
# update checks allowed, clicks "Install update" through UI Automation (as
# Narrator would), then checks that the helper ran the new installer into
# the same folder and started KafDesk again.
param([string]$Mode, [string]$Setup, [string]$Want = "")
$ErrorActionPreference = "Stop"
$dir = "C:\Программы\KafDesk"
$tmp = "C:\Временные"
New-Item -ItemType Directory -Force $tmp | Out-Null

$p = Start-Process $Setup -ArgumentList '/S', "/D=$dir" -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "installer exit code $($p.ExitCode)" }
$exe = Join-Path $dir "KafDesk.exe"
if (-not (Test-Path $exe)) { throw "KafDesk.exe not in $dir" }
# The installer records its version in the uninstall entry; the exe's own
# version resource is printed for the record.
function Get-Installed {
  foreach ($k in 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AKStudioKafDesk',
                 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AKStudioKafDesk') {
    $v = (Get-ItemProperty $k -ErrorAction SilentlyContinue).DisplayVersion
    if ($v) { return $v }
  }
  return ""
}
$before = Get-Installed
$hash0 = (Get-FileHash $exe).Hash
$vi = (Get-Item $exe).VersionInfo
"installed $before in $dir (exe ProductVersion '$($vi.ProductVersion)', FileVersion '$($vi.FileVersion)')"

$app = Join-Path $env:APPDATA "KafDesk"
New-Item -ItemType Directory -Force $app | Out-Null
'{"checkUpdates": true, "autoDownloadUpdates": true}' | Set-Content -Encoding utf8NoBOM (Join-Path $app "settings.json")

$env:TEMP = $tmp
$env:TMP = $tmp
$kd = Start-Process $exe -PassThru
python "$PSScriptRoot\update-driver.py" uia $Mode
$driver = $LASTEXITCODE
function Show-Logs {
  Get-ChildItem -Recurse $app -Filter *.log -ErrorAction SilentlyContinue | ForEach-Object { "== $($_.FullName)"; Get-Content $_.FullName -Tail 60 }
  Get-ChildItem -Recurse $dir -Filter *.log -ErrorAction SilentlyContinue | ForEach-Object { "== $($_.FullName)"; Get-Content $_.FullName -Tail 60 }
}
if ($driver -ne 0) {
  Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe' or Name='KafDesk.exe'" | Select-Object -First 3 | ForEach-Object { "$($_.Name): $($_.CommandLine)" }
  Show-Logs; throw "driver failed"
}
if ($Mode -eq "probe") { Stop-Process -Id $kd.Id -Force; exit 0 }

# KafDesk quits, the helper runs the new setup into $dir and starts it again.
$deadline = (Get-Date).AddMinutes(5)
while ((Get-Date) -lt $deadline) {
  Start-Sleep 5
  $v = Get-Installed
  $changed = (Test-Path $exe) -and ((Get-FileHash $exe).Hash -ne $hash0)
  $running = Get-Process KafDesk -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $kd.Id -and $_.Path -eq $exe }
  if ($v -like "$Want*" -and $changed -and $running -and $kd.HasExited) {
    "updated $before -> $v, running again (pid $($running[0].Id))"
    Start-Sleep 10
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    [System.Drawing.Graphics]::FromImage($bmp).CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
    $bmp.Save("$env:RUNNER_TEMP\kafdesk-updated.png")
    Show-Logs
    Get-Process KafDesk -ErrorAction SilentlyContinue | Stop-Process -Force
    $leftover = Get-ChildItem $tmp -Directory -Filter "kafdesk-update*" -ErrorAction SilentlyContinue
    if ($leftover) { "::warning::download folder left behind: $($leftover.FullName)" }
    Start-Process (Join-Path $dir "uninstall.exe") -ArgumentList '/S' -Wait | Out-Null
    exit 0
  }
}
"version now: $v; exe replaced: $changed; old process exited: $($kd.HasExited)"
Show-Logs
throw "KafDesk did not update to $Want within 5 minutes"
