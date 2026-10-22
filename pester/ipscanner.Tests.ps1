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
