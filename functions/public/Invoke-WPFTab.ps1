function Invoke-WPFTab {
    <#
    .SYNOPSIS
        Selects a tab by its actual control instead of its numbered name.
    #>
    param([Parameter(Mandatory=$true)][string]$ClickedTab)

    $tabName = $ClickedTab -replace 'BT$', ''
    if (-not $sync.ContainsKey($ClickedTab) -or -not $sync.ContainsKey($tabName)) { return }

    $tabControl = $sync['WPFTabNav']
    $tabItem = $sync[$tabName]
    if ($null -eq $tabControl -or $null -eq $tabItem) { return }

    $tabIndex = $tabControl.Items.IndexOf($tabItem)
    if ($tabIndex -lt 0) { return }

    $buttons = Get-WinUtilVariables -Type ToggleButton |
        Where-Object { $_ -like 'WPFTab?BT' }
    foreach ($name in $buttons) {
        $sync[$name].IsChecked = ($name -eq $ClickedTab)
    }
    $tabControl.SelectedIndex = $tabIndex

    if ($sync.ContainsKey('CheckboxFilter')) {
        $sync.CheckboxFilter.Visibility = if ($ClickedTab -eq 'WPFTab1BT') { 'Visible' } else { 'Collapsed' }
    }
}
