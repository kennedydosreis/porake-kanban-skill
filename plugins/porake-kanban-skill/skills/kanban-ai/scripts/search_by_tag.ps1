param(
    [string]$KanbanDir = '.',
    [string]$Tag
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/card_utils.ps1"

if (-not $Tag) {
    if ($KanbanDir -and $KanbanDir -ne '.') {
        $Tag = $KanbanDir
        $KanbanDir = '.'
    }
}

if (-not $Tag) {
    Write-Host "Usage: $($MyInvocation.MyCommand.Name) [kanban_dir] <tag>"
    Write-Host "Example: $($MyInvocation.MyCommand.Name) kanban/ ai-discoverability"
    exit 1
}

Write-Host "=== Cards tagged with: $Tag ==="
Write-Host

foreach ($card in Get-CardObjects -KanbanDir $KanbanDir) {
    if ((Get-ListValues -Raw $card.Tags) -contains $Tag) {
        '{0,-4} {1,-12} {2}' -f ('#{0}' -f ($card.Id ?? '?')), ('[{0}]' -f $card.Status), $card.Title
    }
}
