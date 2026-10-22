# ITBros IP Scanner target validation tests. Run with Invoke-Pester on Windows PowerShell 5.1.
BeforeAll {
    . "$PSScriptRoot/../functions/public/Invoke-WPFIPScanner.ps1"
}

Describe 'ITBros IP Scanner target parsing' {
    It 'accepts a single IPv4 address' {
        $targets = @(Get-WPFScannerTargets -Target '192.168.5.12')
        $targets.Count | Should -Be 1
        $targets[0] | Should -Be '192.168.5.12'
    }

    It 'expands a small inclusive start-end range' {
        $targets = @(Get-WPFScannerTargets -Target '10.0.0.10-10.0.0.12')
        $targets.Count | Should -Be 3
        $targets[0] | Should -Be '10.0.0.10'
        $targets[-1] | Should -Be '10.0.0.12'
    }

    It 'excludes network and broadcast for normal CIDR ranges' {
        $targets = @(Get-WPFScannerTargets -Target '192.168.10.0/30')
        $targets.Count | Should -Be 2
        $targets[0] | Should -Be '192.168.10.1'
        $targets[1] | Should -Be '192.168.10.2'
    }

    It 'keeps both addresses for a /31' {
        @(Get-WPFScannerTargets -Target '192.168.10.0/31').Count | Should -Be 2
    }

    It 'rejects an out-of-range octet' {
        { Get-WPFScannerTargets -Target '192.168.1.256' } | Should -Throw
    }

    It 'rejects more than 1024 addresses' {
        { Get-WPFScannerTargets -Target '10.0.0.0/16' } | Should -Throw
    }

    It 'rejects reversed ranges' {
        { Get-WPFScannerTargets -Target '10.0.0.12-10.0.0.10' } | Should -Throw
    }
}

Describe 'ITBros IP Scanner window XAML' {
    It 'parses successfully with the required WPF XML namespaces' {
        $source = Get-Content -LiteralPath "$PSScriptRoot/../functions/public/Invoke-WPFIPScanner.ps1" -Raw
        $match = [regex]::Match($source, "(?s)\`$scannerXaml = @'\r?\n(.*?)\r?\n'@")
        $match.Success | Should -Be $true
        { [xml]$match.Groups[1].Value } | Should -Not -Throw
    }

    It 'loads an actual WPF scanner window on Windows' {
        Add-Type -AssemblyName PresentationFramework
        $source = Get-Content -LiteralPath "$PSScriptRoot/../functions/public/Invoke-WPFIPScanner.ps1" -Raw
        $match = [regex]::Match($source, "(?s)\`$scannerXaml = @'\r?\n(.*?)\r?\n'@")
        $match.Success | Should -Be $true
        $reader = $null
        $stringReader = $null
        $window = $null
        try {
            $stringReader = New-Object System.IO.StringReader($match.Groups[1].Value)
            $reader = [System.Xml.XmlReader]::Create($stringReader)
            $window = [System.Windows.Markup.XamlReader]::Load($reader)
            $window | Should -Not -BeNullOrEmpty
        }
        finally {
            if ($window) { $window.Close() }
            if ($reader) { $reader.Dispose() }
            if ($stringReader) { $stringReader.Dispose() }
        }
    }
}

Describe 'IP Scanner result display' {
    It 'extracts the IPv4 value instead of PowerShell file-provider metadata' {
        $raw = [pscustomobject]@{
            IP = '@{value=192.168.1.107; PSPath=C:\Users\Test\scan.txt}'
            Hostname = 'DESKTOP-TEST'
            DeviceType = 'Device'
            Latency = '5'
            MAC = 'AA-BB-CC-DD-EE-FF'
            Ports = '80, 445'
        }
        $result = Convert-WPFScannerResult -Row $raw
        $result.IP | Should -Be '192.168.1.107'
        $result.Hostname | Should -Be 'DESKTOP-TEST'
        @($result.WebLinks).Count | Should -Be 1
        $result.WebLinks[0].Url.AbsoluteUri | Should -Be 'http://192.168.1.107:80/'
    }

    It 'creates separate HTTP and HTTPS links but no SMB browser link' {
        $raw = [pscustomobject]@{
            IP = '192.168.1.9'
            Hostname = '-'
            DeviceType = 'Likely printer'
            Latency = '2'
            MAC = '-'
            Ports = '80, 443, 445, 631, 9100'
        }
        $result = Convert-WPFScannerResult -Row $raw
        @($result.WebLinks).Count | Should -Be 3
        ($result.WebLinks | ForEach-Object { $_.Label }) -join ',' | Should -Be '80,443,631'
    }

    It 'rejects rows without an IPv4 address' {
        $invalid = [pscustomobject]@{ IP='C:\Users\Test'; Ports='80'; Hostname='-' }
        Convert-WPFScannerResult -Row $invalid | Should -BeNullOrEmpty
    }
}

Describe 'IP Scanner ping and filtering safety' {
    It 'restricts results to confirmed ICMP responders and supports printer filter' {
        $source = Get-Content -LiteralPath "$PSScriptRoot/../functions/public/Invoke-WPFIPScanner.ps1" -Raw
        $source | Should -Match '\$alive = @\(\$pings \| Where-Object \{ \$_\.Alive \}\)'
        $source | Should -Not -Match '\$check\.Entry\.Alive\s*=\s*\$true'
        $source | Should -Match '\-PrintersOnly'
        $source | Should -Match '\-ResolveNetBIOS'
    }
}
