param([string]$KanbanDir = 'kanban')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/card_utils.ps1"

if (-not (Test-Path -LiteralPath $KanbanDir -PathType Container)) {
    Write-Error "Error: '$KanbanDir' not found."
}

$columns = [ordered]@{
    backlog = @()
    todo    = @()
    doing   = @()
    review  = @()
    done    = @()
    archive = @()
}

foreach ($card in Get-CardObjects -KanbanDir $KanbanDir) {
    $line = '  #{0} {1}' -f $card.Id, $card.Title
    if ($card.Priority -eq 'High') {
        $line += ' [HIGH]'
    }

    $blockers = @(Get-UnresolvedBlockers -KanbanDir $KanbanDir -Path $card.Path) -join ' '
    if ($blockers) {
        $line += ' [blocked: {0}]' -f $blockers
    }

    if ($columns.Contains($card.Status)) {
        $columns[$card.Status] += $line
    }
}

foreach ($status in $columns.Keys) {
    '=== {0,-8} ===' -f $status.ToUpperInvariant()
    if ($columns[$status].Count -eq 0) {
        '  (empty)'
    } else {
        $columns[$status]
    }
    ''
}
