param([string]$KanbanDir = '.')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/card_utils.ps1"

foreach ($card in Get-CardObjects -KanbanDir $KanbanDir | Sort-Object { [int]$_.Id }) {
    $blocked = ($card.BlockedBy -replace '[\[\]]', '').Trim()
    '{0}|{1}|{2}|{3}' -f $card.Id, $card.Status, $blocked, $card.Title
}
