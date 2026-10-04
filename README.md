# dc.online

Keep your Discord status **Online** (green) while you're away from the PC. Toggle it with a keyboard shortcut. Windows only.

```
npx dc.online
```

Then press **Ctrl+Alt+O** to turn it on or off. A dot in the system tray shows the state: green = on, gray = off. You can also left-click the dot to toggle.

## How it works

Discord marks you Idle when Windows reports no mouse or keyboard input for a while. While dc.online is on, it checks every second how long the PC has been idle. Once that reaches 60 seconds, it moves the mouse 1 px right and 1 px back. The cursor ends where it started and nothing gets clicked. It never does anything while you're using the PC.

While on, it also stops Windows from sleeping or turning the screen off.

It is a small PowerShell script with a tray icon. It needs no admin rights, sends nothing over the network and doesn't touch Discord itself.

## Commands

| Command | What it does |
| --- | --- |
| `npx dc.online` | Install (or update) and start |
| `npx dc.online hotkey ctrl+shift+f9` | Change the shortcut (modifiers: ctrl, alt, shift, win; key: A–Z, 0–9, F1–F24) |
| `npx dc.online interval 120` | Idle seconds before each nudge (10–3600, default 60) |
| `npx dc.online start` / `stop` | Start or quit the background agent |
| `npx dc.online status` | Show what's installed and running |
| `npx dc.online uninstall` | Remove everything |

It installs into `%LOCALAPPDATA%\dc.online` and adds a shortcut to your Startup folder so it runs when you log in. It always starts **off**. `uninstall` removes both.

If you install it globally (`npm i -g dc.online`), the command is `dc-online`, e.g. `dc-online status`.

## License

MIT
