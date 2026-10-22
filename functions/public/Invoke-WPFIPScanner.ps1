function Convert-WPFScannerIPv4 {
    param([Parameter(Mandatory=$true)][string]$Address)

    if ($Address -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
        throw "Enter a valid IPv4 address: $Address"
    }
    [uint64]$value = 0
    foreach ($part in $Address.Split('.')) {
        $octet = [int]$part
        if ($octet -gt 255) { throw "Invalid IPv4 octet in $Address" }
        $value = ($value * 256) + $octet
    }
    return $value
}

function Get-WPFScannerTargets {
    param([Parameter(Mandatory=$true)][string]$Target)

    $inputText = $Target.Trim()
    [uint64]$start = 0
    [uint64]$end = 0

    if ($inputText -match '^([^/]+)/(\d{1,2})$') {
        $address = Convert-WPFScannerIPv4 $Matches[1]
        $prefix = [int]$Matches[2]
        if ($prefix -lt 0 -or $prefix -gt 32) { throw "CIDR prefix must be between 0 and 32." }

        [uint64]$blockSize = [uint64][math]::Pow(2, (32 - $prefix))
        $start = [uint64]([math]::Floor($address / $blockSize) * $blockSize)
        $end = $start + $blockSize - 1

        # Exclude network and broadcast in ordinary subnets; keep both addresses in /31 and /32.
        if ($prefix -le 30) { $start++; $end-- }
    }
    elseif ($inputText -match '^([0-9.]+)\s*-\s*([0-9.]+)$') {
        $start = Convert-WPFScannerIPv4 $Matches[1]
        $end = Convert-WPFScannerIPv4 $Matches[2]
    }
    else {
        $start = Convert-WPFScannerIPv4 $inputText
        $end = $start
    }

    if ($end -lt $start) { throw "The end IP must be greater than or equal to the start IP." }
    $count = $end - $start + 1
    if ($count -gt 1024) { throw "For safety, scan 1,024 addresses or fewer at a time." }

    for ([uint64]$n = $start; $n -le $end; $n++) {
        $a = [int][math]::Floor($n / 16777216)
        $b = [int][math]::Floor(($n % 16777216) / 65536)
        $c = [int][math]::Floor(($n % 65536) / 256)
        $d = [int]($n % 256)
        "$a.$b.$c.$d"
    }
}

