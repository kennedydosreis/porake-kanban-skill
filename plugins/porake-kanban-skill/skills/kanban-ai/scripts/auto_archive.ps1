param(
    [Parameter(Mandatory)][string]$KanbanDir,
    [int]$Days = 3,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/card_utils.ps1"

$archiveDir = Join-Path $KanbanDir 'archived'
$threshold = Get-DaysAgoEpoch -Days $Days
$archived = 0

foreach ($card in Get-CardObjects -KanbanDir $KanbanDir | Where-Object Status -eq 'done') {
    $doneEpoch = Get-StatusSinceEpoch -Path $card.Path -TargetStatus 'done'
    if ($doneEpoch -le $threshold) {
        if ($DryRun) {
            Write-Host ("[DRY RUN] Would archive: #{0} {1} ({2})" -f $card.Id, $card.Title, $card.Name)
        } else {
            New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
            Move-Item -LiteralPath $card.Path -Destination (Join-Path $archiveDir $card.Name)
            Write-Host ("Archived: #{0} {1} -> archived/{2}" -f $card.Id, $card.Title, $card.Name)
        }
        $archived++
    }
}

if ($archived -eq 0) {
    Write-Host "No cards eligible for archiving (done > $Days days)."
} elseif ($DryRun) {
    Write-Host "($archived cards would be archived)"
} else {
    Write-Host "($archived cards archived)"
}
