param([Parameter(Mandatory)][string]$KanbanDir)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/card_utils.ps1"

$errors = 0
$warnings = 0
$validStatuses = @('backlog', 'todo', 'doing', 'review', 'done', 'archive')
$idMap = @{}

Write-Host '=== BOARD VALIDATION ==='
Write-Host

$cards = @(Get-CardObjects -KanbanDir $KanbanDir -IncludeArchived)
foreach ($card in $cards) {
    if (-not $card.Id) {
        Write-Host "ERROR: $($card.Name) has no 'id' field"
        $errors++
        continue
    }

    if ($idMap.ContainsKey($card.Id)) {
        Write-Host "ERROR: Duplicate ID #$($card.Id) in '$($card.Name)' and '$($idMap[$card.Id])'"
        $errors++
    } else {
        $idMap[$card.Id] = $card.Name
    }

    if (-not $card.Status) {
        Write-Host "ERROR: $($card.Name) (#$($card.Id)) has no 'status' field"
        $errors++
    } elseif ($card.Status -notin $validStatuses) {
        Write-Host "ERROR: $($card.Name) (#$($card.Id)) has invalid status '$($card.Status)'"
        $errors++
    }

    if ($card.Priority -and $card.Priority -notin @('High', 'Normal')) {
        Write-Host "WARNING: $($card.Name) (#$($card.Id)) has unusual priority '$($card.Priority)' (expected: High or Normal)"
        $warnings++
    }

    if (-not (Select-String -Path $card.Path -Pattern '^## Narrative' -Quiet)) {
        Write-Host "WARNING: $($card.Name) (#$($card.Id)) has no '## Narrative' section"
        $warnings++
    }
}

foreach ($card in $cards) {
    if (-not $card.Id) {
        continue
    }
    foreach ($blockedId in Get-ListValues -Raw $card.BlockedBy) {
        if (-not $idMap.ContainsKey($blockedId)) {
            Write-Host "ERROR: #$($card.Id) references non-existent blocker #$blockedId"
            $errors++
        }
    }
}

Write-Host
Write-Host '--- RESULT ---'
if ($errors -eq 0 -and $warnings -eq 0) {
    Write-Host 'Board is healthy. No issues found.'
} else {
    Write-Host "Errors:   $errors"
    Write-Host "Warnings: $warnings"
}

exit $errors