function Invoke-WPFIPScanner {
    <#
    .SYNOPSIS
        Opens a separate ITBros IP Scanner window.
    .DESCRIPTION
        Only scans an explicitly entered IPv4 target. Supports a single IP, a
        full IP start-end range, or a CIDR subnet (up to 1,024 addresses).
        A child PowerShell process performs network probes so the WPF UI
        remains responsive. Stopping or closing the window ends that process.
        No external scanning tools or dependencies are downloaded.
    #>

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Add-Type -AssemblyName System.Windows.Forms

    $scannerXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ITBros | IP Scanner TEST v0.3" Width="1160" Height="700"
        MinWidth="810" MinHeight="490" WindowStartupLocation="CenterOwner"
        Background="#101923" FontFamily="Segoe UI" FontSize="13">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Foreground" Value="#F2F6FA"/>
            <Setter Property="Background" Value="#293E54"/>
            <Setter Property="BorderBrush" Value="#405870"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="15,9"/>
            <Setter Property="Margin" Value="5,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="BasicButtonSurface" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="1" CornerRadius="8" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="BasicButtonSurface" Property="Background" Value="#3F5971"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#E7EDF5"/>
        </Style>
    </Window.Resources>
    <Grid Margin="22">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <DockPanel Grid.Row="0" Margin="2,0,2,18">
            <StackPanel>
                <TextBlock Text="ITBros IP Scanner" FontSize="25" FontWeight="SemiBold"/>
                <TextBlock Text="Device discovery for networks you are authorized to scan"
                           Foreground="#9EAFBE" Margin="0,5,0,0"/>
            </StackPanel>
            <TextBlock DockPanel.Dock="Right" Text="TEST v0.3" Foreground="#FA9CA5"
                       HorizontalAlignment="Right" FontWeight="Bold" FontSize="11"
                       Margin="0,9,0,0"/>
        </DockPanel>
        <Border Grid.Row="1" Background="#1B2A3B" BorderBrush="#35495D"
                BorderThickness="1" CornerRadius="12" Padding="18,16">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock Text="IP RANGE OR CIDR" Foreground="#BCCAD8" FontSize="11"
                               FontWeight="Bold" Margin="0,0,0,8"/>
                    <TextBox Name="ScanTarget" Background="#111F2E" BorderBrush="#567087"
                             Foreground="White" Padding="10,9" FontSize="14"
                             Text="" ToolTip="Example: 192.168.1.0/24 or 192.168.1.10-192.168.1.50"/>
                    <TextBlock Text="Examples: 192.168.1.0/24  |  10.0.0.10-10.0.0.50  |  192.168.1.1"
                               Foreground="#A6B8CA" FontSize="11" Margin="0,8,0,0"/>
                    <CheckBox Name="ScanPorts" Content="Check TCP ports on ping-responsive devices (80, 443, 445, 3389)"
                              Foreground="#D5E0EB" Margin="0,12,0,0" IsChecked="False"/>
                    <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                        <TextBlock Text="SHOW:" Foreground="#BECEDF" FontSize="11" FontWeight="Bold"
                                   VerticalAlignment="Center" Margin="0,0,12,0"/>
                        <ComboBox Name="ScanFilter" SelectedIndex="0" Height="33" Width="200"
                                  Background="#203247" Foreground="#101923" FontSize="12"
                                  ToolTip="Printer filter looks for TCP 9100, 631, 515 or printer names. All devices must respond to ping.">
                            <ComboBoxItem Content="All responding devices"/>
                            <ComboBoxItem Content="Likely printers only"/>
                        </ComboBox>
                    </StackPanel>
                </StackPanel>
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center"
                            Margin="14,8,0,0">
                    <Button Name="ScanStart" Content="Start scan" Background="#AA3542"/>
                    <Button Name="ScanStop" Content="Stop" IsEnabled="False"/>
                    <Button Name="ScanExport" Content="Export CSV" IsEnabled="False"/>
                </StackPanel>
            </Grid>
        </Border>
        <StackPanel Grid.Row="2" Margin="3,16,3,12">
            <TextBlock Name="ScanStatus" Text="Ready. Enter a target above, then start the scan."
                       Foreground="#CAD6E2" Margin="0,0,0,9"/>
            <ProgressBar Name="ScanProgress" Height="7" Minimum="0" Maximum="100"
                         Value="0" Background="#243448" Foreground="#C84B5B"/>
        </StackPanel>
        <Border Grid.Row="3" Background="#192838" BorderBrush="#35495D"
                BorderThickness="1" CornerRadius="11" Padding="2">
            <DataGrid Name="ScanResults" AutoGenerateColumns="False" CanUserAddRows="False"
                      IsReadOnly="True" HeadersVisibility="Column" AlternatingRowBackground="#21364B"
                      Background="#192838" Foreground="#EEF3F8" RowBackground="#192838"
                      BorderThickness="0" GridLinesVisibility="None"
                      ColumnHeaderHeight="38" RowHeight="33" SelectionMode="Extended">
                <DataGrid.Resources>
                    <Style TargetType="{x:Type TextBlock}">
                        <Setter Property="Foreground" Value="#EAF1F9"/>
                        <Setter Property="VerticalAlignment" Value="Center"/>
                    </Style>
                </DataGrid.Resources>
                <DataGrid.ColumnHeaderStyle>
                    <Style TargetType="{x:Type DataGridColumnHeader}">
                        <Setter Property="Background" Value="#263B51"/>
                        <Setter Property="Foreground" Value="#FFFFFF"/>
                        <Setter Property="FontWeight" Value="SemiBold"/>
                        <Setter Property="FontSize" Value="13"/>
                        <Setter Property="Padding" Value="12,0"/>
                        <Setter Property="BorderBrush" Value="#435970"/>
                        <Setter Property="BorderThickness" Value="0,0,1,1"/>
                    </Style>
                </DataGrid.ColumnHeaderStyle>
                <DataGrid.Columns>
                    <DataGridTextColumn Header="IP address" Binding="{Binding IP}" Width="145"/>
                    <DataGridTextColumn Header="Device name" Binding="{Binding Hostname}" Width="*"/>
                    <DataGridTextColumn Header="Type" Binding="{Binding DeviceType}" Width="118"/>
                    <DataGridTextColumn Header="Ping (ms)" Binding="{Binding Latency}" Width="88"/>
                    <DataGridTextColumn Header="MAC (local LAN)" Binding="{Binding MAC}" Width="145"/>
                    <DataGridTextColumn Header="Open TCP ports" Binding="{Binding Ports}" Width="130"/>
                    <DataGridTemplateColumn Header="Web UI" Width="118">
                        <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate>
                                <ItemsControl ItemsSource="{Binding WebLinks}">
                                    <ItemsControl.ItemsPanel>
                                        <ItemsPanelTemplate>
                                            <StackPanel Orientation="Horizontal"/>
                                        </ItemsPanelTemplate>
                                    </ItemsControl.ItemsPanel>
                                    <ItemsControl.ItemTemplate>
                                        <DataTemplate>
                                            <TextBlock Margin="0,0,9,0">
                                                <Hyperlink NavigateUri="{Binding Url}" Foreground="#72C9FF"
                                                           ToolTip="Open this HTTP(S) address in your browser">
                                                    <Run Text="{Binding Label}"/>
                                                </Hyperlink>
                                            </TextBlock>
                                        </DataTemplate>
                                    </ItemsControl.ItemTemplate>
                                </ItemsControl>
                            </DataTemplate>
                        </DataGridTemplateColumn.CellTemplate>
                    </DataGridTemplateColumn>
                </DataGrid.Columns>
            </DataGrid>
        </Border>
        <TextBlock Grid.Row="4"
                   Text="Only successful ping replies are listed. Printer detection is best-effort; web links appear for HTTP, HTTPS and IPP services."
                   Foreground="#A7B8C8" FontSize="11" Margin="5,14,0,0" TextWrapping="Wrap"/>
    </Grid>
</Window>
'@

    # Use XmlReader instead of converting the entire XAML to [xml].
    # Show the underlying XML/WPF error rather than echoing the complete markup.
    $xmlReader = $null
    $stringReader = $null
    try {
        $stringReader = [System.IO.StringReader]::new($scannerXaml)
        $xmlReader = [System.Xml.XmlReader]::Create($stringReader)
        $window = [System.Windows.Markup.XamlReader]::Load($xmlReader)
    }
    catch {
        $errorDetail = $_.Exception.GetBaseException()
        $summary = $errorDetail.Message
        if ($errorDetail -is [System.Xml.XmlException]) {
            $summary = "XML line $($errorDetail.LineNumber), position $($errorDetail.LinePosition): $summary"
        }
        [void][System.Windows.MessageBox]::Show(
            ("IP Scanner TEST v0.2 could not open." + [Environment]::NewLine + [Environment]::NewLine + $summary),
            'ITBros IP Scanner', 'OK', 'Error'
        )
        return
    }
    finally {
        if ($xmlReader) { $xmlReader.Dispose() }
        if ($stringReader) { $stringReader.Dispose() }
    }

    if ($sync -and $sync.Form) { $window.Owner = $sync.Form }

    $state = @{
        Window = $window
        Target = $window.FindName('ScanTarget')
        Ports = $window.FindName('ScanPorts')
        Filter = $window.FindName('ScanFilter')
        Start = $window.FindName('ScanStart')
        Stop = $window.FindName('ScanStop')
        Export = $window.FindName('ScanExport')
        Status = $window.FindName('ScanStatus')
        Progress = $window.FindName('ScanProgress')
        Results = $window.FindName('ScanResults')
        Items = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
        Process = $null
        Folder = $null
        ResultPath = $null
        ProgressPath = $null
        ErrorPath = $null
        Timer = $null
        NextLine = 0
        Total = 0
        WasStopped = $false
    }
    $state.Results.ItemsSource = $state.Items

    $worker = @'
param(
    [Parameter(Mandatory=$true)][string]$TargetFile,
    [Parameter(Mandatory=$true)][string]$ResultFile,
    [Parameter(Mandatory=$true)][string]$ProgressFile,
    [Parameter(Mandatory=$true)][string]$ErrorFile,
    [switch]$ProbePorts
)
$ErrorActionPreference = 'Stop'
try {
    $addresses = @(Get-Content -LiteralPath $TargetFile)
    $count = $addresses.Count
    [void](New-Item -ItemType File -Path $ResultFile -Force)

    for ($offset = 0; $offset -lt $count; $offset += 32) {
        $end = [math]::Min($offset + 31, $count - 1)
        $batch = @($addresses[$offset..$end])
        $pings = @()
        foreach ($address in $batch) {
            $client = New-Object System.Net.NetworkInformation.Ping
            try {
                $task = $client.SendPingAsync($address, 500)
                $pings += [pscustomobject]@{ IP=$address; Client=$client; Task=$task; Alive=$false; Latency='-'; Ports=@() }
            }
            catch { $client.Dispose() }
        }

        $pingTasks = @($pings | ForEach-Object { $_.Task })
        if ($pingTasks.Count) {
            try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$pingTasks, 950) }
            catch { } # Some ICMP probes can fault or time out.
        }
        foreach ($entry in $pings) {
            try {
                if ($entry.Task.IsCompleted -and -not $entry.Task.IsFaulted -and -not $entry.Task.IsCanceled -and
                    $entry.Task.Result.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                    $entry.Alive = $true
                    $entry.Latency = [string]$entry.Task.Result.RoundtripTime
                }
            } catch {}
            finally { $entry.Client.Dispose() }
        }

        # Optional concurrent TCP discovery. A service can respond even when ICMP is blocked.
        if ($ProbePorts) {
            $checks = @()
            foreach ($entry in $pings) {
                foreach ($port in @(80,443,445,3389)) {
                    $tcp = New-Object System.Net.Sockets.TcpClient
                    try {
                        $task = $tcp.ConnectAsync($entry.IP, $port)
                        $checks += [pscustomobject]@{ Entry=$entry; Port=$port; Client=$tcp; Task=$task }
                    }
                    catch { $tcp.Dispose() }
                }
            }
            $tcpTasks = @($checks | ForEach-Object { $_.Task })
            if ($tcpTasks.Count) {
                try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$tcpTasks, 700) }
                catch { } # Closed ports can fault.
            }
            foreach ($check in $checks) {
                try {
                    if ($check.Task.IsCompleted -and -not $check.Task.IsFaulted -and
                        -not $check.Task.IsCanceled -and $check.Client.Connected) {
                        $check.Entry.Alive = $true
                        $check.Entry.Ports += $check.Port
                    }
                }
                catch {}
                finally { $check.Client.Dispose() }
            }
        }

        $alive = @($pings | Where-Object { $_.Alive })
        $dnsQueries = @()
        foreach ($entry in $alive) {
            try {
                $task = [System.Net.Dns]::GetHostEntryAsync($entry.IP)
                $dnsQueries += [pscustomobject]@{ IP=$entry.IP; Task=$task }
            }
            catch {}
        }
        $dnsTasks = @($dnsQueries | ForEach-Object { $_.Task })
        if ($dnsTasks.Count) {
            try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$dnsTasks, 650) }
            catch {}
        }
        $names = @{}
        foreach ($query in $dnsQueries) {
            try {
                if ($query.Task.IsCompleted -and -not $query.Task.IsFaulted -and -not $query.Task.IsCanceled) {
                    $names[$query.IP] = $query.Task.Result.HostName
                }
            } catch {}
        }

        # Neighbor table normally contains MACs only for hosts on the same local L2 segment.
        $neighbors = @{}
        try {
            Get-NetNeighbor -AddressFamily IPv4 -ErrorAction Stop | ForEach-Object {
                if ($_.LinkLayerAddress -and $_.LinkLayerAddress -ne '00-00-00-00-00-00') {
                    $neighbors[$_.IPAddress] = $_.LinkLayerAddress
                }
            }
        } catch {}

        foreach ($entry in $alive) {
            $hostname = if ($names.ContainsKey($entry.IP)) { $names[$entry.IP] } else { '-' }
            $mac = if ($neighbors.ContainsKey($entry.IP)) { $neighbors[$entry.IP] } else { '-' }
            $ports = if ($entry.Ports.Count) { ($entry.Ports | Sort-Object -Unique) -join ', ' } else { '-' }
            $record = [pscustomobject]@{
                IP = $entry.IP
                Hostname = $hostname
                Latency = $entry.Latency
                MAC = $mac
                Ports = $ports
            }
            Add-Content -LiteralPath $ResultFile -Value ($record | ConvertTo-Json -Compress) -Encoding UTF8
        }

        Set-Content -LiteralPath $ProgressFile -Value ($end + 1) -Encoding Ascii
    }
}
catch {
    Set-Content -LiteralPath $ErrorFile -Value $_.Exception.Message -Encoding UTF8
    exit 1
}
'@

    $state.Timer = New-Object System.Windows.Threading.DispatcherTimer
    $state.Timer.Interval = [TimeSpan]::FromMilliseconds(350)

    $state.Timer.Add_Tick({
        if (-not $state.Process) { return }
        try {
            if ($state.ResultPath -and (Test-Path -LiteralPath $state.ResultPath)) {
                $lines = @(Get-Content -LiteralPath $state.ResultPath -ErrorAction Stop)
                while ($state.NextLine -lt $lines.Count) {
                    try {
                        $row = $lines[$state.NextLine] | ConvertFrom-Json -ErrorAction Stop
                        $state.Items.Add([pscustomobject]@{
                            IP = [string]$row.IP
                            Hostname = [string]$row.Hostname
                            Latency = [string]$row.Latency
                            MAC = [string]$row.MAC
                            Ports = [string]$row.Ports
                        })
                        $state.NextLine++
                    }
                    catch { break }  # A partially written line can be read on the next tick.
                }
                $state.Export.IsEnabled = ($state.Items.Count -gt 0)
            }
            $done = 0
            if ($state.ProgressPath -and (Test-Path -LiteralPath $state.ProgressPath)) {
                $value = Get-Content -LiteralPath $state.ProgressPath -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($value -match '^\d+$') { $done = [int]$value }
            }
            if ($state.Total -gt 0) {
                $state.Progress.Value = [math]::Min(100, 100 * $done / $state.Total)
            }
            $state.Status.Text = "Scanned $done / $($state.Total) addresses | $($state.Items.Count) responding devices"

            if ($state.Process.HasExited) {
                $state.Timer.Stop()
                # Read results one more time after the child process has exited.
                if ($state.ResultPath -and (Test-Path -LiteralPath $state.ResultPath)) {
                    $lines = @(Get-Content -LiteralPath $state.ResultPath -ErrorAction SilentlyContinue)
                    while ($state.NextLine -lt $lines.Count) {
                        try {
                            $row = $lines[$state.NextLine] | ConvertFrom-Json -ErrorAction Stop
                            $state.Items.Add([pscustomobject]@{
                                IP=[string]$row.IP; Hostname=[string]$row.Hostname
                                Latency=[string]$row.Latency; MAC=[string]$row.MAC; Ports=[string]$row.Ports
                            })
                        } catch {}
                        $state.NextLine++
                    }
                }
                $state.Start.IsEnabled = $true
                $state.Stop.IsEnabled = $false
                $state.Export.IsEnabled = ($state.Items.Count -gt 0)
                if ($state.WasStopped) {
                    $state.Status.Text = "Scan stopped | $($state.Items.Count) devices found"
                }
                elseif ($state.Process.ExitCode -ne 0) {
                    $message = if (Test-Path -LiteralPath $state.ErrorPath) {
                        (Get-Content -LiteralPath $state.ErrorPath -Raw).Trim()
                    } else { "Scanner worker exited unexpectedly." }
                    $state.Status.Text = "Scan failed: $message"
                }
                else {
                    $state.Progress.Value = 100
                    $state.Status.Text = "Scan complete | $($state.Items.Count) responding devices"
                }
                $state.Process.Dispose()
                $state.Process = $null
                if ($state.Folder -and (Test-Path -LiteralPath $state.Folder)) {
                    Remove-Item -LiteralPath $state.Folder -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        catch {
            # A temporary file read conflict should not stop or orphan a running scan.
            $state.Status.Text = "Updating scan results; retrying... $($_.Exception.Message)"
        }
    }.GetNewClosure())

    $state.Start.Add_Click({
        if ($state.Process -and -not $state.Process.HasExited) { return }
        try {
            $targets = @(Get-WPFScannerTargets -Target $state.Target.Text)
            if ($targets.Count -lt 1) { throw "No usable addresses were entered." }

            $state.Timer.Stop()
            $state.Items.Clear()
            $state.Progress.Value = 0
            $state.NextLine = 0
            $state.Total = $targets.Count
            $state.WasStopped = $false

            $folder = Join-Path $env:TEMP ("ITBros-IPScan-" + [guid]::NewGuid().ToString('N'))
            [void](New-Item -ItemType Directory -Path $folder -Force)
            $state.Folder = $folder
            $targetFile = Join-Path $folder 'targets.txt'
            $workerFile = Join-Path $folder 'scanner-worker.ps1'
            $state.ResultPath = Join-Path $folder 'results.jsonl'
            $state.ProgressPath = Join-Path $folder 'progress.txt'
            $state.ErrorPath = Join-Path $folder 'error.txt'
            $targets | Set-Content -LiteralPath $targetFile -Encoding Ascii
            $worker | Set-Content -LiteralPath $workerFile -Encoding UTF8

            $argsList = @(
                '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                '-File', ('"' + $workerFile + '"'),
                '-TargetFile', ('"' + $targetFile + '"'),
                '-ResultFile', ('"' + $state.ResultPath + '"'),
                '-ProgressFile', ('"' + $state.ProgressPath + '"'),
                '-ErrorFile', ('"' + $state.ErrorPath + '"')
            )
            if ($state.Ports.IsChecked) { $argsList += '-ProbePorts' }
            $powershellExe = Join-Path $PSHOME 'powershell.exe'
            $state.Process = Start-Process -FilePath $powershellExe -ArgumentList $argsList -PassThru -WindowStyle Hidden -ErrorAction Stop

            $state.Start.IsEnabled = $false
            $state.Stop.IsEnabled = $true
            $state.Export.IsEnabled = $false
            $state.Status.Text = "Scanning $($state.Total) addresses..."
            $state.Timer.Start()
        }
        catch {
            [void][System.Windows.MessageBox]::Show(
                $_.Exception.Message, 'ITBros IP Scanner',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            $state.Start.IsEnabled = $true
            $state.Stop.IsEnabled = $false
        }
    }.GetNewClosure())

    $state.Stop.Add_Click({
        if ($state.Process -and -not $state.Process.HasExited) {
            $state.WasStopped = $true
            try { $state.Process.Kill() } catch {}
            $state.Status.Text = "Stopping scan..."
        }
    }.GetNewClosure())

    $state.Export.Add_Click({
        if ($state.Items.Count -eq 0) { return }
        $dialog = New-Object System.Windows.Forms.SaveFileDialog
        $dialog.Filter = 'CSV files (*.csv)|*.csv'
        $dialog.FileName = 'ITBros-IPScan.csv'
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            try {
                $state.Items | Select-Object IP, Hostname, Latency, MAC, Ports |
                    Export-Csv -LiteralPath $dialog.FileName -NoTypeInformation -Encoding UTF8
                $state.Status.Text = "Exported $($state.Items.Count) devices to CSV."
            }
            catch {
                [void][System.Windows.MessageBox]::Show(
                    "Could not save the CSV: $($_.Exception.Message)",
                    'ITBros IP Scanner', 'OK', 'Error'
                )
            }
        }
    }.GetNewClosure())

    $window.Add_Closing({
        $state.Timer.Stop()
        if ($state.Process) {
            try {
                if (-not $state.Process.HasExited) { $state.Process.Kill() }
            } catch {}
            try { $state.Process.Dispose() } catch {}
        }
        if ($state.Folder -and (Test-Path -LiteralPath $state.Folder)) {
            Remove-Item -LiteralPath $state.Folder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }.GetNewClosure())

    $window.Show() | Out-Null
}
