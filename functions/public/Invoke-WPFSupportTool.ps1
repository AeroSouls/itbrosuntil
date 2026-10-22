function Invoke-WPFSupportTool {
    <#
    .SYNOPSIS
        Launches only the pre-defined ITBros support shortcuts.
        Repair actions display a confirmation before launching.
    #>
    param([Parameter(Mandatory=$true)][string]$Button)

    $actions = @{
        'WPFSupControlPanel' = @{ File = 'control.exe' }
        'WPFSupSettings' = @{ File = 'ms-settings:' }
        'WPFSupDeviceManager' = @{ File = 'devmgmt.msc' }
        'WPFSupComputerMgmt' = @{ File = 'compmgmt.msc' }
        'WPFSupEventViewer' = @{ File = 'eventvwr.msc' }
        'WPFSupServices' = @{ File = 'services.msc' }
        'WPFSupTaskScheduler' = @{ File = 'taskschd.msc' }
        'WPFSupTaskManager' = @{ File = 'taskmgr.exe' }
        'WPFSupInstalledApps' = @{ File = 'control.exe'; Args = @('appwiz.cpl') }
        'WPFSupSystemProperties' = @{ File = 'sysdm.cpl' }
        'WPFSupSystemInfo' = @{ File = 'msinfo32.exe' }
        'WPFSupReliability' = @{ File = 'perfmon.exe'; Args = @('/rel') }
        'WPFSupPrinterSettings' = @{ File = 'ms-settings:printers' }
        'WPFSupDevicesPrinters' = @{ File = 'control.exe'; Args = @('/name', 'Microsoft.DevicesAndPrinters') }
        'WPFSupPrintManagement' = @{ File = 'printmanagement.msc' }
        'WPFSupPrintServerProps' = @{ File = 'rundll32.exe'; Args = @('printui.dll,PrintUIEntry', '/s', '/t2') }
        'WPFSupBluetooth' = @{ File = 'ms-settings:bluetooth' }
        'WPFSupSound' = @{ File = 'control.exe'; Args = @('mmsys.cpl') }
        'WPFSupRestartSpooler' = @{ File = 'cmd.exe'; Args = @('/k', 'net stop spooler && net start spooler'); Confirm = 'This interrupts printing on this computer. Restart the Print Spooler service?' }
        'WPFSupNetworkAdapters' = @{ File = 'control.exe'; Args = @('ncpa.cpl') }
        'WPFSupNetworkStatus' = @{ File = 'ms-settings:network-status' }
        'WPFSupWifi' = @{ File = 'ms-settings:network-wifi' }
        'WPFSupProxy' = @{ File = 'ms-settings:network-proxy' }
        'WPFSupNetworkSharing' = @{ File = 'control.exe'; Args = @('/name', 'Microsoft.NetworkAndSharingCenter') }
        'WPFSupFirewall' = @{ File = 'control.exe'; Args = @('/name', 'Microsoft.WindowsFirewall') }
        'WPFSupAdvFirewall' = @{ File = 'wf.msc' }
        'WPFSupIPConfig' = @{ File = 'cmd.exe'; Args = @('/k', 'ipconfig /all') }
        'WPFSupNetstat' = @{ File = 'cmd.exe'; Args = @('/k', 'netstat -ano') }
        'WPFSupDNSLookup' = @{ File = 'cmd.exe'; Args = @('/k', 'nslookup microsoft.com') }
        'WPFSupUserAccounts' = @{ File = 'netplwiz.exe' }
        'WPFSupLocalUsers' = @{ File = 'lusrmgr.msc' }
        'WPFSupCredentials' = @{ File = 'control.exe'; Args = @('/name', 'Microsoft.CredentialManager') }
        'WPFSupGroupPolicy' = @{ File = 'gpedit.msc' }
        'WPFSupSecurityPolicy' = @{ File = 'secpol.msc' }
        'WPFSupWinSecurity' = @{ File = 'windowsdefender:' }
        'WPFSupStartupApps' = @{ File = 'ms-settings:startupapps' }
        'WPFSupWinFeatures' = @{ File = 'optionalfeatures.exe' }
        'WPFSupDiskManagement' = @{ File = 'diskmgmt.msc' }
        'WPFSupDiskCleanup' = @{ File = 'cleanmgr.exe' }
        'WPFSupStorage' = @{ File = 'ms-settings:storagesense' }
        'WPFSupResourceMonitor' = @{ File = 'resmon.exe' }
        'WPFSupPerfmon' = @{ File = 'perfmon.exe' }
        'WPFSupWindowsUpdate' = @{ File = 'ms-settings:windowsupdate' }
        'WPFSupTroubleshoot' = @{ File = 'ms-settings:troubleshoot' }
        'WPFSupMsconfig' = @{ File = 'msconfig.exe' }
        'WPFSupSfcScan' = @{ File = 'cmd.exe'; Args = @('/k', 'sfc /scannow'); Confirm = 'Run System File Checker? This can repair Windows system files and may take some time.' }
        'WPFSupDismScan' = @{ File = 'cmd.exe'; Args = @('/k', 'DISM /Online /Cleanup-Image /ScanHealth'); Confirm = 'Run the DISM component store health scan? It can take some time.' }
        'WPFSupDismRepair' = @{ File = 'cmd.exe'; Args = @('/k', 'DISM /Online /Cleanup-Image /RestoreHealth'); Confirm = 'Repair the Windows component store using DISM? This may take a long time and can use Windows Update.' }
        'WPFSupFlushDNS' = @{ File = 'cmd.exe'; Args = @('/k', 'ipconfig /flushdns'); Confirm = 'Flush this computer''s DNS resolver cache?' }
        'WPFSupWinsockReset' = @{ File = 'cmd.exe'; Args = @('/k', 'netsh winsock reset'); Confirm = 'Reset the Winsock catalog? Network services may be affected and a restart is normally required.' }
        'WPFSupGPUpdate' = @{ File = 'cmd.exe'; Args = @('/k', 'gpupdate /force'); Confirm = 'Force a Group Policy refresh now? Managed settings may change.' }
        'WPFSupWebsite' = @{ File = 'https://itbros.gg/' }
        'WPFSupContact' = @{ File = 'https://itbros.gg/contact/' }
        'WPFSupPortal' = @{ File = 'https://portal.itbros.gg/' }
        'WPFSupRemoteSupport' = @{ File = 'https://itbrosrmm.screenconnect.com/' }
        'WPFSupEmailSupport' = @{ File = 'mailto:support@itbros.gg' }
        'WPFSupPasswordSender' = @{ File = 'https://pws.itbros.gg/' }
    }

    if (-not $actions.ContainsKey($Button)) { return }
    $action = $actions[$Button]

    if ($action.ContainsKey('Confirm')) {
        $answer = [System.Windows.MessageBox]::Show(
            $action.Confirm,
            'ITBros LLC - Confirm repair action',
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning
        )
        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
    }

    try {
        $params = @{ FilePath = $action.File; ErrorAction = 'Stop' }
        if ($action.ContainsKey('Args')) {
            $params.ArgumentList = $action.Args
        }
        Start-Process @params
    }
    catch {
        [void][System.Windows.MessageBox]::Show(
            "Unable to launch this tool. It may not be available on this Windows edition.`n`n$($_.Exception.Message)",
            'ITBros LLC - IT Support',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
    }
}
