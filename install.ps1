# cardea: install the agent stack on Windows (PowerShell 5.1 or 7).
#
#   .\install.ps1            link the rules and skills, register the MCP servers and plugins
#   .\install.ps1 -Check     report prerequisites and links, change nothing
#
# safe to run repeatedly. existing files at a link target are moved to backup\<stamp>\.
# links are real symbolic links: they need Developer Mode or an elevated shell.
# if script execution is blocked, run it as:
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
#   pwsh -File .\install.ps1
# CARDEA_USER_HOME replaces the home directory (tests); CARDEA_ASSUME_NO_SYMLINK=1 forces
# the no-symlink path.
param([switch]$Check)

$RepoDir = $PSScriptRoot
$UserHome = if ($env:CARDEA_USER_HOME) { $env:CARDEA_USER_HOME } else { $HOME }
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$OnWindows = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
$script:Bad = 0

function Join-Parts { [IO.Path]::Combine([string[]]$args) }

function Step($Text) { Write-Host ''; Write-Host "> $Text" -ForegroundColor Blue }
function Ok($Text) { Write-Host "  + $Text" -ForegroundColor Green }
function Info($Text) { Write-Host "  . $Text" -ForegroundColor DarkGray }
function Warn($Text) { Write-Host "  ! $Text" -ForegroundColor Yellow }
function Bad($Text) { $script:Bad++; Write-Host "  x $Text" -ForegroundColor Red }

function Stop-Cardea($Text) {
    Write-Host ''
    Write-Host "cardea: $Text" -ForegroundColor Red
    exit 1
}

function Test-GitBash {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $false }

    if (-not $OnWindows) { return [bool](Get-Command bash -ErrorAction SilentlyContinue) }

    $dir = Split-Path (Get-Command git).Source

    if ($env:CLAUDE_CODE_GIT_BASH_PATH -and (Test-Path -LiteralPath $env:CLAUDE_CODE_GIT_BASH_PATH -PathType Leaf)) { return $true }

    return (Test-Path (Join-Parts $dir '..' 'bin' 'bash.exe')) -or (Test-Path (Join-Parts $dir '..' '..' 'bin' 'bash.exe'))
}

function Test-Python {
    if (-not (Get-Command py -ErrorAction SilentlyContinue)) { return $false }

    & py -3 --version *> $null

    return $LASTEXITCODE -eq 0
}

function Get-Prerequisites {
    @(
        @{ Name = 'Git for Windows with Git Bash'; Ok = (Test-GitBash); Hint = 'winget install Git.Git' }
        @{ Name = 'Python 3 (py)'; Ok = (Test-Python); Hint = 'winget install Python.Python.3.13' }
        @{ Name = 'uv (graphify)'; Ok = [bool](Get-Command uv -ErrorAction SilentlyContinue); Hint = 'winget install astral-sh.uv' }
        @{ Name = 'pnpm'; Ok = [bool](Get-Command pnpm -ErrorAction SilentlyContinue); Hint = 'winget install pnpm.pnpm' }
        @{ Name = 'GitHub CLI (gh)'; Ok = [bool](Get-Command gh -ErrorAction SilentlyContinue); Hint = 'winget install GitHub.cli' }
        @{ Name = 'claude CLI'; Ok = [bool](Get-Command claude -ErrorAction SilentlyContinue); Hint = 'install Claude Code, then run claude once' }
    )
}

function New-LinkItem($Path, $Target) {
    try {
        New-Item -ItemType SymbolicLink -Path $Path -Target $Target -ErrorAction Stop | Out-Null

        return
    }
    catch {
        $failure = $_
    }

    if (-not $OnWindows) { throw $failure }

    $flags = @()

    if (Test-Path -LiteralPath $Target -PathType Container) { $flags = @('/D') }

    $output = & cmd /c mklink @flags "$Path" "$Target" 2>&1

    if ($LASTEXITCODE -ne 0) { throw ($output -join ' ') }
}

function Test-SymlinkAllowed {
    if ($env:CARDEA_ASSUME_NO_SYMLINK -eq '1') { return $false }

    $scratch = New-Scratch
    $target = Join-Path $scratch 'target'
    Set-Content -Path $target -Value ''

    try {
        New-LinkItem (Join-Path $scratch 'link') $target

        return $true
    }
    catch {
        return $false
    }
    finally {
        Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue
    }
}

