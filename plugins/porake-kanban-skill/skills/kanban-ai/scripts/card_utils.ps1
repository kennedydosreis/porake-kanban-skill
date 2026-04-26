Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-KanbanPath {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    [System.IO.Path]::GetFullPath($Path)
}

function Get-CardDocument {
    param([Parameter(Mandatory)][string]$Path)

    $resolved = Resolve-KanbanPath -Path $Path
    $lines = [System.IO.File]::ReadAllLines($resolved)
    $frontmatter = [ordered]@{}
    $bodyStart = 0

    if ($lines.Length -gt 0 -and $lines[0] -eq '---') {
        $bodyStart = $lines.Length
        for ($i = 1; $i -lt $lines.Length; $i++) {
            if ($lines[$i] -eq '---') {
                $bodyStart = $i + 1
                break
            }

            if ($lines[$i] -match '^([^:]+):\s*(.*)$') {
                $frontmatter[$matches[1]] = $matches[2]
            }
        }
    }

    $bodyLines = @()
    if ($bodyStart -lt $lines.Length) {
        $bodyLines = $lines[$bodyStart..($lines.Length - 1)]
    }

    [pscustomobject]@{
        Path       = $resolved
        Frontmatter = $frontmatter
        BodyLines  = [string[]]$bodyLines
    }
}

function Write-CardDocument {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][System.Collections.Specialized.OrderedDictionary]$Frontmatter,
        [string[]]$BodyLines = @()
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('---')
    foreach ($entry in $Frontmatter.GetEnumerator()) {
        $lines.Add(('{0}: {1}' -f $entry.Key, $entry.Value))
    }
    $lines.Add('---')
    foreach ($line in $BodyLines) {
        $lines.Add($line)
    }

    $content = [string]::Join("`n", $lines)
    if (-not $content.EndsWith("`n")) {
        $content += "`n"
    }

    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText((Resolve-KanbanPath -Path $Path), $content, $encoding)
}

function Get-CardField {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Field
    )

    $doc = Get-CardDocument -Path $Path
    if ($doc.Frontmatter.Contains($Field)) {
        return [string]$doc.Frontmatter[$Field]
    }

    ''
}

function Get-CardTitle {
    param([Parameter(Mandatory)][string]$Path)

    $doc = Get-CardDocument -Path $Path
    foreach ($line in $doc.BodyLines) {
        if ($line -match '^# (.+)$') {
            return $matches[1]
        }
    }

    ''
}

