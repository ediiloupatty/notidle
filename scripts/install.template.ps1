# notidle installer: keeps your Discord status Online while you're away. No Node.js needed.
# Usage, in PowerShell:  irm https://<notidle site>/install.ps1 | iex
# Installs to %LOCALAPPDATA%\notidle, adds a Startup shortcut and starts the tray agent.
# Same layout as `npx notidle`, so both installers and all npx commands work together.
# GENERATED from scripts/install.template.ps1 by scripts/build-installer.js. Do not edit by hand.

& {
    $ErrorActionPreference = 'Stop'

    $dir = Join-Path $env:LOCALAPPDATA 'notidle'
    $agent = Join-Path $dir 'agent.ps1'
    $config = Join-Path $dir 'config.json'
    $lnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\notidle.lnk'
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

    # Dispose every handle we open: a leftover one keeps the named object alive in this
    # PowerShell session, which fools later checks and makes a new agent think one is running.
    function Test-Agent {
        try { ([Threading.Mutex]::OpenExisting('Local\notidle.agent')).Dispose(); $true } catch { $false }
    }

    $existed = Test-Path $agent

    # Quit a running agent so its file can be replaced.
    if (Test-Agent) {
        try { $quit = [Threading.EventWaitHandle]::OpenExisting('Local\notidle.quit'); [void]$quit.Set(); $quit.Dispose() } catch {}
        for ($i = 0; $i -lt 25 -and (Test-Agent); $i++) { Start-Sleep -Milliseconds 200 }
    }

    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [IO.File]::WriteAllText($agent, @'
__AGENT__
'@, [Text.Encoding]::ASCII)

    if (-not (Test-Path $config)) {
        $defaults = [ordered]@{ hotkeyMods = 3; hotkeyVk = 79; hotkeyLabel = 'Ctrl+Alt+O'; intervalSeconds = 60; startActive = $false }
        [IO.File]::WriteAllText($config, ($defaults | ConvertTo-Json), [Text.Encoding]::ASCII)
    }

    $shell = New-Object -ComObject WScript.Shell
    $l = $shell.CreateShortcut($lnk)
    $l.TargetPath = $ps
    $l.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $agent + '"'
    $l.WorkingDirectory = $dir
    $l.WindowStyle = 7
    $l.Description = 'notidle - keep Discord Online'
    $l.Save()

    Start-Process -FilePath $ps -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + $agent + '"')
    for ($i = 0; $i -lt 50 -and -not (Test-Agent); $i++) { Start-Sleep -Milliseconds 200 }

    $label = (Get-Content $config -Raw | ConvertFrom-Json).hotkeyLabel
    $verb = if ($existed) { 'updated' } else { 'installed' }
    Write-Host ''
    Write-Host "notidle $verb." -ForegroundColor Green
    Write-Host ''
    Write-Host "  Press $label to turn it ON / OFF."
    Write-Host '  Tray icon: green = ON, gray = OFF. Left-click it to toggle too.'
    Write-Host '  Starts automatically when you log in to Windows.'
    Write-Host ''
    Write-Host '  To remove it, run the uninstall command from the notidle website.'
}
