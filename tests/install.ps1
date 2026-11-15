# install.ps1 end to end, against stand-ins: claude, git, py, uv, npm, playwright-cli and graphify on PATH log
# their arguments instead of installing anything. runs in a temp folder with a fake home.
#
#   powershell -File tests\install.ps1        (or pwsh)
#
# on Windows the run needs symlink rights (Developer Mode or an elevated shell).
$ErrorActionPreference = 'Stop'

$Root = Split-Path $PSScriptRoot
$OnWindows = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
$Self = (Get-Process -Id $PID).Path
$Work = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
$Out = ''

function Fail($Text) {
    Write-Host "FAIL: $Text" -ForegroundColor Red

    if ($Out) { Write-Host '--- last output:'; Write-Host $Out }

    exit 1
}

function Assert($Condition, $Text) { if (-not $Condition) { Fail $Text } }

function New-Stub($Dir, $Name, [string[]]$Cmd, [string[]]$Sh) {
    if ($OnWindows) {
        [IO.File]::WriteAllText((Join-Path $Dir "$Name.cmd"), (($Cmd -join "`r`n") + "`r`n"))
    }
    else {
        $path = Join-Path $Dir $Name
        [IO.File]::WriteAllText($path, (($Sh -join "`n") + "`n"))
        & chmod +x $path
    }
}

function New-Stubs($Dir) {
    New-Item -ItemType Directory -Path $Dir | Out-Null

    New-Stub $Dir 'claude' @(
        '@echo off',
        'if "%1 %2 %3"=="plugin list --json" (echo [{"id": "superpowers@superpowers-marketplace"}] & exit /b 0)',
        'if "%1 %2"=="mcp list" (echo basic-memory: http - Connected & exit /b 0)',
        'echo claude %* >> "%FAKE_LOG%"'
    ) @(
        '#!/bin/sh',
        'case "$*" in',
        '  "plugin list --json") echo ''[{"id": "superpowers@superpowers-marketplace"}]''; exit 0 ;;',
        '  "mcp list") echo "basic-memory: http - Connected"; exit 0 ;;',
        'esac',
        'echo "claude $*" >> "$FAKE_LOG"'
    )

    New-Stub $Dir 'git' @(
        '@echo off',
        'echo git %* >> "%FAKE_LOG%"',
        'if "%1"=="clone" (',
        '  mkdir "%~6\skills\marimo-notebook"',
        '  echo name: marimo-notebook> "%~6\skills\marimo-notebook\SKILL.md"',
        '  mkdir "%~6\skills\langfuse"',
        '  echo name: langfuse> "%~6\skills\langfuse\SKILL.md"',
        ')'
    ) @(
        '#!/bin/sh',
        'echo "git $*" >> "$FAKE_LOG"',
        'if [ "$1" = clone ]; then',
        '  for last; do :; done',
        '  mkdir -p "$last/skills/marimo-notebook" "$last/skills/langfuse"',
        '  echo "name: marimo-notebook" > "$last/skills/marimo-notebook/SKILL.md"',
        '  echo "name: langfuse" > "$last/skills/langfuse/SKILL.md"',
        'fi'
    )

    New-Stub $Dir 'py' @('@echo off', 'echo py %* >> "%FAKE_LOG%"') @('#!/bin/sh', 'echo "py $*" >> "$FAKE_LOG"')
    New-Stub $Dir 'uv' @('@echo off', 'echo uv %* >> "%FAKE_LOG%"') @('#!/bin/sh', 'echo "uv $*" >> "$FAKE_LOG"')

    New-Stub $Dir 'npm' @('@echo off', 'echo npm %* >> "%FAKE_LOG%"') @('#!/bin/sh', 'echo "npm $*" >> "$FAKE_LOG"')

    New-Stub $Dir 'playwright-cli' @(
        '@echo off',
        'echo playwright-cli %* >> "%FAKE_LOG%"',
        'if "%1"=="install" (',
        '  mkdir "%HOME%\.claude\skills\playwright-cli"',
        '  echo name: playwright-cli> "%HOME%\.claude\skills\playwright-cli\SKILL.md"',
        ')'
    ) @(
        '#!/bin/sh',
        'echo "playwright-cli $*" >> "$FAKE_LOG"',
        'if [ "$1" = install ]; then',
        '  mkdir -p "$HOME/.claude/skills/playwright-cli"',
        '  echo "name: playwright-cli" > "$HOME/.claude/skills/playwright-cli/SKILL.md"',
        'fi'
    )

    New-Stub $Dir 'graphify' @(
        '@echo off',
        'echo graphify %* >> "%FAKE_LOG%"',
        'if "%1"=="install" (',
        '  mkdir "%CLAUDE_CONFIG_DIR%\skills\graphify"',
        '  echo name: graphify> "%CLAUDE_CONFIG_DIR%\skills\graphify\SKILL.md"',
        ')'
    ) @(
        '#!/bin/sh',
        'echo "graphify $*" >> "$FAKE_LOG"',
        'if [ "$1" = install ]; then',
        '  mkdir -p "$CLAUDE_CONFIG_DIR/skills/graphify"',
        '  echo "name: graphify" > "$CLAUDE_CONFIG_DIR/skills/graphify/SKILL.md"',
        'fi'
    )
}