function Trim-Quotes {
    param([AllowEmptyString()][string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $trimmed = $Value.Trim()
    if ($trimmed.Length -ge 2) {
        if (($trimmed.StartsWith('"') -and $trimmed.EndsWith('"')) -or ($trimmed.StartsWith("'") -and $trimmed.EndsWith("'"))) {
            return $trimmed.Substring(1, $trimmed.Length - 2)
        }
    }

    $trimmed
}

function Normalize-FieldValue {
    param([AllowEmptyString()][string]$Value)
    (Trim-Quotes -Value $Value).Trim()
}

function Get-ListValues {
    param([AllowEmptyString()][string]$Raw)

    if ([string]::IsNullOrWhiteSpace($Raw)) {
        return @()
    }

    $clean = $Raw.Replace('[', '').Replace(']', '').Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) {
        return @()
    }

    @($clean.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-KanbanCardFiles {
    param(
        [Parameter(Mandatory)][string]$KanbanDir,
        [switch]$IncludeArchived
    )

    $dirs = @((Resolve-KanbanPath -Path $KanbanDir))
    if ($IncludeArchived) {
        $archived = Join-Path $KanbanDir 'archived'
        if (Test-Path -LiteralPath $archived) {
            $dirs += (Resolve-KanbanPath -Path $archived)
        }
    }

    $files = foreach ($dir in $dirs) {
        if (Test-Path -LiteralPath $dir) {
            Get-ChildItem -LiteralPath $dir -File -Filter *.md | Sort-Object Name
        }
    }
    @($files)
}

function Find-CardFileById {
    param(
        [Parameter(Mandatory)][string]$KanbanDir,
        [Parameter(Mandatory)][string]$CardId
    )

    foreach ($file in Get-KanbanCardFiles -KanbanDir $KanbanDir -IncludeArchived) {
        if ((Get-CardField -Path $file.FullName -Field 'id') -eq $CardId) {
            return $file.FullName
        }
    }

    $null
}

function Get-UnresolvedBlockers {
    param(
        [Parameter(Mandatory)][string]$KanbanDir,
        [Parameter(Mandatory)][string]$Path
    )

    $results = [System.Collections.Generic.List[string]]::new()
    $blockedBy = Get-CardField -Path $Path -Field 'blocked_by'
    foreach ($blockerId in Get-ListValues -Raw $blockedBy) {
        $blockerFile = Find-CardFileById -KanbanDir $KanbanDir -CardId $blockerId
        if (-not $blockerFile) {
            $results.Add(('#{0}(missing)' -f $blockerId))
            continue
        }

        $status = Get-CardField -Path $blockerFile -Field 'status'
        if ($status -notin @('done', 'archive')) {
            $results.Add(('#{0}({1})' -f $blockerId, $(if ($status) { $status } else { 'unknown' })))
        }
    }

    @($results)
}

function Add-Narrative {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Line
    )

    $doc = Get-CardDocument -Path $Path
    $body = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $doc.BodyLines) {
        $body.Add($item)
    }

    $index = -1
    for ($i = 0; $i -lt $body.Count; $i++) {
        if ($body[$i] -eq '## Narrative') {
            $index = $i
            break
        }
    }

    if ($index -ge 0) {
        $body.Insert($index + 1, $Line)
    } else {
        if ($body.Count -gt 0 -and $body[$body.Count - 1] -ne '') {
            $body.Add('')
        }
        $body.Add('## Narrative')
        $body.Add($Line)
    }

    Write-CardDocument -Path $Path -Frontmatter $doc.Frontmatter -BodyLines $body.ToArray()
}

function Get-FileEpoch {
    param([Parameter(Mandatory)][string]$Path)
    [int64]([DateTimeOffset](Get-Item -LiteralPath $Path).LastWriteTimeUtc).ToUnixTimeSeconds()
}

function Convert-DateToEpoch {
    param([AllowEmptyString()][string]$Date)

    if ([string]::IsNullOrWhiteSpace($Date)) {
        return 0
    }

    try {
        $parsed = [DateTime]::ParseExact($Date, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        return [int64]([DateTimeOffset]$parsed).ToUnixTimeSeconds()
    }
    catch {
        return 0
    }
}

function Get-DaysAgoEpoch {
    param([Parameter(Mandatory)][int]$Days)
    [int64]([DateTimeOffset](Get-Date).AddDays(-$Days)).ToUnixTimeSeconds()
}

function Get-StatusSinceEpoch {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$TargetStatus
    )

    $doc = Get-CardDocument -Path $Path
    foreach ($line in $doc.BodyLines) {
        if ($line -match "^- (\d{4}-\d{2}-\d{2}): .*to '$([regex]::Escape($TargetStatus))'") {
            return Convert-DateToEpoch -Date $matches[1]
        }
    }

    Get-FileEpoch -Path $Path
}

function Get-CurrentDateString {
    (Get-Date).ToString('yyyy-MM-dd')
}

function Get-CardObjects {
    param(
        [Parameter(Mandatory)][string]$KanbanDir,
        [switch]$IncludeArchived
    )

    foreach ($file in Get-KanbanCardFiles -KanbanDir $KanbanDir -IncludeArchived:$IncludeArchived) {
        [pscustomobject]@{
            Path       = $file.FullName
            Name       = $file.Name
            Id         = Get-CardField -Path $file.FullName -Field 'id'
            Status     = Get-CardField -Path $file.FullName -Field 'status'
            Priority   = Get-CardField -Path $file.FullName -Field 'priority'
            BlockedBy  = Get-CardField -Path $file.FullName -Field 'blocked_by'
            Assignee   = Normalize-FieldValue -Value (Get-CardField -Path $file.FullName -Field 'assignee')
            DueDate    = Get-CardField -Path $file.FullName -Field 'due_date'
            Tags       = Get-CardField -Path $file.FullName -Field 'tags'
            Title      = $(if (Get-CardTitle -Path $file.FullName) { Get-CardTitle -Path $file.FullName } else { [System.IO.Path]::GetFileNameWithoutExtension($file.Name) })
        }
    }
}

function Get-MaxCardId {
    param([Parameter(Mandatory)][string]$KanbanDir)

    $max = 0
    foreach ($card in Get-CardObjects -KanbanDir $KanbanDir -IncludeArchived) {
        $value = 0
        if ([int]::TryParse($card.Id, [ref]$value) -and $value -gt $max) {
            $max = $value
        }
    }

    $max
}

function ConvertTo-KebabCase {
    param([Parameter(Mandatory)][string]$Text)

    $value = $Text.ToLowerInvariant()
    $value = [regex]::Replace($value, '[^a-z0-9]+', '-')
    $value = [regex]::Replace($value, '-{2,}', '-')
    $value.Trim('-')
}

function Acquire-KanbanLock {
    param(
        [Parameter(Mandatory)][string]$KanbanDir,
        [Parameter(Mandatory)][string]$Name
    )

    $lockPath = Join-Path $KanbanDir ('.{0}.lock' -f $Name)
    try {
        New-Item -ItemType Directory -Path $lockPath -ErrorAction Stop | Out-Null
        return $lockPath
    } catch {
        throw [System.InvalidOperationException]::new($lockPath)
    }
}

function Release-KanbanLock {
    param([AllowEmptyString()][string]$LockPath)

    if ($LockPath -and (Test-Path -LiteralPath $LockPath)) {
        Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue
    }
}

function Set-CardFields {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Updates
    )

    $doc = Get-CardDocument -Path $Path
    foreach ($entry in $Updates.GetEnumerator()) {
        $doc.Frontmatter[$entry.Key] = $entry.Value
    }
    Write-CardDocument -Path $Path -Frontmatter $doc.Frontmatter -BodyLines $doc.BodyLines
}
