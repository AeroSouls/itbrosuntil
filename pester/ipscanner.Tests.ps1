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
