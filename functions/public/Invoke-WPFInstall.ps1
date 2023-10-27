function Invoke-WPFInstall {
    <#

    .SYNOPSIS
        Installs the selected programs using winget

    #>

    if($sync.ProcessRunning){
        $msg = "Install process is currently running."
        [System.Windows.MessageBox]::Show($msg, "Winutil", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $WingetInstall = Get-WinUtilCheckBoxes -Group "WPFInstall"

    if ($wingetinstall.Count -eq 0) {
        $WarningMsg = "Please select the program(s) to install"
        [System.Windows.MessageBox]::Show($WarningMsg, $AppTitle, [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    Invoke-WPFRunspace -ArgumentList $WingetInstall -scriptblock {
        param($WingetInstall)
        try{
            $sync.ProcessRunning = $true

            # Ensure winget is installed
            Install-WinUtilWinget

            # Install all selected programs in new window
            Install-WinUtilProgramWinget -ProgramsToInstall $WingetInstall

            $ButtonType = [System.Windows.MessageBoxButton]::OK
            $MessageboxTitle = "Installs are Finished "
            $Messageboxbody = ("Done")
            $MessageIcon = [System.Windows.MessageBoxImage]::Information

<<<<<<< HEAD
            [System.Windows.MessageBox]::Show($Messageboxbody, $MessageboxTitle, $ButtonType, $MessageIcon)
=======
                Write-Host "==========================================="
                Write-Host "--      Installs have finished          ---"
                Write-Host "==========================================="
            } else {
                # winget is not installed, proceed to download links...

                # Specify the app name for which you want to download
                $appName = "WPFInstalladobe"  # Change this to the desired app name

                # Call the DownloadLinks.ps1 script to retrieve the download link
                .\Invoke-WPFDownloadLinks.ps1
                $downloadLink = $DownloadLinks[$appName]

                if ($downloadLink) {
                    # Specify the output path where the downloaded file will be saved
                    $outputPath = Join-Path -Path $tempFolder -ChildPath "DownloadedApp.exe"

                    # Download the file
                    Download-File -url $downloadLink -outputPath $outputPath

                    Write-Host "Downloaded $appName to $outputPath"
                } else {
                    Write-Host "Download link not found for $appName."
                }
            }
>>>>>>> parent of 94f8efd (test3)

            Write-Host "==========================================="
            Write-Host "--      Installs have finished          ---"
            Write-Host "==========================================="
        }
        Catch {
            Write-Host "==========================================="
            Write-Host "--      Winget failed to install        ---"
            Write-Host "==========================================="
        }
        $sync.ProcessRunning = $False
    }
}