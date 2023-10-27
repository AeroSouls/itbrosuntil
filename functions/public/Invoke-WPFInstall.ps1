function Invoke-WPFInstall {
    <#
    .SYNOPSIS
        Installs the selected programs using winget
    #>

    if ($sync.ProcessRunning) {
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

    Invoke-WPFRunspace -ArgumentList $WingetInstall -ScriptBlock {
        param($WingetInstall)
        try {
            $sync.ProcessRunning = $true

            # Check if winget is installed
            if (Test-WinUtilPackageManager -winget) {
                # winget is installed, proceed with installation
                Install-WinUtilProgramWinget -ProgramsToInstall $WingetInstall

                $ButtonType = [System.Windows.MessageBoxButton]::OK
                $MessageboxTitle = "Installs are Finished "
                $Messageboxbody = ("Done")
                $MessageIcon = [System.Windows.MessageBoxImage]::Information

                [System.Windows.MessageBox]::Show($Messageboxbody, $MessageboxTitle, $ButtonType, $MessageIcon)

                Write-Host "==========================================="
                Write-Host "--      Installs have finished          ---"
                Write-Host "==========================================="
            } else {
                # winget is not installed, proceed to download links...

                # Iterate through selected programs and download each one
                foreach ($selectedProgram in $WingetInstall) {
                    # Call the DownloadLinks.ps1 script to retrieve the download link
                    .\Invoke-WPFDownloadLinks.ps1
                    $appName = "WPFInstall$selectedProgram"  # Set the app name based on the selected program

                    $downloadLink = $DownloadLinks[$appName]

                    if ($downloadLink) {
                        # Specify the output path where the downloaded file will be saved
                        $outputPath = Join-Path -Path $tempFolder -ChildPath "DownloadedApp_$selectedProgram.exe"

                        # Download the file
                        Download-File -url $downloadLink -outputPath $outputPath

                        Write-Host "Downloaded $appName to $outputPath"
                    } else {
                        Write-Host "Download link not found for $appName."
                    }
                }
            }

            Write-Host "==========================================="
        } catch {
            Write-Host "==========================================="
            Write-Host "--      Installation failed             ---"
            Write-Host "==========================================="
        }
        $sync.ProcessRunning = $False
    }
}