param(
    [string]$KanbanDir = '.',
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$SearchParts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/card_utils.ps1"

if ($SearchParts.Count -eq 0 -and $KanbanDir -and $KanbanDir -ne '.') {
    $SearchParts = @($KanbanDir)
    $KanbanDir = '.'
}

$SearchTerm = ($SearchParts -join ' ').Trim()
if (-not $SearchTerm) {
    Write-Host "Usage: $($MyInvocation.MyCommand.Name) [kanban_dir] <search_term>"
    Write-Host "Example: $($MyInvocation.MyCommand.Name) kanban/ temporal signals"
    exit 1
}

Write-Host "=== Cards matching: $SearchTerm ==="
Write-Host

foreach ($card in Get-CardObjects -KanbanDir $KanbanDir) {
    $matches = Select-String -Path $card.Path -Pattern $SearchTerm -SimpleMatch -CaseSensitive:$false -Context 1,1
    if (-not $matches) {
        continue
    }

    '{0,-4} {1,-12} {2}' -f ('#{0}' -f ($card.Id ?? '?')), ('[{0}]' -f $card.Status), $card.Title
    '  Matches:'

    $rendered = [System.Collections.Generic.List[string]]::new()
    foreach ($match in $matches) {
        foreach ($line in $match.Context.PreContext) {
            $rendered.Add(('    {0}' -f $line))
        }
        $rendered.Add(('    {0}: {1}' -f $match.LineNumber, $match.Line))
        foreach ($line in $match.Context.PostContext) {
            $rendered.Add(('    {0}' -f $line))
        }
        if ($rendered.Count -ge 10) {
            break
        }
    }

    $rendered | Select-Object -First 10
    ''
}
