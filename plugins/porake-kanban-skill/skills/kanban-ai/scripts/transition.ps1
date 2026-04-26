param(
    [Parameter(Mandatory)][string]$KanbanDir,
    [Parameter(Mandatory)][string]$CardId,
    [Parameter(Mandatory)][string]$NewStatus,
    [int]$WipLimit = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/card_utils.ps1"

$validStatuses = @('backlog', 'todo', 'doing', 'review', 'done', 'archive')
if ($NewStatus -notin $validStatuses) {
    Write-Error ("Error: Invalid status '{0}'. Must be one of: {1}" -f $NewStatus, ($validStatuses -join ' '))
}

$cardFile = Find-CardFileById -KanbanDir $KanbanDir -CardId $CardId
if (-not $cardFile) {
    Write-Error "Error: Card #$CardId not found in $KanbanDir"
}

$currentStatus = Get-CardField -Path $cardFile -Field 'status'
$cardTitle = Get-CardTitle -Path $cardFile

if ($currentStatus -eq $NewStatus) {
    Write-Host "Card #$CardId is already '$NewStatus'. No change."
    exit 0
}

if ($NewStatus -eq 'doing') {
    $blockers = @(Get-UnresolvedBlockers -KanbanDir $KanbanDir -Path $cardFile)
    if ($blockers.Count -gt 0) {
        Write-Host "BLOCKED: Card #$CardId cannot move to 'doing'."
        Write-Host "  Unresolved blockers: $($blockers -join ' ')"
        exit 1
    }

    if ($WipLimit -gt 0) {
        $doingCount = @(Get-CardObjects -KanbanDir $KanbanDir | Where-Object Status -eq 'doing').Count
        if ($doingCount -ge $WipLimit) {
            Write-Host "WIP LIMIT: Already $doingCount cards in 'doing' (limit: $WipLimit)."
            Write-Host '  Finish or move existing cards before starting new work.'
            exit 1
        }
    }
}

Set-CardFields -Path $cardFile -Updates @{ status = $NewStatus }
Add-Narrative -Path $cardFile -Line ("- {0}: Status changed from '{1}' to '{2}'. (by @assistant)" -f (Get-CurrentDateString), $currentStatus, $NewStatus)

Write-Host ("OK: Card #{0} '{1}' moved from '{2}' -> '{3}'" -f $CardId, $cardTitle, $currentStatus, $NewStatus)
