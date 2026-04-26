param(
    [Parameter(Mandatory)][string]$Repo,
    [string]$KanbanDir = 'kanban/analysis',
    [string]$ActionDir = 'kanban/actions',
    [switch]$SkipProfile,
    [switch]$DryRun,
    [ValidateSet('acceptEdits', 'bypassPermissions', 'default', 'dontAsk', 'plan', 'auto')]
    [string]$ClaudePermissionMode = 'bypassPermissions'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Repo -PathType Container)) {
    Write-Error "Error: '$Repo' is not a directory"
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$kanbanScripts = Join-Path (Split-Path -Parent $scriptDir) 'scripts'
$promptsDir = Join-Path $scriptDir 'prompts'
$specialistsDir = Join-Path $scriptDir 'specialists'

if (-not [System.IO.Path]::IsPathRooted($KanbanDir)) {
    $KanbanDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $KanbanDir))
}
if (-not [System.IO.Path]::IsPathRooted($ActionDir)) {
    $ActionDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $ActionDir))
}
$profilePath = Join-Path $KanbanDir '.project-profile.md'

. (Join-Path $kanbanScripts 'card_utils.ps1')

function Render-Prompt {
    param([Parameter(Mandatory)][string]$Template)

    $content = Get-Content -LiteralPath $Template -Raw
    $replacements = @{
        '{{PROFILE_PATH}}'   = $profilePath
        '{{SPECIALISTS_DIR}}' = $specialistsDir
        '{{KANBAN_DIR}}'     = $KanbanDir
        '{{ACTION_DIR}}'     = $ActionDir
        '{{SCRIPTS_DIR}}'    = $kanbanScripts
    }

    foreach ($entry in $replacements.GetEnumerator()) {
        $content = $content.Replace($entry.Key, $entry.Value)
    }

    $content
}

function Invoke-Claude {
    param([Parameter(Mandatory)][string]$Prompt)

    if ($DryRun) {
        Write-Host '[DRY RUN] Would call: claude -p'
        Write-Host '--- PROMPT ---'
        ($Prompt -split "`r?`n" | Select-Object -First 20) | ForEach-Object { Write-Host $_ }
        Write-Host '... (truncated)'
        Write-Host '--------------'
        return
    }

    $arguments = @(
        '-p'
        '--permission-mode', $ClaudePermissionMode
        '--add-dir', $Repo, $KanbanDir, $ActionDir, $kanbanScripts, $scriptDir, $promptsDir, $specialistsDir
    )

    $output = $Prompt | & claude @arguments 2>&1
    $exitCode = $LASTEXITCODE
    $outputText = ''
    if ($output) {
        $output | Out-Host
        $outputText = $output -join "`n"
    }
    if ($exitCode -ne 0) {
        if ([string]::IsNullOrWhiteSpace($outputText)) {
            throw "Claude CLI failed with exit code $exitCode and produced no output."
        }
        throw "Claude CLI failed with exit code $exitCode.`nClaude output:`n$outputText"
    }

    return $outputText
}

if (-not $DryRun -and -not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Error "Error: 'claude' CLI not found. Install Claude Code first."
}

New-Item -ItemType Directory -Path $KanbanDir -Force | Out-Null
New-Item -ItemType Directory -Path $ActionDir -Force | Out-Null

Write-Host '=== PHASE 1: Profiling repository ==='
if ($SkipProfile -and (Test-Path -LiteralPath $profilePath)) {
    Write-Host "Skipping profile (using existing: $profilePath)"
} else {
    & (Join-Path $scriptDir 'profiler.ps1') $Repo $profilePath
}
Write-Host

Write-Host '=== PHASE 2: Decomposing into analysis cards ==='
$existingCards = @(Get-ChildItem -LiteralPath $KanbanDir -File -Filter *.md -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '.project-profile.md' }).Count
if ($existingCards -gt 0) {
    Write-Host "Analysis cards already exist ($existingCards found). Skipping decomposition."
    Write-Host "To re-decompose, clear $KanbanDir/ first."
} else {
    $decomposerPrompt = Render-Prompt -Template (Join-Path $promptsDir 'decomposer.md')
    $fullPrompt = @"
You are analyzing the repository at: $Repo
Change to that directory before using shell tools for repo inspection. Use PowerShell in PowerShell environments and bash in Bash environments. When invoking kanban helper scripts, choose the script extension that matches the current shell.

$decomposerPrompt
"@
    $null = Invoke-Claude -Prompt $fullPrompt

    $createdCards = @(Get-ChildItem -LiteralPath $KanbanDir -File -Filter *.md -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '.project-profile.md' })
    if ($createdCards.Count -eq 0) {
        throw "Phase 2 failed: Claude finished without creating any analysis cards in $KanbanDir."
    }
}
Write-Host

