param([Parameter(Mandatory)][string]$KanbanDir)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/card_utils.ps1"

$today = Get-CurrentDateString
$todayEpoch = [int64]([DateTimeOffset](Get-Date)).ToUnixTimeSeconds()

Write-Host "=== KANBAN REPORT - $today ==="
Write-Host

Write-Host 'CARD DISTRIBUTION:'
$total = 0
foreach ($status in @('backlog', 'todo', 'doing', 'review', 'done')) {
    $count = @(Get-CardObjects -KanbanDir $KanbanDir | Where-Object Status -eq $status).Count
    $total += $count
    $bar = if ($count -gt 0) { ('█' * $count) } else { '' }
    '{0,-10} {1,2}  {2}' -f ('  ' + $status), $count, $bar
}
$archived = if (Test-Path -LiteralPath (Join-Path $KanbanDir 'archived')) { @(Get-ChildItem -LiteralPath (Join-Path $KanbanDir 'archived') -File -Filter *.md).Count } else { 0 }
'{0,-10} {1,2}' -f '  archived', $archived
"  Total active: $total"
Write-Host

Write-Host 'PRIORITY BREAKDOWN:'
$active = @(Get-CardObjects -KanbanDir $KanbanDir | Where-Object { $_.Status -notin @('done', 'archive') })
$high = @($active | Where-Object Priority -eq 'High').Count
$normal = $active.Count - $high
Write-Host "  High:   $high"
Write-Host "  Normal: $normal"
Write-Host

Write-Host 'OVERDUE CARDS:'
$overdue = @()
foreach ($card in $active) {
    if (-not $card.DueDate) { continue }
    $dueEpoch = Convert-DateToEpoch -Date $card.DueDate
    if ($dueEpoch -gt 0 -and $dueEpoch -lt $todayEpoch) {
        $daysOver = [int](($todayEpoch - $dueEpoch) / 86400)
        $overdue += "  #$($card.Id) $($card.Title)  (due: $($card.DueDate), ${daysOver}d overdue)"
    }
}
if ($overdue.Count -eq 0) { Write-Host '  (none)' } else { $overdue }
Write-Host

Write-Host "AGING CARDS (doing > 7 days):"
$aging = @()
foreach ($card in Get-CardObjects -KanbanDir $KanbanDir | Where-Object Status -eq 'doing') {
    $doingSince = Get-StatusSinceEpoch -Path $card.Path -TargetStatus 'doing'
    $ageDays = [int](($todayEpoch - $doingSince) / 86400)
    if ($ageDays -gt 7) {
        $aging += "  #$($card.Id) $($card.Title)  ($ageDays days in doing)"
    }
}
if ($aging.Count -eq 0) { Write-Host '  (none)' } else { $aging }
Write-Host

Write-Host 'THROUGHPUT:'
$weekAgo = Get-DaysAgoEpoch -Days 7
$monthAgo = Get-DaysAgoEpoch -Days 30
$done7 = 0
$done30 = 0
foreach ($card in Get-CardObjects -KanbanDir $KanbanDir -IncludeArchived | Where-Object Status -eq 'done') {
    $doneSince = Get-StatusSinceEpoch -Path $card.Path -TargetStatus 'done'
    if ($doneSince -ge $weekAgo) { $done7++ }
    if ($doneSince -ge $monthAgo) { $done30++ }
}
Write-Host "  Last 7 days:  $done7 cards"
Write-Host "  Last 30 days: $done30 cards"
Write-Host

Write-Host 'DEPENDENCY CHAINS:'
$chains = @()
foreach ($card in $active) {
    $blockers = @(Get-UnresolvedBlockers -KanbanDir $KanbanDir -Path $card.Path)
    if ($blockers.Count -gt 0) {
        $chains += "  #$($card.Id) $($card.Title)  <- blocked by $($blockers -join ' ')"
    }
}
if ($chains.Count -eq 0) { Write-Host '  (no active dependencies)' } else { $chains }