function Initialize-Case($Name) {
    $script:Dir = Join-Path $Work $Name
    $script:Repo = Join-Path $Dir 'repo'
    $script:Home_ = Join-Path $Dir 'home'
    $script:Log = Join-Path $Dir 'fake.log'
    New-Item -ItemType Directory -Path $Repo, $Home_ | Out-Null
    Copy-Item (Join-Path $Root 'install.ps1') $Repo
    Copy-Item (Join-Path $Root 'claude') $Repo -Recurse
    Set-Content -Path $Log -Value ''
    $env:FAKE_LOG = $Log
    $env:CARDEA_USER_HOME = $Home_
}

function Invoke-Install([string[]]$ScriptArgs) {
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    try {
        $script:Out = (& $Self -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo 'install.ps1') @ScriptArgs 2>&1 | Out-String)
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $saved
    }

    return $code
}

function Assert-Called($Text) { Assert ((Get-Content $Log -Raw) -like "*$Text*") "expected a call: $Text" }
function Assert-NotCalled($Text) { Assert (-not ((Get-Content $Log -Raw) -like "*$Text*")) "unexpected call: $Text" }
function Assert-Said($Text) { Assert ($Out -like "*$Text*") "output should mention: $Text" }

function Assert-Linked($Rel, $Target) {
    $item = Get-Item -LiteralPath (Join-Path $Home_ $Rel) -Force -ErrorAction SilentlyContinue
    Assert ($item -and $item.LinkType -eq 'SymbolicLink') "$Rel is not a symbolic link"
    $actual = [IO.Path]::GetFullPath(@($item.Target)[0])
    $expected = [IO.Path]::GetFullPath((Join-Path $Repo $Target))
    Assert ($actual -eq $expected) "$Rel does not point at $Target"
}