Write-Host '=== PHASE 3: Executing specialists ==='
$iteration = 0
$maxIterations = 50
while ($iteration -lt $maxIterations) {
    $iteration++
    $nextCard = $null

    foreach ($card in Get-CardObjects -KanbanDir $KanbanDir) {
        if ($card.Name -eq '.project-profile.md' -or $card.Status -ne 'todo') {
            continue
        }

        $allResolved = $true
        foreach ($blockedId in Get-ListValues -Raw $card.BlockedBy) {
            $blockerFile = Find-CardFileById -KanbanDir $KanbanDir -CardId $blockedId
            if (-not $blockerFile) {
                $allResolved = $false
                break
            }
            if ((Get-CardField -Path $blockerFile -Field 'status') -ne 'done') {
                $allResolved = $false
                break
            }
        }

        if ($allResolved) {
            $nextCard = $card
            break
        }
    }

    if (-not $nextCard) {
        $todoCount = @(Get-CardObjects -KanbanDir $KanbanDir | Where-Object { $_.Name -ne '.project-profile.md' -and $_.Status -eq 'todo' }).Count
        if ($todoCount -gt 0) {
            Write-Warning "$todoCount cards still in 'todo' but all blocked. Possible cycle."
        } else {
            Write-Host 'All cards processed.'
        }
        break
    }

    $cardId = $nextCard.Id
    $specialist = Get-CardField -Path $nextCard.Path -Field 'specialist'
    if (-not $specialist) {
        $specialist = (Get-CardField -Path $nextCard.Path -Field 'assignee').Trim('"@')
    }

    $specialistDef = Join-Path $specialistsDir "$specialist.md"
    if (-not (Test-Path -LiteralPath $specialistDef -PathType Leaf)) {
        Write-Warning "No specialist definition for '$specialist' (card #$cardId). Using generic role."
        $specialistDef = Join-Path $specialistsDir 'architect.md'
    }

    Write-Host "--- Working card #$cardId (specialist: $specialist) ---"

    try {
        & (Join-Path $kanbanScripts 'transition.ps1') $KanbanDir $cardId doing | Out-Host
    } catch {
        Write-Warning "Failed to transition card #$cardId to doing. Skipping."
        continue
    }

    $specialistPrompt = Render-Prompt -Template (Join-Path $promptsDir 'specialist.md')
    $specialistPrompt = $specialistPrompt.Replace('{{SPECIALIST_NAME}}', $specialist)
    $specialistPrompt = $specialistPrompt.Replace('{{SPECIALIST_DEFINITION}}', $specialistDef)
    $specialistPrompt = $specialistPrompt.Replace('{{CARD_PATH}}', $nextCard.Path)
    $specialistPrompt = $specialistPrompt.Replace('{{CARD_ID}}', $cardId)

    $fullPrompt = @"
You are analyzing the repository at: $Repo
Change to that directory before using shell tools for repo inspection. Use PowerShell in PowerShell environments and bash in Bash environments. When invoking kanban helper scripts, choose the script extension that matches the current shell.

$specialistPrompt
"@

    try {
        $null = Invoke-Claude -Prompt $fullPrompt
    } catch {
        Write-Warning "Specialist failed on card #$cardId. Card remains in 'doing' state."
    }

    $postStatus = Get-CardField -Path $nextCard.Path -Field 'status'
    if ($postStatus -eq 'doing') {
        Write-Warning "Card #$cardId still in 'doing' after specialist run."
        Write-Warning "Inspect $($nextCard.Path) and transition manually, or re-run analyze.ps1."
    }
}
Write-Host

if (-not $DryRun) {
    $analysisCards = @(Get-CardObjects -KanbanDir $KanbanDir | Where-Object { $_.Name -ne '.project-profile.md' })
    if ($analysisCards.Count -eq 0) {
        throw "Phase 3 failed: no analysis cards exist in $KanbanDir."
    }

    $unfinishedCards = @($analysisCards | Where-Object { $_.Status -ne 'done' })
    if ($unfinishedCards.Count -gt 0) {
        $unfinishedSummary = $unfinishedCards | ForEach-Object { "#$($_.Id):$($_.Status)" }
        throw "Phase 3 failed: analysis cards are not all done: $($unfinishedSummary -join ', ')"
    }
}

Write-Host '=== PHASE 4: Synthesizing action board ==='
$synthesizerPrompt = Render-Prompt -Template (Join-Path $promptsDir 'synthesizer.md')
$fullPrompt = @"
You are analyzing the repository at: $Repo.
Read the analysis cards in $KanbanDir and write outputs to $ActionDir. Use PowerShell in PowerShell environments and bash in Bash environments. When invoking kanban helper scripts, choose the script extension that matches the current shell.

$synthesizerPrompt
"@
$null = Invoke-Claude -Prompt $fullPrompt

if (-not $DryRun) {
    $summaryPath = Join-Path $ActionDir 'ARCHITECTURE-REVIEW.md'
    if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
        throw "Phase 4 failed: Claude finished without creating $summaryPath."
    }
}

Write-Host
Write-Host '=== DONE ==='
Write-Host "Analysis cards:  $KanbanDir/"
Write-Host "Action board:    $ActionDir/"
Write-Host "Executive summary: $ActionDir/ARCHITECTURE-REVIEW.md"
