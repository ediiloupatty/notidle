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
# notidle agent: tray icon + global hotkey.
# While active, nudges the mouse 1px back and forth whenever the PC has been idle
# for IntervalSeconds, so Windows' idle timer (which Discord reads) never runs out.
# Also blocks sleep and screen-off while active.
# Keep this file ASCII: Windows PowerShell 5.1 reads BOM-less scripts as ANSI.

$ErrorActionPreference = 'Stop'

$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $dir 'config.json'

$config = @{ hotkeyMods = 3; hotkeyVk = 0x4F; hotkeyLabel = 'Ctrl+Alt+O'; intervalSeconds = 60; startActive = $false }
if (Test-Path $configPath) {
    $saved = Get-Content $configPath -Raw | ConvertFrom-Json
    foreach ($p in $saved.PSObject.Properties) { $config[$p.Name] = $p.Value }
}

Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

public class NotIdleHotkey : NativeWindow, IDisposable {
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    const int WM_HOTKEY = 0x0312;
    const uint MOD_NOREPEAT = 0x4000;

    public event EventHandler Pressed;
    public readonly bool Registered;

    public NotIdleHotkey(uint mods, uint vk) {
        CreateHandle(new CreateParams());
        Registered = RegisterHotKey(Handle, 1, mods | MOD_NOREPEAT, vk);
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_HOTKEY && Pressed != null) Pressed(this, EventArgs.Empty);
        base.WndProc(ref m);
    }

    public void Dispose() {
        UnregisterHotKey(Handle, 1);
        DestroyHandle();
    }
}

public static class NotIdle {
    [StructLayout(LayoutKind.Sequential)]
    struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }

    // MOUSEINPUT is the largest member of INPUT's union, so this layout matches the
    // native size on both x86 (28) and x64 (40, union aligned to offset 8).
    [StructLayout(LayoutKind.Sequential)]
    struct INPUT { public uint type; public MOUSEINPUT mi; }

    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }

    [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
    [DllImport("kernel32.dll")] static extern uint SetThreadExecutionState(uint flags);
    [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr handle);

    const uint MOUSEEVENTF_MOVE = 0x0001;
    const uint ES_CONTINUOUS = 0x80000000;
    const uint ES_SYSTEM_REQUIRED = 0x00000001;
    const uint ES_DISPLAY_REQUIRED = 0x00000002;

    static NotifyIcon tray;
    static ToolStripMenuItem toggleItem;
    static Icon iconOn, iconOff;
    static bool active;
    static string hotkeyLabel;
    static int intervalMs;
    static DateTime lastNudge = DateTime.MinValue;

    static void Nudge() {
        var inputs = new INPUT[2];
        inputs[0].type = 0; inputs[0].mi.dx = 1;  inputs[0].mi.dwFlags = MOUSEEVENTF_MOVE;
        inputs[1].type = 0; inputs[1].mi.dx = -1; inputs[1].mi.dwFlags = MOUSEEVENTF_MOVE;
        SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
    }

    static uint IdleMs() {
        var info = new LASTINPUTINFO();
        info.cbSize = (uint)Marshal.SizeOf(info);
        GetLastInputInfo(ref info);
        return (uint)Environment.TickCount - info.dwTime;
    }

    static Icon Dot(Color color) {
        using (var bmp = new Bitmap(32, 32)) {
            using (var g = Graphics.FromImage(bmp)) {
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                using (var ring = new SolidBrush(Color.FromArgb(30, 31, 34))) g.FillEllipse(ring, 1, 1, 30, 30);
                using (var dot = new SolidBrush(color)) g.FillEllipse(dot, 5, 5, 22, 22);
            }
            IntPtr h = bmp.GetHicon();
            var icon = (Icon)Icon.FromHandle(h).Clone();
            DestroyIcon(h);
            return icon;
        }
    }

    static void SetActive(bool on, bool announce) {
        active = on;
        SetThreadExecutionState(on ? ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED : ES_CONTINUOUS);
        tray.Icon = on ? iconOn : iconOff;
        tray.Text = "notidle: " + (on ? "ON" : "OFF") + " (" + hotkeyLabel + ")";
        toggleItem.Checked = on;
        if (announce) {
            tray.ShowBalloonTip(1500, "notidle",
                on ? "ON - Discord stays Online" : "OFF - normal idle again",
                ToolTipIcon.None);
        }
    }

    public static void Run(uint mods, uint vk, string label, int intervalSeconds, bool startActive) {
        bool created;
        using (var mutex = new Mutex(true, @"Local\notidle.agent", out created)) {
            if (!created) return;
            using (var quit = new EventWaitHandle(false, EventResetMode.ManualReset, @"Local\notidle.quit")) {
                quit.Reset();
                hotkeyLabel = label;
                intervalMs = Math.Max(10, intervalSeconds) * 1000;
                iconOn = Dot(Color.FromArgb(35, 165, 90));
                iconOff = Dot(Color.FromArgb(128, 132, 142));

                var menu = new ContextMenuStrip();
                toggleItem = new ToolStripMenuItem("Keep Online  (" + label + ")");
                toggleItem.Click += delegate { SetActive(!active, false); };
                menu.Items.Add(toggleItem);
                menu.Items.Add(new ToolStripSeparator());
                menu.Items.Add("Quit", null, delegate { Application.Exit(); });

                tray = new NotifyIcon();
                tray.ContextMenuStrip = menu;
                tray.MouseClick += delegate(object s, MouseEventArgs e) {
                    if (e.Button == MouseButtons.Left) SetActive(!active, false);
                };
                tray.Visible = true;
                SetActive(startActive, false);

                var hotkey = new NotIdleHotkey(mods, vk);
                hotkey.Pressed += delegate { SetActive(!active, true); };
                if (!hotkey.Registered) {
                    tray.ShowBalloonTip(4000, "notidle",
                        label + " is already used by another app. Pick another: npx notidle hotkey <combo>",
                        ToolTipIcon.Warning);
                }

                var timer = new System.Windows.Forms.Timer();
                timer.Interval = 1000;
                timer.Tick += delegate {
                    if (quit.WaitOne(0)) { Application.Exit(); return; }
                    if (!active) return;
                    // Nudge only after the user has been idle a full interval, and at most once per interval.
                    if (IdleMs() >= intervalMs && (DateTime.UtcNow - lastNudge).TotalMilliseconds >= intervalMs) {
                        Nudge();
                        lastNudge = DateTime.UtcNow;
                    }
                };
                timer.Start();

                Application.Run();

                timer.Stop();
                hotkey.Dispose();
                tray.Visible = false;
                tray.Dispose();
                SetThreadExecutionState(ES_CONTINUOUS);
            }
        }
    }
}
"@

[NotIdle]::Run([uint32]$config.hotkeyMods, [uint32]$config.hotkeyVk, [string]$config.hotkeyLabel,
    [int]$config.intervalSeconds, [bool]$config.startActive)
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
