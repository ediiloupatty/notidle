# notidle uninstaller. Usage, in PowerShell:  irm https://<notidle site>/uninstall.ps1 | iex
# Quits the tray agent and removes %LOCALAPPDATA%\notidle and the Startup shortcut.

& {
    $dir = Join-Path $env:LOCALAPPDATA 'notidle'
    $lnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\notidle.lnk'

    # Dispose every handle we open, or the named object stays alive in this session.
    function Test-Agent {
        try { ([Threading.Mutex]::OpenExisting('Local\notidle.agent')).Dispose(); $true } catch { $false }
    }

    if (Test-Agent) {
        try { $quit = [Threading.EventWaitHandle]::OpenExisting('Local\notidle.quit'); [void]$quit.Set(); $quit.Dispose() } catch {}
        for ($i = 0; $i -lt 25 -and (Test-Agent); $i++) { Start-Sleep -Milliseconds 200 }
    }

    Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host ''
    Write-Host 'notidle removed.' -ForegroundColor Green
}
