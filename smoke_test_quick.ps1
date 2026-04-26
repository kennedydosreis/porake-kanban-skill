param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ScriptsDir = Join-Path $RootDir 'plugins\porake-kanban-skill\skills\kanban-ai\scripts'
$TempDir = Join-Path $env:TEMP ('porake-kanban-quick-' + [guid]::NewGuid())
$BoardDir = Join-Path $TempDir 'kanban'

function Assert-Contains {
    param(
        [string]$Text,
        [string]$Needle,
        [string]$Message
    )

    if ($Text -notlike "*$Needle*") {
        throw $Message
    }
}

try {
    Get-ChildItem $ScriptsDir -Filter *.ps1 | ForEach-Object {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) {
            throw "Parse failed for $($_.Name): $($errors[0].Message)"
        }
    }

    New-Item -ItemType Directory -Path $TempDir | Out-Null

    & (Join-Path $ScriptsDir 'create_from_template.ps1') $BoardDir chore 'Quick Smoke Card' | Out-Null
    $cardsOutput = & (Join-Path $ScriptsDir 'list_all_cards.ps1') $BoardDir
    Assert-Contains -Text ($cardsOutput -join "`n") -Needle '1|backlog||Quick Smoke Card' -Message 'Created card was not listed.'

    & (Join-Path $ScriptsDir 'claim_next.ps1') $BoardDir codex -DryRun | Out-Null
    & (Join-Path $ScriptsDir 'claim_next.ps1') $BoardDir codex | Out-Null
    & (Join-Path $ScriptsDir 'submit_for_review.ps1') $BoardDir 1 claude | Out-Null
    & (Join-Path $ScriptsDir 'review_card.ps1') $BoardDir 1 approve claude | Out-Null

    $cardsAfterReview = & (Join-Path $ScriptsDir 'list_all_cards.ps1') $BoardDir
    Assert-Contains -Text ($cardsAfterReview -join "`n") -Needle '1|done||Quick Smoke Card' -Message 'Approved card did not end in done.'

    & (Join-Path $ScriptsDir 'view_board.ps1') $BoardDir | Out-Null
    & (Join-Path $ScriptsDir 'validate_board.ps1') $BoardDir | Out-Null

    Write-Host 'PASS: quick PowerShell smoke test'
}
finally {
    if (Test-Path -LiteralPath $TempDir) {
        Remove-Item -LiteralPath $TempDir -Recurse -Force
    }
}
