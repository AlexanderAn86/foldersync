# Устанавливает foldersync в Windows: копирует скрипт, создаёт настройки, регистрирует задачу (каждые 15 минут).
$Base = Join-Path $env:USERPROFILE '.foldersync'
New-Item -ItemType Directory -Force -Path $Base | Out-Null
Copy-Item -Force (Join-Path $PSScriptRoot 'foldersync.ps1') (Join-Path $Base 'foldersync.ps1')
if (-not (Test-Path (Join-Path $Base 'pairs.conf'))) { Copy-Item (Join-Path $PSScriptRoot 'pairs.conf') (Join-Path $Base 'pairs.conf') }
$script = Join-Path $Base 'foldersync.ps1'
$action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 15)
$logon   = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 1)
Register-ScheduledTask -TaskName 'foldersync' -Action $action -Trigger @($trigger,$logon) -Settings $settings -Force | Out-Null
Write-Host "Готово. Настройки: $Base\pairs.conf ; журнал: $Base\logs\"
Write-Host "Первый запуск: powershell -ExecutionPolicy Bypass -File `"$script`" -Init"
