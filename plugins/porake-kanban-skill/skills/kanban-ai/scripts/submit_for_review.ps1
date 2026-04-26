param(
    [Parameter(Mandatory)][string]$KanbanDir,
    [Parameter(Mandatory)][string]$CardId,
    [Parameter(Mandatory)][string]$Reviewer
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/card_utils.ps1"

if (-not (Test-Path -LiteralPath $KanbanDir -PathType Container)) {
    Write-Error "Error: '$KanbanDir' not found."
}

$cardFile = Find-CardFileById -KanbanDir $KanbanDir -CardId $CardId
if (-not $cardFile) {
    Write-Error "Error: Card #$CardId not found in $KanbanDir"
}

$currentStatus = Get-CardField -Path $cardFile -Field 'status'
if ($currentStatus -in @('done', 'archive')) {
    Write-Error "Error: Card #$CardId is already '$currentStatus' and cannot be submitted for review."
}

$currentAssignee = Normalize-FieldValue -Value (Get-CardField -Path $cardFile -Field 'assignee')
$normalizedReviewer = Normalize-FieldValue -Value $Reviewer
if ($currentAssignee -and $currentAssignee -eq $normalizedReviewer) {
    Write-Host "Error: Reviewer '$normalizedReviewer' is already the card assignee."
    Write-Host '  Choose the other provider for review.'
    exit 1
}

$lockPath = $null
try {
    try {
        $lockPath = Acquire-KanbanLock -KanbanDir $KanbanDir -Name 'review'
    } catch {
        Write-Host "REVIEW BUSY: another review action appears to be running for $KanbanDir."
        exit 1
    }

    Set-CardFields -Path $cardFile -Updates @{
        status   = 'review'
        assignee = ('"{0}"' -f $normalizedReviewer)
    }

    $actor = if ($currentAssignee) { "'$currentAssignee'" } else { 'the current agent' }
    Add-Narrative -Path $cardFile -Line ("- {0}: Submitted for review by {1}; assigned review to '{2}'. (by @assistant)" -f (Get-CurrentDateString), $actor, $normalizedReviewer)

    Write-Host ("REVIEW: #{0} {1} [{2} -> review] assigned to {3}" -f $CardId, (Get-CardTitle -Path $cardFile), $currentStatus, $normalizedReviewer)
    Write-Host ("FILE: {0}" -f $cardFile)
}
finally {
    Release-KanbanLock -LockPath $lockPath
}
