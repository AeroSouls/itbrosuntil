# ITBros LLC Windows Utility

Windows utility and troubleshooting toolkit for ITBros LLC. The original Install, Tweaks, Config, Updates, and MicroWin sections remain available. The new **IT Support** tab groups Windows administrative tools, printer shortcuts, network diagnostics, repair commands, and ITBros support links.

## Run on Windows

Use Windows PowerShell 5.1 on a trusted Windows computer. Download `winutil.ps1` from this repository and review the script before running it. This utility requests administrator elevation. The compiled `winutil.ps1` is generated from the source by `Compile.ps1` and should not be edited directly.

## IT Support tab

- **Windows and System**: Control Panel, Device Manager, Event Viewer, Services, Task Scheduler, installed programs, and more.
- **Printers and Devices**: printer settings, classic Devices and Printers, Print Management, Print Server Properties, and spooler restart.
- **Network Troubleshooting**: network adapters, Wi-Fi, firewall, IP configuration, netstat, DNS lookup.
- **Accounts and Security**: Credential Manager, Local Users, Group Policy Editor, security tools.
- **Diagnostics and Maintenance**: disk tools, performance monitoring, Windows Update, troubleshooting.
- **Repairs**: SFC, DISM, DNS cache flush, Winsock reset, and Group Policy refresh. These always ask for confirmation.
- **ITBros Support Resources**: support website, portal, remote support, support email, and password sender.

**Note:** Some Windows tools are unavailable on Home editions. Repair commands can change the system, take time, or require a restart. Verify they are appropriate for the machine before confirming.

## ITBros contact

Website: https://itbros.gg  
Support email: support@itbros.gg  
Phone: (919) 907-2599

The app header uses the ITBros logo hosted on itbros.gg. A network connection may be required for the logo to load on a new PC.

## Build

From the repository root on a Windows machine, run `Compile.ps1` to regenerate `winutil.ps1` from `functions/`, `scripts/`, `xaml/`, and `config/`. Keep both the source files and generated script in sync.
