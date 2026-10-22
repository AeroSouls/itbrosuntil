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

function Convert-WPFScannerResult {
    <#
    .SYNOPSIS
        Normalizes one worker result for the table and safe, clickable web links.
    #>
    param([Parameter(Mandatory=$true)]$Row)

    # Never display provider metadata or file paths as an IP address.
    $ipMatch = [regex]::Match([string]$Row.IP, '(?<!\d)(?:\d{1,3}\.){3}\d{1,3}(?!\d)')
    if (-not $ipMatch.Success) { return $null }
    $ip = $ipMatch.Value
    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($ip, [ref]$parsed)) { return $null }
    if ($parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { return $null }

    $webLinks = New-Object 'System.Collections.Generic.List[object]'
    $portString = [string]$Row.Ports
    foreach ($port in @(80, 443, 631, 8080, 8443)) {
        if ($portString -match "(^|,\s*)$port(\s*,|$)") {
            $scheme = if ($port -in @(443,8443)) { 'https' } else { 'http' }
            $uri = "$scheme" + "://$ip" + ":$port/"
            $webLinks.Add([pscustomobject]@{
                Label = [string]$port
                Url = [System.Uri]::new($uri)
            })
        }
    }

    $name = [string]$Row.Hostname
    if ([string]::IsNullOrWhiteSpace($name)) { $name = '-' }
    $type = [string]$Row.DeviceType
    if ([string]::IsNullOrWhiteSpace($type)) { $type = 'Device' }

    [pscustomobject]@{
        IP = [string]$ip
        Hostname = $name
        DeviceType = $type
        Latency = [string]$Row.Latency
        MAC = [string]$Row.MAC
        Ports = if ($portString) { $portString } else { '-' }
        WebLinks = @($webLinks.ToArray())
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
                    <CheckBox Name="ScanNetBIOS" Content="Try Windows/NetBIOS device names (slower)"
                              Foreground="#BBD0E1" Margin="0,8,0,0" IsChecked="False"/>
                    <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                        <TextBlock Text="SHOW:" Foreground="#BECEDF" FontSize="11" FontWeight="Bold"
                                   VerticalAlignment="Center" Margin="0,0,12,0"/>
                        <ComboBox Name="ScanFilter" SelectedIndex="0" Height="33" Width="200"
                                  Background="#E6EDF6" Foreground="#17273A" FontSize="12"
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
            ("IP Scanner TEST v0.3 could not open." + [Environment]::NewLine + [Environment]::NewLine + $summary),
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
        NetBIOS = $window.FindName('ScanNetBIOS')
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

    # Open only discovered HTTP(S) service URLs on an explicit user click.
    $navigate = [System.Windows.Navigation.RequestNavigateEventHandler] {
        param($sender, $args)
        $uri = $args.Uri
        $args.Handled = $true
        if (-not $uri -or $uri.Scheme -notin @('http','https')) { return }
        $address = $null
        if (-not [System.Net.IPAddress]::TryParse($uri.Host, [ref]$address)) { return }
        if ($address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { return }
        if ($uri.Port -notin @(80,443,631,8080,8443)) { return }
        try { Start-Process -FilePath $uri.AbsoluteUri -ErrorAction Stop }
        catch {
            [void][System.Windows.MessageBox]::Show(
                "Unable to open the web page: $($_.Exception.Message)",
                'ITBros IP Scanner', 'OK', 'Warning'
            )
        }
    }
    $state.Results.AddHandler([System.Windows.Documents.Hyperlink]::RequestNavigateEvent, $navigate)



    $worker = @'
param(
    [Parameter(Mandatory=$true)][string]$TargetFile,
    [Parameter(Mandatory=$true)][string]$ResultFile,
    [Parameter(Mandatory=$true)][string]$ProgressFile,
    [Parameter(Mandatory=$true)][string]$ErrorFile,
    [switch]$ProbePorts,
    [switch]$PrintersOnly,
    [switch]$ResolveNetBIOS
)
$ErrorActionPreference = 'Stop'

function Get-ScannerNetBIOSName {
    param([string]$IP)
    $exe = Join-Path $env:SystemRoot 'System32\nbtstat.exe'
    if (-not (Test-Path -LiteralPath $exe)) { return $null }

    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $exe
    $info.Arguments = "-A $IP"
    $info.CreateNoWindow = $true
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $proc = $null
    try {
        $proc = [System.Diagnostics.Process]::Start($info)
        if (-not $proc.WaitForExit(850)) {
            try { $proc.Kill() } catch {}
            return $null
        }
        $result = $proc.StandardOutput.ReadToEnd()
        $hit = [regex]::Match($result, '(?im)^\s*([^\s<>]{1,63})\s+<00>\s+UNIQUE\s+Registered')
        if ($hit.Success) { return $hit.Groups[1].Value }
    }
    catch {}
    finally { if ($proc) { $proc.Dispose() } }
    return $null
}

try {
    # Use .NET file I/O to avoid Get-Content's extended PSPath/Value metadata.
    $addresses = @([System.IO.File]::ReadAllLines($TargetFile))
    $count = $addresses.Count
    [System.IO.File]::WriteAllText($ResultFile, '')
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $dnsHint = '(?i)(printer|print|laserjet|officejet|deskjet|brother|xerox|ricoh|kyocera|lexmark|epson|canon|konica|zebra|sharp|bizhub)'

    for ($offset = 0; $offset -lt $count; $offset += 32) {
        $last = [math]::Min($offset + 31, $count - 1)
        $batch = @($addresses[$offset..$last])
        $pings = @()
        foreach ($raw in $batch) {
            # Restrict probes to valid IPv4 addresses, even if a stale target list contains metadata.
            $match = [regex]::Match([string]$raw, '(?<!\d)(?:\d{1,3}\.){3}\d{1,3}(?!\d)')
            if (-not $match.Success) { continue }
            $ip = $match.Value
            $ipObject = $null
            if (-not [System.Net.IPAddress]::TryParse($ip, [ref]$ipObject)) { continue }
            if ($ipObject.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { continue }

            $client = New-Object System.Net.NetworkInformation.Ping
            try {
                $task = $client.SendPingAsync($ip, 650)
                $pings += [pscustomobject]@{
                    IP=[string]$ip; Client=$client; Task=$task;
                    Alive=$false; Latency='-'; Ports=@()
                }
            }
            catch { $client.Dispose() }
        }

        $pingTasks = @($pings | ForEach-Object { $_.Task })
        if ($pingTasks.Count) {
            try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$pingTasks, 950) }
            catch {}
        }
        foreach ($item in $pings) {
            try {
                if ($item.Task.IsCompleted -and -not $item.Task.IsFaulted -and
                    -not $item.Task.IsCanceled -and
                    $item.Task.Result.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                    $item.Alive = $true
                    $item.Latency = [string]$item.Task.Result.RoundtripTime
                }
            } catch {}
            finally { $item.Client.Dispose() }
        }

        # Nothing other than a successful ICMP reply can mark a device as responsive.
        $alive = @($pings | Where-Object { $_.Alive })
        if ($alive.Count -gt 0 -and ($ProbePorts -or $PrintersOnly)) {
            $portsToCheck = if ($PrintersOnly) { @(80,443,515,631,9100) } else { @(80,443,445,3389) }
            $checks = @()
            foreach ($item in $alive) {
                foreach ($port in $portsToCheck) {
                    $tcp = New-Object System.Net.Sockets.TcpClient
                    try {
                        $task = $tcp.ConnectAsync($item.IP, $port)
                        $checks += [pscustomobject]@{ Entry=$item; Port=$port; Client=$tcp; Task=$task }
                    }
                    catch { $tcp.Dispose() }
                }
            }
            if ($checks.Count) {
                try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($checks | ForEach-Object { $_.Task }), 750) }
                catch {}
            }
            foreach ($check in $checks) {
                try {
                    if ($check.Task.IsCompleted -and -not $check.Task.IsFaulted -and
                        -not $check.Task.IsCanceled -and $check.Client.Connected) {
                        $check.Entry.Ports += [int]$check.Port
                    }
                }
                catch {}
                finally { $check.Client.Dispose() }
            }
        }

        $dnsQueries = @()
        foreach ($item in $alive) {
            try {
                $task = [System.Net.Dns]::GetHostEntryAsync([System.Net.IPAddress]::Parse($item.IP))
                $dnsQueries += [pscustomobject]@{ IP=$item.IP; Task=$task }
            }
            catch {}
        }
        if ($dnsQueries.Count) {
            try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($dnsQueries | ForEach-Object { $_.Task }), 1800) }
            catch {}
        }
        $names = @{}
        foreach ($query in $dnsQueries) {
            try {
                if ($query.Task.IsCompleted -and -not $query.Task.IsFaulted -and -not $query.Task.IsCanceled) {
                    $hostname = [string]$query.Task.Result.HostName
                    if ($hostname -and $hostname -ne $query.IP) { $names[$query.IP] = $hostname }
                }
            } catch {}
        }

        $neighbors = @{}
        try {
            Get-NetNeighbor -AddressFamily IPv4 -ErrorAction Stop | ForEach-Object {
                $mac = [string]$_.LinkLayerAddress
                if ($mac -and $mac -ne '00-00-00-00-00-00') {
                    $neighbors[[string]$_.IPAddress] = $mac
                }
            }
        } catch {}

        foreach ($item in $alive) {
            $hostname = if ($names.ContainsKey($item.IP)) { $names[$item.IP] } else { '-' }
            if ($hostname -eq '-' -and $ResolveNetBIOS) {
                $netbios = Get-ScannerNetBIOSName -IP $item.IP
                if ($netbios) { $hostname = [string]$netbios }
            }
            $mac = if ($neighbors.ContainsKey($item.IP)) { $neighbors[$item.IP] } else { '-' }
            $distinctPorts = @($item.Ports | Sort-Object -Unique)
            $looksLikePrinter = (($distinctPorts | Where-Object { $_ -in @(515,631,9100) }).Count -gt 0) -or
                                ($hostname -match $dnsHint)
            if ($PrintersOnly -and -not $looksLikePrinter) { continue }

            $record = [pscustomobject]@{
                IP = [string]$item.IP
                Hostname = [string]$hostname
                DeviceType = if ($looksLikePrinter) { 'Likely printer' } else { 'Device' }
                Latency = [string]$item.Latency
                MAC = [string]$mac
                Ports = if ($distinctPorts.Count) { $distinctPorts -join ', ' } else { '-' }
            }
            $line = ($record | ConvertTo-Json -Compress -Depth 3) + [Environment]::NewLine
            [System.IO.File]::AppendAllText($ResultFile, $line, $utf8)
        }

        [System.IO.File]::WriteAllText($ProgressFile, [string]($last + 1))
    }
}
catch {
    try { [System.IO.File]::WriteAllText($ErrorFile, $_.Exception.Message) } catch {}
    exit 1
}
'@

    # Read plain lines, without PowerShell filesystem provider-added metadata.
    $updateRows = {
        if ([string]::IsNullOrWhiteSpace($state.ResultPath) -or
            -not [System.IO.File]::Exists($state.ResultPath)) { return }
        try {
            $lines = [System.IO.File]::ReadAllLines($state.ResultPath)
            while ($state.NextLine -lt $lines.Length) {
                $line = [string]$lines[$state.NextLine]
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    try {
                        $parsed = $line | ConvertFrom-Json -ErrorAction Stop
                        $device = Convert-WPFScannerResult -Row $parsed
                        if ($null -ne $device) { $state.Items.Add($device) }
                    }
                    catch { break } # Incomplete JSON line; read it on next tick.
                }
                $state.NextLine++
            }
            $state.Export.IsEnabled = ($state.Items.Count -gt 0)
        }
        catch {} # Transient file sharing during a write is normal.
    }.GetNewClosure()

    $state.Timer = New-Object System.Windows.Threading.DispatcherTimer
    $state.Timer.Interval = [TimeSpan]::FromMilliseconds(350)
    $state.Timer.Add_Tick({
        if (-not $state.Process) { return }

        [void]$updateRows.Invoke()
        $done = 0
        if ($state.ProgressPath -and [System.IO.File]::Exists($state.ProgressPath)) {
            try {
                $value = [System.IO.File]::ReadAllText($state.ProgressPath).Trim()
                if ($value -match '^\d+$') { $done = [int]$value }
            } catch {}
        }

        if ($state.Total -gt 0) {
            $state.Progress.Value = [math]::Min(100, (100 * $done / $state.Total))
        }
        $state.Status.Text = "Scanned $done / $($state.Total) addresses | $($state.Items.Count) ping-responsive matches"

        if (-not $state.Process.HasExited) { return }

        $state.Timer.Stop()
        [void]$updateRows.Invoke()
        $state.Start.IsEnabled = $true
        $state.Stop.IsEnabled = $false
        $state.Export.IsEnabled = ($state.Items.Count -gt 0)

        if ($state.WasStopped) {
            $state.Status.Text = "Scan stopped | $($state.Items.Count) devices"
        }
        elseif ($state.Process.ExitCode -ne 0) {
            $detail = 'Scanner worker exited unexpectedly.'
            if ($state.ErrorPath -and [System.IO.File]::Exists($state.ErrorPath)) {
                try { $detail = [System.IO.File]::ReadAllText($state.ErrorPath).Trim() } catch {}
            }
            $state.Status.Text = "Scan failed: $detail"
        }
        else {
            $state.Progress.Value = 100
            $state.Status.Text = "Scan complete | $($state.Items.Count) matching ping-responsive devices"
        }

        $state.Process.Dispose()
        $state.Process = $null
        if ($state.Folder -and [System.IO.Directory]::Exists($state.Folder)) {
            try { [System.IO.Directory]::Delete($state.Folder, $true) } catch {}
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
            $targetText = ((@($targets | ForEach-Object { [string]$_ }) -join [Environment]::NewLine) + [Environment]::NewLine)
            [System.IO.File]::WriteAllText($targetFile, $targetText)
            [System.IO.File]::WriteAllText($workerFile, $worker, [System.Text.UTF8Encoding]::new($false))

            $argsList = @(
                '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                '-File', ('"' + $workerFile + '"'),
                '-TargetFile', ('"' + $targetFile + '"'),
                '-ResultFile', ('"' + $state.ResultPath + '"'),
                '-ProgressFile', ('"' + $state.ProgressPath + '"'),
                '-ErrorFile', ('"' + $state.ErrorPath + '"')
            )
            if ($state.Ports.IsChecked) { $argsList += '-ProbePorts' }
            if ($state.Filter.SelectedIndex -eq 1) { $argsList += '-PrintersOnly' }
            if ($state.NetBIOS.IsChecked) { $argsList += '-ResolveNetBIOS' }
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
                $state.Items | Select-Object IP, Hostname, DeviceType, Latency, MAC, Ports |
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
