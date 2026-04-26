param(
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string]$Output
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Repo -PathType Container)) {
    Write-Error "Error: '$Repo' is not a directory."
}

$repoPath = (Resolve-Path -LiteralPath $Repo).Path
$filters = @('node_modules', '.git', 'venv', '.venv', 'dist', 'build', 'target', '__pycache__')

function Get-RepoFiles {
    param([string]$Root)

    Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object {
        $fullName = $_.FullName
        foreach ($filter in $filters) {
            if ($fullName -like "*\$filter\*" -or $fullName -like "*/$filter/*") {
                return $false
            }
        }
        return $true
    }
}

function Has-AnyPath {
    param([string[]]$Paths)
    foreach ($path in $Paths) {
        if (Test-Path -LiteralPath (Join-Path $repoPath $path)) {
            return $true
        }
    }
    $false
}

function Search-FilePatterns {
    param(
        [string[]]$Files,
        [string[]]$Patterns,
        [switch]$CaseSensitive
    )

    foreach ($file in $Files) {
        $path = Join-Path $repoPath $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }

        foreach ($pattern in $Patterns) {
            $params = @{
                Path         = $path
                Pattern      = $pattern
                SimpleMatch  = $true
                Quiet        = $true
                ErrorAction  = 'SilentlyContinue'
            }
            if (-not $CaseSensitive) {
                $params.CaseSensitive = $false
            }
            if (Select-String @params) {
                return $true
            }
        }
    }

    $false
}

$allFiles = @(Get-RepoFiles -Root $repoPath)
$extensionCounts = @{}
foreach ($file in $allFiles) {
    $extension = $file.Extension.TrimStart('.')
    if (-not $extension) {
        continue
    }
    if (-not $extensionCounts.ContainsKey($extension)) {
        $extensionCounts[$extension] = 0
    }
    $extensionCounts[$extension]++
}

$languages = $extensionCounts.GetEnumerator() |
    Sort-Object @{ Expression = 'Value'; Descending = $true }, @{ Expression = 'Key'; Descending = $false } |
    Select-Object -First 10 |
    ForEach-Object { '{0,5} {1}' -f $_.Value, $_.Key }

$totalFiles = $allFiles.Count
$repoSizeBytes = ($allFiles | Measure-Object -Property Length -Sum).Sum
if (-not $repoSizeBytes) { $repoSizeBytes = 0 }
$repoSize = if ($repoSizeBytes -ge 1GB) { '{0:N1} GB' -f ($repoSizeBytes / 1GB) } elseif ($repoSizeBytes -ge 1MB) { '{0:N1} MB' -f ($repoSizeBytes / 1MB) } elseif ($repoSizeBytes -ge 1KB) { '{0:N1} KB' -f ($repoSizeBytes / 1KB) } else { "$repoSizeBytes B" }

$pkgManagers = [System.Collections.Generic.List[string]]::new()
if (Has-AnyPath -Paths @('package.json')) { $pkgManagers.Add('npm/node') }
if (Has-AnyPath -Paths @('requirements.txt', 'pyproject.toml', 'setup.py')) { $pkgManagers.Add('python/pip') }
if (Has-AnyPath -Paths @('Cargo.toml')) { $pkgManagers.Add('rust/cargo') }
if (Has-AnyPath -Paths @('go.mod')) { $pkgManagers.Add('go/modules') }
if (Has-AnyPath -Paths @('pom.xml')) { $pkgManagers.Add('java/maven') }
if (Has-AnyPath -Paths @('build.gradle', 'build.gradle.kts')) { $pkgManagers.Add('java/gradle') }
if (Has-AnyPath -Paths @('Gemfile')) { $pkgManagers.Add('ruby/bundler') }
if (Has-AnyPath -Paths @('composer.json')) { $pkgManagers.Add('php/composer') }
if (Has-AnyPath -Paths @('mix.exs')) { $pkgManagers.Add('elixir/mix') }

$frameworks = [System.Collections.Generic.List[string]]::new()
if (Search-FilePatterns -Files @('package.json') -Patterns @('"react"', '"vue"', '"svelte"', '"next"', '"nuxt"', '"angular"', '"express"', '"fastify"', '"nestjs"')) {
    foreach ($fw in @('react', 'vue', 'svelte', 'next', 'nuxt', 'angular', 'express', 'fastify', 'nestjs')) {
        if (Search-FilePatterns -Files @('package.json') -Patterns @("""$fw""")) { $frameworks.Add($fw) }
    }
}
foreach ($fw in @('django', 'fastapi', 'flask', 'pyramid', 'tornado', 'starlette')) {
    if (Search-FilePatterns -Files @('requirements.txt', 'pyproject.toml', 'setup.py', 'Pipfile') -Patterns @($fw, "$fw==", "$fw>=", "$fw = ", """$fw""")) {
        $frameworks.Add($fw)
    }
}
$frameworks = @($frameworks | Select-Object -Unique)

$aiSignals = [System.Collections.Generic.List[string]]::new()
foreach ($lib in @('torch', 'tensorflow', 'transformers', 'langchain', 'openai', 'anthropic', 'llama', 'scikit-learn', 'pandas', 'numpy')) {
    if (Search-FilePatterns -Files @('requirements.txt', 'pyproject.toml', 'setup.py', 'Pipfile') -Patterns @($lib, "$lib==", "$lib>=", "$lib = ", """$lib""")) {
        $aiSignals.Add($lib)
    }
}
$notebooks = @(Get-ChildItem -LiteralPath $repoPath -Recurse -File -Filter *.ipynb -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notlike "*\.git\*" }).Count
if ($notebooks -gt 0) {
    $aiSignals.Add("jupyter($notebooks)")
}
$aiSignals = @($aiSignals | Select-Object -Unique)

