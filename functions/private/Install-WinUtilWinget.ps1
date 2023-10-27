function Get-LatestHash {
    $shaUrl = ((Invoke-WebRequest $apiLatestUrl -UseBasicParsing | ConvertFrom-Json).assets | Where-Object { $_.name -match '^Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.txt$' }).browser_download_url

    $shaFile = Join-Path -Path $tempFolder -ChildPath 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.txt'
    $WebClient.DownloadFile($shaUrl, $shaFile)

    Get-Content $shaFile
}

function Install-WinUtilWinget {
    <#
    .SYNOPSIS
        Installs Winget if it is not already installed
    #>
    Try {
        Write-Host "Checking if Winget is Installed..."
        if (Test-WinUtilPackageManager -winget) {
            # Checks if winget executable exists and if the Windows Version is 1809 or higher
            Write-Host "Winget Already Installed"
            return
        }

        # Gets the computer's information
        if ($null -eq $sync.ComputerInfo) {
            $ComputerInfo = Get-ComputerInfo -ErrorAction Stop
        } else {
            $ComputerInfo = $sync.ComputerInfo
        }

        if ($ComputerInfo.WindowsVersion -lt "1809") {
            # Checks if Windows Version is too old for winget
            Write-Host "Winget is not supported on this version of Windows (Pre-1809)"
            
            # Specify the app name for which you want to download the file
            $appName = "WPFInstalladobe"

            # Call the DownloadLinks.ps1 script to retrieve the download link
            .\Invoke-WPFDownloadLinks.ps1

            # Retrieve the download link for the specified app
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

            return
        }

        Write-Host "Running Alternative Installer and Direct Installing"
        Start-Process -Verb runas -FilePath powershell.exe -ArgumentList "choco install winget"

        Write-Host "Winget Installed"
    } Catch {
        throw [WingetFailedInstall]::new('Failed to install')
    }
}