Unregister-ScheduledTask -TaskName 'foldersync' -Confirm:$false -ErrorAction SilentlyContinue
Write-Host 'Задача отключена. Папка %USERPROFILE%\.foldersync (настройки, журналы, резервные копии) оставлена.'
