param(
    [Parameter(Mandatory)][string]$KanbanDir,
    [Parameter(Mandatory)][string]$CardId,
    [Parameter(Mandatory)][ValidateSet('approve', 'changes')][string]$Action,
    [Parameter(Mandatory)][string]$Reviewer,
    [string]$NextAssignee = ""
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
if ($currentStatus -ne 'review') {
    Write-Host "Error: Card #$CardId is '$currentStatus', not 'review'."
    Write-Host '  Submit it with submit_for_review.sh before resolving review.'
    exit 1
}

$normalizedReviewer = Normalize-FieldValue -Value $Reviewer
if (-not $NextAssignee) {
    $NextAssignee = $normalizedReviewer
} else {
    $NextAssignee = Normalize-FieldValue -Value $NextAssignee
}

$lockPath = $null
try {
    try {
        $lockPath = Acquire-KanbanLock -KanbanDir $KanbanDir -Name 'review'
    } catch {
        Write-Host "REVIEW BUSY: another review action appears to be running for $KanbanDir."
        exit 1
    }

    if ($Action -eq 'approve') {
        Set-CardFields -Path $cardFile -Updates @{
            status   = 'done'
            assignee = '""'
        }
        Add-Narrative -Path $cardFile -Line ("- {0}: Approved by '{1}' and finalized. (by @assistant)" -f (Get-CurrentDateString), $normalizedReviewer)
        Write-Host ("APPROVED: #{0} {1} [review -> done] by {2}" -f $CardId, (Get-CardTitle -Path $cardFile), $normalizedReviewer)
    } else {
        Set-CardFields -Path $cardFile -Updates @{
            status   = 'doing'
            priority = 'High'
            assignee = ('"{0}"' -f $NextAssignee)
        }
        Add-Narrative -Path $cardFile -Line ("- {0}: Changes requested by '{1}'; pulled back into development with High priority for '{2}'. (by @assistant)" -f (Get-CurrentDateString), $normalizedReviewer, $NextAssignee)
        Write-Host ("CHANGES: #{0} {1} [review -> doing] assigned to {2} with High priority" -f $CardId, (Get-CardTitle -Path $cardFile), $NextAssignee)
    }

    Write-Host ("FILE: {0}" -f $cardFile)
}
finally {
    Release-KanbanLock -LockPath $lockPath
}