$Links = @(
    @{ Src = Join-Parts $RepoDir 'claude' 'CLAUDE.md'; Dest = Join-Parts $UserHome '.claude' 'CLAUDE.md' }
    @{ Src = Join-Parts $RepoDir 'claude' 'skills' 'tldr'; Dest = Join-Parts $UserHome '.claude' 'skills' 'tldr' }
    @{ Src = Join-Parts $RepoDir 'claude' 'skills' 'baby'; Dest = Join-Parts $UserHome '.claude' 'skills' 'baby' }
)

function Get-LinkState($Src, $Dest) {
    $item = Get-Item -LiteralPath $Dest -Force -ErrorAction SilentlyContinue

    if (-not $item) { return 'missing' }

    if ($item.LinkType -ne 'SymbolicLink') { return 'file' }

    if (@($item.Target)[0] -eq $Src) { return 'correct' }

    return 'elsewhere'
}

function Get-ShortPath($Dest) { $Dest.Substring($UserHome.Length).TrimStart('\', '/') }

function Set-Link($Src, $Dest) {
    $state = Get-LinkState $Src $Dest

    if ($state -eq 'correct') { Ok (Get-ShortPath $Dest); return }

    New-Item -ItemType Directory -Force -Path (Split-Path $Dest) | Out-Null

    if ($state -eq 'elsewhere') {
        (Get-Item -LiteralPath $Dest -Force).Delete()
    }
    elseif ($state -eq 'file') {
        $backup = Join-Parts $RepoDir 'backup' $Stamp
        New-Item -ItemType Directory -Force -Path $backup | Out-Null
        Move-Item -LiteralPath $Dest -Destination (Join-Path $backup (Split-Path $Dest -Leaf))
        Warn "existing $(Split-Path $Dest -Leaf) moved to backup\$Stamp\"
    }

    try {
        New-LinkItem $Dest $Src
        Ok (Get-ShortPath $Dest)
    }
    catch {
        Bad "$(Get-ShortPath $Dest): could not link ($($_.Exception.Message))"
    }
}

function Get-BasicMemoryUrl {
    if ($env:BASIC_MEMORY_URL) { return $env:BASIC_MEMORY_URL }

    $envFile = Join-Parts $RepoDir '.env'

    if (Test-Path $envFile) {
        $line = Select-String -Path $envFile -Pattern '^BASIC_MEMORY_URL=(.+)$' | Select-Object -First 1

        if ($line) { return $line.Matches[0].Groups[1].Value.Trim() }
    }

    return $null
}

function Register-Mcp($Name, [string[]]$AddArgs) {
    & claude mcp remove -s user $Name *> $null
    $output = & claude mcp add -s user @AddArgs 2>&1

    if ($LASTEXITCODE -eq 0) { Ok "mcp: $Name" } else { Bad "mcp: $Name - could not register"; Write-Host ($output | Out-String) }
}

function Install-Plugin($Id, $Source) {
    $list = (& claude plugin list --json 2>$null) -join "`n"

    if ($list -match ('"id":\s*"' + [regex]::Escape($Id) + '"')) {
        & claude plugin enable $Id *> $null
        & claude plugin update $Id *> $null

        if ($LASTEXITCODE -eq 0) { Ok "plugin: $Id" } else { Bad "plugin: $Id - update failed" }

        return
    }

    $plugin = ($Id -split '@')[0]
    & claude plugin install $plugin --marketplace $Source -y *> $null

    if ($LASTEXITCODE -eq 0) { Ok "plugin: $Id" } else { Bad "plugin: $Id - install failed" }
}

function Install-SkillDir($From, $Name) {
    $dest = Join-Parts $UserHome '.claude' 'skills' $Name

    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null

    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }

    Move-Item -LiteralPath $From -Destination $dest
}

function New-Scratch {
    $path = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $path | Out-Null

    return $path
}

function Install-VendoredSkills {
    & uv tool install graphifyy==0.9.88 *> $null

    if ($LASTEXITCODE -ne 0) { Warn 'graphify failed to install' }

    $toolBin = (& uv tool dir --bin 2>$null | Select-Object -First 1)

    if ($toolBin) { $env:PATH = "$toolBin$([IO.Path]::PathSeparator)$($env:PATH)" }

    if (-not (Get-Command graphify -ErrorAction SilentlyContinue)) {
        Warn 'graphify not found on PATH, skipping its skill'
    }
    else {
        $scratch = New-Scratch
        $savedConfigDir = $env:CLAUDE_CONFIG_DIR
        $savedUtf8 = $env:PYTHONUTF8
        $env:CLAUDE_CONFIG_DIR = $scratch
        $env:PYTHONUTF8 = '1'

        try {
            & graphify install *> $null
            $code = $LASTEXITCODE
        }
        finally {
            $env:CLAUDE_CONFIG_DIR = $savedConfigDir
            $env:PYTHONUTF8 = $savedUtf8
        }

        $built = Join-Parts $scratch 'skills' 'graphify'

        if ($code -eq 0 -and (Test-Path (Join-Path $built 'SKILL.md'))) {
            Install-SkillDir $built 'graphify'
            Ok 'graphify skill'
        }
        else {
            Warn 'graphify install did not produce a skill'
        }

        Remove-Item -Recurse -Force $scratch
    }

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Warn 'npm not found, skipping playwright-cli'
    }
    else {
        & npm install -g '@playwright/cli@0.1.24' *> $null

        if ($LASTEXITCODE -ne 0) { Warn 'playwright-cli failed to install' }

        if (-not (Get-Command playwright-cli -ErrorAction SilentlyContinue)) {
            Warn 'playwright-cli not found on PATH, skipping its skill'
        }
        else {
            & playwright-cli install-browser chromium *> $null

            if ($LASTEXITCODE -ne 0) { Warn 'chromium failed to install' }

            $scratch = New-Scratch
            $savedHome = $env:HOME
            $savedProfile = $env:USERPROFILE
            $env:HOME = $scratch
            $env:USERPROFILE = $scratch

            try {
                & playwright-cli install --skills claude --global *> $null
                $code = $LASTEXITCODE
            }
            finally {
                $env:HOME = $savedHome
                $env:USERPROFILE = $savedProfile
            }

            $built = Join-Parts $scratch '.claude' 'skills' 'playwright-cli'

            if ($code -eq 0 -and (Test-Path (Join-Path $built 'SKILL.md'))) {
                Install-SkillDir $built 'playwright-cli'
                Ok 'playwright-cli skill'
            }
            else {
                Warn 'playwright-cli install did not produce a skill'
            }

            Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue
        }
    }

    $scratch = New-Scratch
    $clone = Join-Path $scratch 'repo'
    & git clone -q --depth 1 https://github.com/marimo-team/skills $clone *> $null
    $built = Join-Parts $clone 'skills' 'marimo-notebook'

    if ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $built 'SKILL.md'))) {
        Install-SkillDir $built 'marimo-notebook'
        Ok 'marimo-notebook skill'
    }
    else {
        Warn 'could not fetch marimo-team/skills'
    }

    Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue

    $scratch = New-Scratch
    $clone = Join-Path $scratch 'repo'
    & git clone -q --depth 1 https://github.com/langfuse/skills $clone *> $null
    $built = Join-Parts $clone 'skills' 'langfuse'

    if ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $built 'SKILL.md'))) {
        Install-SkillDir $built 'langfuse'
        Ok 'langfuse skill'
    }
    else {
        Warn 'could not fetch langfuse/skills'
    }

    Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue
}

