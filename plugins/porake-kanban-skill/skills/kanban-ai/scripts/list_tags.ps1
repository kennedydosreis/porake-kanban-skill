param([string]$KanbanDir = '.')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/card_utils.ps1"

Write-Host '=== Tag Usage ==='
Write-Host

$counts = @{}
foreach ($card in Get-CardObjects -KanbanDir $KanbanDir) {
    foreach ($tag in Get-ListValues -Raw $card.Tags) {
        if (-not $counts.ContainsKey($tag)) {
            $counts[$tag] = 0
        }
        $counts[$tag]++
    }
}

foreach ($entry in $counts.GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, @{ Expression = 'Key'; Descending = $false }) {
    '{0,3}  {1}' -f $entry.Value, $entry.Key
}
