param(
    [Parameter(Mandatory)][string]$KanbanDir,
    [Parameter(Mandatory)][string]$Template,
    [Parameter(Mandatory)][string]$Title,
    [string]$Assignee = "",
    [string]$DueDate = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/card_utils.ps1"

$templateFile = Join-Path $PSScriptRoot "templates/$Template.md"
if (-not (Test-Path -LiteralPath $templateFile -PathType Leaf)) {
    Write-Error "Error: Template '$Template' not found."
}

$newId = (Get-MaxCardId -KanbanDir $KanbanDir) + 1
$filename = ConvertTo-KebabCase -Text $Title
$path = Join-Path $KanbanDir ($filename + '.md')
if (Test-Path -LiteralPath $path) {
    $path = Join-Path $KanbanDir ('{0}-{1}.md' -f $filename, $newId)
}

New-Item -ItemType Directory -Path $KanbanDir -Force | Out-Null

$content = Get-Content -LiteralPath $templateFile -Raw
$content = $content.Replace('__ID__', [string]$newId)
$content = $content.Replace('__TITLE__', $Title)
$content = $content.Replace('__ASSIGNEE__', $Assignee)
$content = $content.Replace('__DUE_DATE__', $DueDate)
[System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))

Write-Host ("Created card #{0}: {1} (template: {2})" -f $newId, $path, $Template)