function Invoke-Checks {
    Step 'prerequisites'

    foreach ($p in Get-Prerequisites) {
        if ($p.Ok) { Ok $p.Name } else { Bad "$($p.Name) - not found ($($p.Hint))" }
    }

    if ($env:ANTHROPIC_API_KEY) { Warn 'ANTHROPIC_API_KEY is set: claude code will use it instead of your subscription' }

    Step 'links'

    foreach ($l in $Links) {
        $name = Get-ShortPath $l.Dest

        switch (Get-LinkState $l.Src $l.Dest) {
            'correct' { Ok $name }
            'missing' { Bad "$name - missing" }
            'elsewhere' { Bad "$name - points somewhere else" }
            'file' { Bad "$name - exists and is not a link" }
        }
    }

    if (Get-Command claude -ErrorAction SilentlyContinue) {
        Step 'claude code mcp servers'
        $servers = & claude mcp list 2>$null | Where-Object { $_ -match '^basic-memory:' }

        if ($servers) { $servers | ForEach-Object { Write-Host "  $_" } } else { Warn 'none registered yet' }
    }
}

Write-Host ''
Write-Host '  Cardea'
Write-Host '  Installs Claude Code, its MCP servers and plugins, and their NAS services.' -ForegroundColor DarkGray

if ($Check) {
    Invoke-Checks

    if (-not (Test-SymlinkAllowed)) { Warn 'symbolic links are not allowed here: enable Developer Mode (Settings > System > For developers) before installing' }

    Write-Host ''

    if ($script:Bad -gt 0) { exit 1 }

    exit 0
}

