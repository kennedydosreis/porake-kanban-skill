param(
    [Parameter(Mandatory)][string]$KanbanDir,
    [int]$Days = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/card_utils.ps1"

$today = Get-CurrentDateString
$threshold = Get-DaysAgoEpoch -Days $Days
$todayEpoch = [int64]([DateTimeOffset](Get-Date)).ToUnixTimeSeconds()

Write-Host "=== STANDUP $today ==="
Write-Host

Write-Host 'IN PROGRESS:'
$inProgress = @(Get-CardObjects -KanbanDir $KanbanDir | Where-Object Status -eq 'doing')
if ($inProgress.Count -eq 0) {
    Write-Host '  (nothing in progress)'
} else {
    foreach ($card in $inProgress) {
        $line = "  #$($card.Id) $($card.Title)"
        if ($card.Assignee) { $line += " ($($card.Assignee))" }
        if ($card.Priority -eq 'High') { $line += ' [HIGH]' }
        Write-Host $line
    }
}
Write-Host

Write-Host 'IN REVIEW:'
$inReview = @(Get-CardObjects -KanbanDir $KanbanDir | Where-Object Status -eq 'review')
if ($inReview.Count -eq 0) {
    Write-Host '  (nothing in review)'
} else {
    foreach ($card in $inReview) {
        $line = "  #$($card.Id) $($card.Title)"
        if ($card.Assignee) { $line += " (review: $($card.Assignee))" }
        if ($card.Priority -eq 'High') { $line += ' [HIGH]' }
        Write-Host $line
    }
}
Write-Host

Write-Host 'BLOCKED:'
$blockedCards = @()
foreach ($card in Get-CardObjects -KanbanDir $KanbanDir) {
    if ($card.Status -in @('done', 'archive')) { continue }
    $blockers = @(Get-UnresolvedBlockers -KanbanDir $KanbanDir -Path $card.Path)
    if ($blockers.Count -gt 0) {
        $blockedCards += [pscustomobject]@{ Card = $card; Blockers = $blockers }
    }
}
if ($blockedCards.Count -eq 0) {
    Write-Host '  (nothing blocked)'
} else {
    foreach ($item in $blockedCards) {
        Write-Host ("  #{0} {1}  [blocked by: {2}]" -f $item.Card.Id, $item.Card.Title, ($item.Blockers -join ' '))
    }
}
Write-Host

Write-Host 'RECENTLY DONE:'
$recentDone = @()
foreach ($card in Get-CardObjects -KanbanDir $KanbanDir -IncludeArchived | Where-Object Status -eq 'done') {
    $doneSince = Get-StatusSinceEpoch -Path $card.Path -TargetStatus 'done'
    if ($doneSince -ge $threshold) {
        $recentDone += $card
    }
}
if ($recentDone.Count -eq 0) {
    Write-Host '  (nothing completed recently)'
} else {
    foreach ($card in $recentDone) {
        $line = "  #$($card.Id) $($card.Title)"
        if ($card.Assignee) { $line += " ($($card.Assignee))" }
        Write-Host $line
    }
}
Write-Host

Write-Host 'UP NEXT (todo):'
$upNext = foreach ($card in Get-CardObjects -KanbanDir $KanbanDir | Where-Object Status -eq 'todo') {
    $isBlocked = @(Get-UnresolvedBlockers -KanbanDir $KanbanDir -Path $card.Path).Count -gt 0
    [pscustomobject]@{
        Card         = $card
        PriorityRank = $(if ($card.Priority -eq 'High') { 0 } else { 1 })
        BlockedRank  = $(if ($isBlocked) { 1 } else { 0 })
        IsBlocked    = $isBlocked
    }
}
$upNext = @($upNext | Sort-Object PriorityRank, BlockedRank, @{ Expression = { [int]$_.Card.Id } } | Select-Object -First 5)
if ($upNext.Count -eq 0) {
    Write-Host '  (backlog is empty)'
} else {
    foreach ($item in $upNext) {
        $line = "  #$($item.Card.Id) $($item.Card.Title)"
        if ($item.Card.Priority -eq 'High') { $line += ' [HIGH]' }
        if ($item.IsBlocked) { $line += ' [BLOCKED]' }
        Write-Host $line
    }
}
Write-Host

Write-Host '--- BOARD SUMMARY ---'
foreach ($status in @('backlog', 'todo', 'doing', 'review', 'done')) {
    $count = @(Get-CardObjects -KanbanDir $KanbanDir | Where-Object Status -eq $status).Count
    '{0,-10} {1}' -f ('  ' + $status), $count
}
$archivedCount = if (Test-Path -LiteralPath (Join-Path $KanbanDir 'archived')) { @(Get-ChildItem -LiteralPath (Join-Path $KanbanDir 'archived') -File -Filter *.md).Count } else { 0 }
'{0,-10} {1}' -f '  archived', $archivedCount
