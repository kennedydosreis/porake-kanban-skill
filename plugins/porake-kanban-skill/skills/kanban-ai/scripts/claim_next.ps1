param(
    [Parameter(Mandatory)][string]$KanbanDir,
    [Parameter(Mandatory)][string]$Assignee,
    [string]$From = 'todo backlog',
    [int]$WipLimit = 0,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/card_utils.ps1"

if (-not (Test-Path -LiteralPath $KanbanDir -PathType Container)) {
    Write-Error "Error: '$KanbanDir' not found."
}

$fromStatuses = @($From.Replace(',', ' ').Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries))
if ($fromStatuses.Count -eq 0) {
    Write-Error 'Error: --from must include at least one status.'
}

$validStatuses = @('backlog', 'todo', 'doing', 'review', 'done', 'archive')
foreach ($status in $fromStatuses) {
    if ($status -notin $validStatuses) {
        Write-Error "Error: Invalid --from status '$status'."
    }
}

if ($WipLimit -lt 0) {
    Write-Error 'Error: --wip-limit must be a non-negative integer.'
}

$lockPath = $null
try {
    try {
        $lockPath = Acquire-KanbanLock -KanbanDir $KanbanDir -Name 'claim'
    } catch {
        Write-Host "CLAIM BUSY: another claim appears to be running for $KanbanDir."
        Write-Host '  Retry after the other agent finishes claiming a card.'
        exit 1
    }

    if ($WipLimit -gt 0) {
        $doingCount = @(Get-CardObjects -KanbanDir $KanbanDir | Where-Object Status -eq 'doing').Count
        if ($doingCount -ge $WipLimit) {
            Write-Host "WIP LIMIT: Already $doingCount cards in 'doing' (limit: $WipLimit)."
            exit 1
        }
    }

    $statusOrder = @{}
    for ($i = 0; $i -lt $fromStatuses.Count; $i++) {
        $statusOrder[$fromStatuses[$i]] = $i + 1
    }

    $candidates = foreach ($card in Get-CardObjects -KanbanDir $KanbanDir) {
        if (-not $statusOrder.ContainsKey($card.Status)) {
            continue
        }
        if ($card.Assignee -and $card.Assignee -notin @('null', '~')) {
            continue
        }

        $blockers = @(Get-UnresolvedBlockers -KanbanDir $KanbanDir -Path $card.Path)
        if ($blockers.Count -gt 0) {
            continue
        }

        [pscustomobject]@{
            StatusRank   = $statusOrder[$card.Status]
            PriorityRank = $(if ($card.Priority -eq 'High') { 0 } else { 1 })
            Id           = [int]$card.Id
            Card         = $card
        }
    }

    $selected = $candidates | Sort-Object StatusRank, PriorityRank, Id | Select-Object -First 1
    if (-not $selected) {
        Write-Host "NO CLAIMABLE CARD: no unassigned, unblocked cards found in: $($fromStatuses -join ' ')"
        exit 1
    }

    if ($DryRun) {
        Write-Host ("NEXT: #{0} {1} [{2}] -> {3}" -f $selected.Card.Id, $selected.Card.Title, $selected.Card.Status, $Assignee)
        Write-Host ("FILE: {0}" -f $selected.Card.Path)
        exit 0
    }

    Set-CardFields -Path $selected.Card.Path -Updates @{
        status   = 'doing'
        assignee = ('"{0}"' -f $Assignee)
    }
    Add-Narrative -Path $selected.Card.Path -Line ("- {0}: Claimed by '{1}' and moved from '{2}' to 'doing'. (by @assistant)" -f (Get-CurrentDateString), $Assignee, $selected.Card.Status)

    Write-Host ("CLAIMED: #{0} {1} [{2} -> doing] by {3}" -f $selected.Card.Id, $selected.Card.Title, $selected.Card.Status, $Assignee)
    Write-Host ("FILE: {0}" -f $selected.Card.Path)
}
finally {
    Release-KanbanLock -LockPath $lockPath
}
