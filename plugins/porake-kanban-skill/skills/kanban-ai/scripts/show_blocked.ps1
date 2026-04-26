param([string]$KanbanDir = '.')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/card_utils.ps1"

Write-Host '=== Blocked Cards ==='
Write-Host

foreach ($card in Get-CardObjects -KanbanDir $KanbanDir) {
    if ($card.Status -in @('done', 'archive')) {
        continue
    }

    $blockers = @(Get-UnresolvedBlockers -KanbanDir $KanbanDir -Path $card.Path)
    if ($blockers.Count -eq 0) {
        continue
    }

    '{0,-4} {1,-12} {2}' -f ('#{0}' -f ($card.Id ?? '?')), ('[{0}]' -f $card.Status), $card.Title
    '  Blocked by: {0}' -f ($blockers -join ' ')
    ''
}
