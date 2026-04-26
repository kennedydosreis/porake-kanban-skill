param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ScriptsDir = Join-Path $RootDir 'plugins\porake-kanban-skill\skills\kanban-ai\scripts'
$TempDir = Join-Path $env:TEMP ('porake-kanban-full-' + [guid]::NewGuid())
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

function Replace-InFile {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Replacement
    )

    $content = Get-Content -LiteralPath $Path -Raw
    $updated = [regex]::Replace($content, $Pattern, $Replacement, 1)
    [System.IO.File]::WriteAllText($Path, $updated, [System.Text.UTF8Encoding]::new($false))
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

    & (Join-Path $ScriptsDir 'create_from_template.ps1') $BoardDir chore 'Smoke Test Chore' | Out-Null
    & (Join-Path $ScriptsDir 'create_from_template.ps1') $BoardDir feature 'Smoke Test Feature' | Out-Null
    & (Join-Path $ScriptsDir 'create_from_template.ps1') $BoardDir bug 'Blocked Smoke Bug' | Out-Null

    $blockedFile = Join-Path $BoardDir 'blocked-smoke-bug.md'
    Replace-InFile -Path $blockedFile -Pattern 'blocked_by:\s*\[\]' -Replacement 'blocked_by: [2]'

    $cardsOutput = & (Join-Path $ScriptsDir 'list_all_cards.ps1') $BoardDir
    Assert-Contains -Text ($cardsOutput -join "`n") -Needle '1|backlog||Smoke Test Chore' -Message 'Chore card missing from list.'

    & (Join-Path $ScriptsDir 'show_blocked.ps1') $BoardDir | Out-Null

    & (Join-Path $ScriptsDir 'claim_next.ps1') $BoardDir codex | Out-Null
    & (Join-Path $ScriptsDir 'submit_for_review.ps1') $BoardDir 1 claude | Out-Null
    & (Join-Path $ScriptsDir 'review_card.ps1') $BoardDir 1 approve claude | Out-Null
    & (Join-Path $ScriptsDir 'transition.ps1') $BoardDir 2 doing | Out-Null
    & (Join-Path $ScriptsDir 'transition.ps1') $BoardDir 2 done | Out-Null
    & (Join-Path $ScriptsDir 'transition.ps1') $BoardDir 3 doing | Out-Null

    $cardsAfterTransitions = & (Join-Path $ScriptsDir 'list_all_cards.ps1') $BoardDir
    Assert-Contains -Text ($cardsAfterTransitions -join "`n") -Needle '3|doing|2|Blocked Smoke Bug' -Message 'Third card did not reach doing as expected.'

    & (Join-Path $ScriptsDir 'view_board.ps1') $BoardDir | Out-Null
    & (Join-Path $ScriptsDir 'standup.ps1') $BoardDir -Days 1 | Out-Null
    & (Join-Path $ScriptsDir 'report.ps1') $BoardDir | Out-Null
    & (Join-Path $ScriptsDir 'search_by_tag.ps1') $BoardDir smoke | Out-Null
    & (Join-Path $ScriptsDir 'search_content.ps1') $BoardDir blocked | Out-Null
    & (Join-Path $ScriptsDir 'list_tags.ps1') $BoardDir | Out-Null
    & (Join-Path $ScriptsDir 'auto_archive.ps1') $BoardDir -Days 1 -DryRun | Out-Null
    & (Join-Path $ScriptsDir 'validate_board.ps1') $BoardDir | Out-Null

    Write-Host 'PASS: full PowerShell smoke test'
}
finally {
    if (Test-Path -LiteralPath $TempDir) {
        Remove-Item -LiteralPath $TempDir -Recurse -Force
    }
}
