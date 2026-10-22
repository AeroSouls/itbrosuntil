# ITBros LLC Windows Utility

Windows utility and troubleshooting toolkit for ITBros LLC. The original Install, Tweaks, Config, Updates, and MicroWin sections remain available. The new **IT Support** tab groups Windows administrative tools, printer shortcuts, network diagnostics, repair commands, and ITBros support links.

## Run on Windows

Use Windows PowerShell 5.1 on a trusted Windows computer. Download `winutil.ps1` from this repository and review the script before running it. This utility requests administrator elevation. The compiled `winutil.ps1` is generated from the source by `Compile.ps1` and should not be edited directly.

## Technician interface

- **IT Support opens automatically** when the utility starts; its navigation button is first.
- Modern dark palette, rounded buttons, and clear two-column cards with vertical scrolling.
- Filter the 57 support tools by name or category using **Search tools**. `Ctrl+F` focuses support search from IT Support, or selects the dedicated application search on other tabs.
- Install, Tweaks, Config, Updates, and MicroWin are preserved.
- Navigation shortcuts: `Alt+S` (Support), `Alt+I` (Install), `Alt+T` (Tweaks), `Alt+C` (Config), `Alt+U` (Updates), and `Alt+M` (MicroWin).

## IT Support tab

- **Windows and System**: Control Panel, Device Manager, Event Viewer, Services, Task Scheduler, installed programs, and more.
- **Printers and Devices**: printer settings, classic Devices and Printers, Print Management, Print Server Properties, and spooler restart.
- **Network Troubleshooting**: network adapters, Wi-Fi, firewall, IP configuration, netstat, DNS lookup.
- **Accounts and Security**: Credential Manager, Local Users, Group Policy Editor, security tools.
- **Diagnostics and Maintenance**: disk tools, performance monitoring, Windows Update, troubleshooting.
- **Repairs**: SFC, DISM, DNS cache flush, Winsock reset, and Group Policy refresh. These always ask for confirmation.
- **ITBros Support Resources**: support website, portal, remote support, support email, and password sender.

**Note:** Some Windows tools are unavailable on Home editions. Repair commands can change the system, take time, or require a restart. Verify they are appropriate for the machine before confirming.

## ITBros IP Scanner (test branch only)

Open **IT Support → Network Troubleshooting → ITBros IP Scanner**. The scanner opens in its own resizable window. Enter an IPv4 target and click **Start scan**.

### Launch the current test build (v0.3.1)

Close all existing ITBros Utility windows and start a fresh Windows PowerShell session. Download from the **test branch**, not `main`:

```powershell
Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/AeroSouls/itbrosuntil/test/itbros-ip-scanner/winutil.ps1' -OutFile "$env:TEMP\ITBros-IPScanner-Test-v031.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\ITBros-IPScanner-Test-v031.ps1"
```

The scanner title must say **ITBros | IP Scanner TEST v0.3.1**. If you still see an older error showing the entire `<Window>` markup, you are running an earlier script. The new build shows a concise underlying error if initialization fails.

- Accepts a single IP (`192.168.1.10`), full start-end range (`192.168.1.10-192.168.1.50`), or CIDR subnet (`192.168.1.0/24`).
- No automatic scanning. At most **1,024 addresses** are allowed per scan. Scan only networks you are authorized to administer.
- Displays **only devices that successfully answer ICMP ping**, in a table with readable dark headers and plain IP addresses.
- Resolves device names using reverse DNS (when available), with an optional slower NetBIOS name lookup for Windows devices.
- **Printers only** searches common printing ports 515, 631 and 9100 and recognizable printer hostnames. This is best-effort identification, not proof that a device is a printer. Printers that block ping or don't expose these indicators won't appear.
- Optional checks on ports 80, 443, 445 and 3389 for responding devices; clickable web links for HTTP 80, HTTPS 443 and IPP web interface 631. Non-web ports such as 445 and 3389 are not opened in a browser.
- **TEST v0.3.1** fixes clickable web links to open in the Windows default browser (the previous handler used the reserved PowerShell `$args` variable). A listening web port does not guarantee that a web admin page is available.
- Shows ICMP latency and local-neighbor MAC addresses when Windows knows them.
- TCP checks never add non-pinging devices. These are targeted service checks, not a full port scan or vulnerability assessment.
- **Stop** terminates the scan worker, **Export CSV** saves found devices, and closing the window cleans up temporary scanner files.
- Uses built-in Windows PowerShell and .NET APIs; does not install third-party scanner applications.

This is an initial Windows test build, not a full replacement for Advanced IP Scanner. Network firewall policies, ICMP blocking, reverse DNS availability, and router separation can limit results. The worker uses a temporary PowerShell script and deletes it after the scan. Target-validation tests are in `pester/ipscanner.Tests.ps1`.

**Windows testing required before merging to main.**

## ITBros contact

Website: https://itbros.gg  

The app header uses the ITBros logo hosted on itbros.gg. A network connection may be required for the logo to load on a new PC.

## Build

From the repository root on a Windows machine, run `Compile.ps1` to regenerate `winutil.ps1` from `functions/`, `scripts/`, `xaml/`, and `config/`. Keep both the source files and generated script in sync.