$missing = Get-Prerequisites | Where-Object { -not $_.Ok }

if ($missing) {
    $lines = $missing | ForEach-Object { "  - $($_.Name): $($_.Hint)" }
    Stop-Cardea "missing prerequisites, nothing was changed:`n$($lines -join "`n")"
}

if (-not (Test-SymlinkAllowed)) {
    Stop-Cardea 'cannot create symbolic links, nothing was changed. Enable Developer Mode (Settings > System > For developers) or run this from an elevated PowerShell, then rerun.'
}

Step 'links'

foreach ($l in $Links) { Set-Link $l.Src $l.Dest }

Step 'claude code settings'

# the task tools are off by default on newer models; an unreadable settings file is left alone.
$settingsPath = Join-Parts $UserHome '.claude' 'settings.json'

try {
    $settings = if (Test-Path $settingsPath) { Get-Content -Raw $settingsPath | ConvertFrom-Json } else { [pscustomobject]@{} }

    if (-not $settings.env) { $settings | Add-Member -NotePropertyName env -NotePropertyValue ([pscustomobject]@{}) -Force }

    if ($settings.env.CLAUDE_CODE_ENABLE_TODO_TOOLS -ne '1') {
        $settings.env | Add-Member -NotePropertyName CLAUDE_CODE_ENABLE_TODO_TOOLS -NotePropertyValue '1' -Force
        New-Item -ItemType Directory -Force -Path (Split-Path $settingsPath) | Out-Null
        $settings | ConvertTo-Json -Depth 20 | Set-Content -Path $settingsPath
    }

    Ok 'task list on (CLAUDE_CODE_ENABLE_TODO_TOOLS)'
}
catch {
    Warn 'could not set CLAUDE_CODE_ENABLE_TODO_TOOLS in ~/.claude/settings.json: add it to "env" by hand'
}

Step 'mcp servers'
$memoryUrl = Get-BasicMemoryUrl

if ($memoryUrl) {
    Register-Mcp 'basic-memory' @('--transport', 'http', 'basic-memory', $memoryUrl)
}
else {
    & claude mcp remove -s user basic-memory *> $null
    Info 'mcp: basic-memory - no url in BASIC_MEMORY_URL or .env, skipped'
}

Step 'plugins'
Install-Plugin 'cardea@cardea' $RepoDir
Install-Plugin 'superpowers@superpowers-marketplace' 'obra/superpowers-marketplace'
Install-Plugin 'ponytail@ponytail' 'DietrichGebert/ponytail'
Install-Plugin 'cloudflare@cloudflare' 'cloudflare/skills'
Install-Plugin 'humanizer@humanizer' 'blader/humanizer'

Step 'skills'
Install-VendoredSkills

Invoke-Checks

Write-Host ''
Write-Host 'Next' -ForegroundColor Blue
Write-Host '  1. claude auth login'
Write-Host '     sign in with your claude subscription (interactive)'
Write-Host ''
Write-Host '  re-run anytime. .\install.ps1 -Check probes without changing anything.' -ForegroundColor DarkGray
Write-Host ''