try {
    New-Item -ItemType Directory -Path $Work | Out-Null
    $stubs = Join-Path $Work 'stubs'
    New-Stubs $stubs
    $sep = [IO.Path]::PathSeparator
    $gitRoot = Join-Path $Work 'gitroot'
    $prefix = $stubs

    if ($OnWindows) {
        New-Item -ItemType Directory -Path (Join-Path $gitRoot 'bin') | Out-Null
        Set-Content -Path (Join-Path $gitRoot 'bin\bash.exe') -Value ''
        $prefix = "$(Join-Path $gitRoot 'cmd')$sep$prefix"
        New-Item -ItemType Directory -Path (Join-Path $gitRoot 'cmd') | Out-Null
        Move-Item (Join-Path $stubs 'git.cmd') (Join-Path $gitRoot 'cmd\git.cmd')
    }

    $realUv = @(Get-Command uv -All -ErrorAction SilentlyContinue | ForEach-Object { Split-Path $_.Source })
    $pathWithoutUv = ($env:PATH -split [regex]::Escape($sep) | Where-Object { $realUv -notcontains $_ }) -join $sep
    $path = "$prefix$sep$($env:PATH)"
    $env:PATH = $path
    $env:BASIC_MEMORY_URL = 'http://127.0.0.1:8766/mcp'
    Remove-Item Env:CARDEA_ASSUME_NO_SYMLINK -ErrorAction SilentlyContinue

    Initialize-Case 'install'
    Assert ((Invoke-Install @()) -eq 0) 'install exited non-zero'
    Assert-Linked '.claude/CLAUDE.md' 'claude/CLAUDE.md'
    Assert-Linked '.claude/skills/tldr' 'claude/skills/tldr'
    Assert-Linked '.claude/skills/baby' 'claude/skills/baby'
    $settings = Get-Content -Raw (Join-Path $Home_ '.claude/settings.json') | ConvertFrom-Json
    Assert ($settings.env.CLAUDE_CODE_ENABLE_TODO_TOOLS -eq '1') 'the task list was not turned on in settings.json'
    Assert-Called 'mcp add -s user --transport http basic-memory http://127.0.0.1:8766/mcp'
    Assert-Called "plugin install cardea --marketplace $Repo -y"
    Assert-Called 'plugin update superpowers@superpowers-marketplace'

    foreach ($m in 'ponytail:DietrichGebert/ponytail', 'cloudflare:cloudflare/skills', 'humanizer:blader/humanizer') {
        Assert-Called "plugin install $($m.Split(':')[0]) --marketplace $($m.Split(':')[1]) -y"
    }

    Assert-NotCalled 'apple-skills'
    Assert-Called 'uv tool install graphifyy==0.9.88'
    Assert-Called 'npm install -g @playwright/cli@0.1.24'
    Assert-Called 'playwright-cli install-browser chromium'

    foreach ($s in 'graphify', 'playwright-cli', 'marimo-notebook', 'langfuse') {
        Assert (Test-Path (Join-Path $Home_ ".claude/skills/$s/SKILL.md")) "the $s skill was not installed"
    }

    Assert ((Invoke-Install @('-Check')) -eq 0) '-Check exited non-zero on a clean install'
    Assert (-not ($Out -match '(?m)^\s*x ')) '-Check reported a problem on a clean install'
    Assert-Said 'CLAUDE.md'

    Assert ((Invoke-Install @()) -eq 0) 'rerun exited non-zero'

    Initialize-Case 'backup'
    New-Item -ItemType Directory -Path (Join-Path $Home_ '.claude') | Out-Null
    Set-Content -Path (Join-Path $Home_ '.claude/CLAUDE.md') -Value 'mine'
    Set-Content -Path (Join-Path $Home_ '.claude/settings.json') -Value '{"model":"x","env":{"A":"1"}}'
    Assert ((Invoke-Install @()) -eq 0) 'backup case exited non-zero'
    $settings = Get-Content -Raw (Join-Path $Home_ '.claude/settings.json') | ConvertFrom-Json
    Assert ($settings.model -eq 'x' -and $settings.env.A -eq '1' -and $settings.env.CLAUDE_CODE_ENABLE_TODO_TOOLS -eq '1') 'settings.json lost its keys or missed the task list'
    Assert-Linked '.claude/CLAUDE.md' 'claude/CLAUDE.md'
    Assert (@(Get-ChildItem (Join-Path $Repo 'backup') -Recurse -Filter CLAUDE.md).Count -eq 1) 'the existing CLAUDE.md was not backed up'

    Initialize-Case 'check-only'
    Assert ((Invoke-Install @('-Check')) -ne 0) '-Check should fail on an empty home'
    Assert-Said 'missing'
    Assert (-not (Test-Path (Join-Path $Home_ '.claude'))) '-Check touched ~/.claude'
    Assert-NotCalled 'mcp add'
    Assert-NotCalled 'plugin install'

    Initialize-Case 'no-uv'
    $uvStub = Join-Path $stubs $(if ($OnWindows) { 'uv.cmd' } else { 'uv' })
    Move-Item $uvStub (Join-Path $Work 'uv.hidden')
    $env:PATH = "$prefix$sep$pathWithoutUv"
    $code = Invoke-Install @()
    $env:PATH = $path
    Move-Item (Join-Path $Work 'uv.hidden') $uvStub
    Assert ($code -ne 0) 'install should stop when uv is missing'
    Assert-Said 'winget install astral-sh.uv'
    Assert (-not (Test-Path (Join-Path $Home_ '.claude'))) 'nothing should be created without uv'
    Assert-NotCalled 'mcp add'

    Initialize-Case 'no-symlink'
    $env:CARDEA_ASSUME_NO_SYMLINK = '1'
    Assert ((Invoke-Install @()) -ne 0) 'install should stop when symlinks are not allowed'
    Remove-Item Env:CARDEA_ASSUME_NO_SYMLINK
    Assert-Said 'Developer Mode'
    Assert-Said 'Settings > System > For developers'
    Assert (-not (Test-Path (Join-Path $Home_ '.claude'))) 'nothing should be created without symlink rights'
    Assert-NotCalled 'mcp add'
    Assert-NotCalled 'plugin install'
    Assert-NotCalled 'git clone'
}
finally {
    $Out = ''
    Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
}

Write-Host 'ok: install.ps1 cases pass'
exit 0