$ciSignals = [System.Collections.Generic.List[string]]::new()
$ghWorkflows = Join-Path $repoPath '.github\workflows'
if (Test-Path -LiteralPath $ghWorkflows -PathType Container) {
    $workflowCount = @(Get-ChildItem -LiteralPath $ghWorkflows -File -Include *.yml, *.yaml -ErrorAction SilentlyContinue).Count
    $ciSignals.Add("github-actions($workflowCount)")
}
if (Has-AnyPath -Paths @('.gitlab-ci.yml')) { $ciSignals.Add('gitlab-ci') }
if (Has-AnyPath -Paths @('Jenkinsfile')) { $ciSignals.Add('jenkins') }
if (Has-AnyPath -Paths @('.circleci/config.yml')) { $ciSignals.Add('circle-ci') }

$testDirs = @(Get-ChildItem -LiteralPath $repoPath -Recurse -Directory -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -in @('test', 'tests', '__tests__', 'spec') -and $_.FullName -notlike "*\node_modules\*" -and $_.FullName -notlike "*\.git\*"
} | Select-Object -ExpandProperty FullName)
$testSignals = if ($testDirs.Count -gt 0) { 'yes (dirs: {0})' -f (($testDirs | ForEach-Object { $_.Replace($repoPath, '.').TrimStart('\') }) -join ' ') } else { 'no test directories found' }

$topDirs = @(Get-ChildItem -LiteralPath $repoPath -Directory -Force -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -notin @('.git', 'node_modules', 'venv', '.venv')
} | Sort-Object Name | ForEach-Object { $_.Name })

$docSignals = [System.Collections.Generic.List[string]]::new()
if (Has-AnyPath -Paths @('README.md', 'README.rst', 'README')) { $docSignals.Add('README') }
if (Has-AnyPath -Paths @('docs', 'doc')) { $docSignals.Add('docs/') }
if (Has-AnyPath -Paths @('CONTRIBUTING.md')) { $docSignals.Add('CONTRIBUTING') }
if (Has-AnyPath -Paths @('ARCHITECTURE.md')) { $docSignals.Add('ARCHITECTURE') }

$gitActivity = 'n/a'
if (Test-Path -LiteralPath (Join-Path $repoPath '.git')) {
    $commits90d = @(& git -C $repoPath log --since="90 days ago" --oneline 2>$null).Count
    $contributors = @(& git -C $repoPath log --since="90 days ago" --format='%ae' 2>$null | Sort-Object -Unique).Count
    $gitActivity = "$commits90d commits, $contributors contributors (last 90d)"
}

$outputDir = Split-Path -Parent $Output
if ($outputDir) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$content = [System.Collections.Generic.List[string]]::new()
$content.Add('# Project Profile')
$content.Add('')
$content.Add(('Generated: {0}' -f (Get-Date -Format 'yyyy-MM-dd')))
$content.Add(('Path: {0}' -f $repoPath))
$content.Add('')
$content.Add('## Size')
$content.Add(('- Total files: {0}' -f $totalFiles))
$content.Add(('- Repo size: {0}' -f $repoSize))
$content.Add(('- Git activity: {0}' -f $gitActivity))
$content.Add('')
$content.Add('## Top File Types')
$content.Add('```')
if ($languages.Count -gt 0) {
    foreach ($line in $languages) { $content.Add([string]$line) }
} else {
    $content.Add('')
}
$content.Add('```')
$content.Add('')
$content.Add('## Package Managers')
$content.Add(('- {0}' -f $(if ($pkgManagers.Count -gt 0) { $pkgManagers -join ' ' } else { 'none detected' })))
$content.Add('')
$content.Add('## Frameworks Detected')
$content.Add(('- {0}' -f $(if ($frameworks.Count -gt 0) { $frameworks -join ' ' } else { 'none detected' })))
$content.Add('')
$content.Add('## AI/ML Signals')
$content.Add(('- {0}' -f $(if ($aiSignals.Count -gt 0) { $aiSignals -join ' ' } else { 'none detected' })))
$content.Add('')
$content.Add('## CI/CD')
$content.Add(('- {0}' -f $(if ($ciSignals.Count -gt 0) { $ciSignals -join ' ' } else { 'none detected' })))
$content.Add('')
$content.Add('## Tests')
$content.Add(('- {0}' -f $testSignals))
$content.Add('')
$content.Add('## Documentation')
$content.Add(('- {0}' -f $(if ($docSignals.Count -gt 0) { $docSignals -join ' ' } else { 'minimal' })))
$content.Add('')
$content.Add('## Top-Level Structure')
$content.Add('```')
if ($topDirs.Count -gt 0) {
    foreach ($line in $topDirs) { $content.Add([string]$line) }
} else {
    $content.Add('')
}
$content.Add('```')

[System.IO.File]::WriteAllLines($Output, $content.ToArray(), [System.Text.UTF8Encoding]::new($false))
Write-Host "Profile written to: $Output"
