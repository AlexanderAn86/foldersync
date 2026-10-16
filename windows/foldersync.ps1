# foldersync — двусторонняя синхронизация выбранных папок с Google Диском через rclone bisync (Windows).
# Настройки: %USERPROFILE%\.foldersync\pairs.conf   (строки: ЛОКАЛЬНАЯ_ПАПКА => gdrive:ПАПКА)
# Запуск:  foldersync.ps1          — синхронизировать все пары
#          foldersync.ps1 -Init    — первая синхронизация для новых пар
param([switch]$Init)
$ErrorActionPreference = 'Continue'
$Base    = Join-Path $env:USERPROFILE '.foldersync'
$Conf    = Join-Path $Base 'pairs.conf'
$State   = Join-Path $Base 'state'
$LogDir  = Join-Path $Base 'logs'
$BackupL = Join-Path $Base 'backup'
foreach ($d in @($State,$LogDir,$BackupL)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
$Log = Join-Path $LogDir ((Get-Date -Format 'yyyy-MM') + '.log')

function Write-Log($m) { Add-Content -Path $Log -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $m) -Encoding UTF8 }
function Show-Note($m) {
  try {
    Add-Type -AssemblyName System.Windows.Forms
    $n = New-Object System.Windows.Forms.NotifyIcon
    $n.Icon = [System.Drawing.SystemIcons]::Warning; $n.Visible = $true
    $n.ShowBalloonTip(10000, 'foldersync', $m, 'Warning'); Start-Sleep -Seconds 10; $n.Dispose()
  } catch {}
}

$rclone = (Get-Command rclone -ErrorAction SilentlyContinue).Source
if (-not $rclone) { $c = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\rclone.exe'; if (Test-Path $c) { $rclone = $c } }
if (-not $rclone) { Write-Log 'ERROR rclone not found'; Show-Note 'rclone не найден'; exit 1 }
if (-not (Test-Path $Conf)) { Write-Log "ERROR no config $Conf"; exit 1 }

$mutex = New-Object System.Threading.Mutex($false, 'Local\foldersync')
if (-not $mutex.WaitOne(0)) { exit 0 }
$errors = 0
try {
  foreach ($raw in (Get-Content -Path $Conf -Encoding UTF8)) {
    $line = ($raw -split '#',2)[0]
    if ($line -notmatch '=>') { continue }
    $parts  = $line -split '=>',2
    $local  = $parts[0].Trim(); $remote = $parts[1].Trim()
    if ($local.StartsWith('~')) { $local = $env:USERPROFILE + $local.Substring(1) }
    if (-not $local -or -not $remote) { continue }
    $sha = [System.Security.Cryptography.SHA1]::Create()
    $id  = (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes("$local|$remote")) | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0,12)
    $rname = ($remote -split ':',2)[0]
    if ($Init -and -not (Test-Path (Join-Path $State "$id.ok"))) { New-Item -ItemType Directory -Force -Path $local | Out-Null }
    if (-not (Test-Path -LiteralPath $local -PathType Container)) { Write-Log "ERROR [$id] local folder missing: $local"; Show-Note "Нет папки: $local"; $errors++; continue }

    $rargs = @('bisync', $local, $remote,
      '--create-empty-src-dirs','--resilient','--recover','--max-lock','2m',
      '--compare','size,modtime',
      '--conflict-resolve','newer','--conflict-loser','num','--conflict-suffix','conflict','--suffix-keep-extension',
      '--backup-dir1', (Join-Path $BackupL $id), '--backup-dir2', "$($rname):_foldersync_backup/$id",
      '--exclude','.DS_Store','--exclude','Thumbs.db','--exclude','desktop.ini','--exclude','~$*','--exclude','.~lock.*','--exclude','*.tmp','--exclude','.tmp.drivedownload/**','--exclude','.tmp.driveupload/**',
      '--drive-skip-gdocs','--log-file', $Log, '--log-level','NOTICE')
    $ok = Join-Path $State "$id.ok"
    if (-not (Test-Path $ok)) {
      if ($Init) {
        Write-Log "INIT [$id] $local <=> $remote"
        & $rclone mkdir $remote 2>&1 | Out-Null
        & $rclone @rargs '--resync' '--resync-mode' 'newer'
        if ($LASTEXITCODE -eq 0) { New-Item -ItemType File -Force -Path $ok | Out-Null; Write-Log "INIT OK [$id]" }
        else { Write-Log "ERROR INIT [$id]"; Show-Note "Ошибка первой синхронизации: $local"; $errors++ }
      } else { Write-Log "SKIP [$id] not initialized, run: foldersync.ps1 -Init" }
      continue
    }
    & $rclone @rargs
    if ($LASTEXITCODE -eq 0) { Write-Log "OK [$id] $local" }
    else { Write-Log "ERROR [$id] $local (see log)"; Show-Note ("Ошибка синхронизации: " + (Split-Path $local -Leaf)); $errors++ }
  }
} finally { $mutex.ReleaseMutex() }
exit $errors
