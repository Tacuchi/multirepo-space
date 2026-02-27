#Requires -Version 5.1
<#
.SYNOPSIS
  multirepo-space - Multi-repo workspace manager for AI coding agents (PowerShell)
.DESCRIPTION
  Cross-platform port of multirepo-space for Windows native PowerShell.
  Subcommands: setup, add, remove, status
#>

param(
  [Parameter(Position = 0)]
  [string]$Command,
  [switch]$Yes,
  [Alias('n')]
  [switch]$DryRun,
  [Alias('v')]
  [switch]$Verbose_,
  [Alias('h')]
  [switch]$Help,
  [switch]$Version_,
  [Parameter(ValueFromRemainingArguments)]
  [string[]]$RemainingArgs
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = '1.1.0'
$ScriptDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$LibDir = Join-Path $ScriptDir 'lib'
$TmplDir = Join-Path $ScriptDir 'templates'

# --- Model/global agent options (defaults, overrideable by flags or config) ---
$script:ModelCoordinator = 'opus'
$script:ModelSpecialist = 'sonnet'
function Write-Info  { param([string]$Msg) Write-Host "[info] $Msg" -ForegroundColor Blue }
function Write-Warn  { param([string]$Msg) Write-Host "[warn] $Msg" -ForegroundColor Yellow }
function Write-Err   { param([string]$Msg) Write-Host "[error] $Msg" -ForegroundColor Red }
function Write-Ok    { param([string]$Msg) Write-Host "[ok] $Msg" -ForegroundColor Green }

function Write-Verbose_ {
  param([string]$Msg)
  if ($script:Verbose_) { Write-Info $Msg }
}

function Join-PathSegments {
  param([string[]]$Segments)
  $result = $Segments[0]
  for ($i = 1; $i -lt $Segments.Count; $i++) {
    $result = Join-Path $result $Segments[$i]
  }
  return $result
}

function Confirm-Action {
  param([string]$Msg = 'Continue?')
  if ($script:Yes) { return $true }
  $answer = Read-Host "$Msg [y/N]"
  return $answer -match '^[Yy]$'
}

function Get-Template {
  param([string]$TmplFile)
  if (-not (Test-Path $TmplFile)) { throw "Template not found: $TmplFile" }
  Get-Content -Path $TmplFile -Raw
}

function Write-OutputFile {
  param([string]$Dest, [string]$Content)
  if ($script:DryRun) {
    Write-Info "[dry-run] Would write: $Dest"
    return
  }
  $dir = Split-Path -Parent $Dest
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  Set-Content -Path $Dest -Value $Content -NoNewline
  Write-Verbose_ "Written: $Dest"
}

function New-RepoLink {
  param([string]$LinkPath, [string]$Target)
  if (Test-Path $LinkPath) { Remove-Item $LinkPath -Force }
  try {
    New-Item -ItemType SymbolicLink -Path $LinkPath -Target $Target -ErrorAction Stop | Out-Null
    Write-Verbose_ "Symlink: $LinkPath -> $Target"
  }
  catch {
    New-Item -ItemType Junction -Path $LinkPath -Target $Target -ErrorAction Stop | Out-Null
    Write-Verbose_ "Junction (fallback): $LinkPath -> $Target"
  }
}

# --- Agent file writer (frontmatter for .claude/agents/ only) ---

function Write-AgentFile {
  param(
    [string]$WorkspacePath,
    [string]$AgentFilename,
    [string]$Body,
    [string]$Model,
    [string]$Description,
    [string]$AllowedTools
  )
  $agentName = $AgentFilename -replace '\.md$', ''

  # .agents/ — plain markdown (Codex/Gemini/Cursor compatible)
  Write-OutputFile (Join-PathSegments $WorkspacePath, '.agents', $AgentFilename) $Body

  # .claude/agents/ — with YAML frontmatter (name is required for Claude Code discovery)
  $frontmatter = "---`nname: $agentName`nmodel: $Model`ndescription: `"$Description`"`ntools: [$AllowedTools]`n---`n`n"
  $withFrontmatter = $frontmatter + $Body
  Write-OutputFile (Join-PathSegments $WorkspacePath, '.claude', 'agents', $AgentFilename) $withFrontmatter
}

# --- Config persistence ---

function Save-WorkspaceConfig {
  param([string]$WorkspacePath)
  $configFile = Join-PathSegments $WorkspacePath, '.claude', '.multirepo-space.conf'

  if ($script:DryRun) {
    Write-Info "[dry-run] Would save config: $configFile"
    return
  }

  $dir = Split-Path -Parent $configFile
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

  $configContent = @"
MODEL_COORDINATOR=$($script:ModelCoordinator)
MODEL_SPECIALIST=$($script:ModelSpecialist)
"@
  Set-Content -Path $configFile -Value $configContent -NoNewline
  Write-Verbose_ "Saved config: $configFile"
}

function Import-WorkspaceConfig {
  param([string]$WorkspacePath)
  $configFile = Join-PathSegments $WorkspacePath, '.claude', '.multirepo-space.conf'

  if (Test-Path $configFile) {
    $lines = Get-Content -Path $configFile
    foreach ($line in $lines) {
      if ($line -match '^MODEL_COORDINATOR=(.+)$') { $script:ModelCoordinator = $Matches[1] }
      elseif ($line -match '^MODEL_SPECIALIST=(.+)$') { $script:ModelSpecialist = $Matches[1] }
    }
    Write-Verbose_ "Loaded config from: $configFile"
  }
}

# --- Sanitization ---

function Invoke-Sanitize {
  param([string]$Value, [int]$MaxLength = 100)
  $Value = $Value -replace '[\x00-\x09\x0B-\x1F]', ''
  $Value = $Value -replace '`', ''
  $Value = $Value -replace '\$\([^)]*\)', ''
  $Value = $Value -replace '\$\{[^}]*\}', ''
  $Value = $Value -replace '<!--[^>]*-->', ''
  $Value = $Value -replace '\{\{[^}]*\}\}', ''
  $Value = $Value -replace '[<>]', ''
  if ($Value.Length -gt $MaxLength) { $Value = $Value.Substring(0, $MaxLength) }
  return $Value
}

# --- Stack Detection ---

function Invoke-DetectStack {
  param([string]$RepoPath)

  $result = @{
    PrimaryTech = ''
    Framework   = ''
    StackCsv    = ''
    VerifyCmds  = ''
    StackParts  = [System.Collections.ArrayList]::new()
  }

  $pkgPath = Join-Path $RepoPath 'package.json'
  if (Test-Path $pkgPath) {
    $pkg = Get-Content -Path $pkgPath -Raw
    if ($pkg -match '"@angular/core"') {
      $ver = ''
      if ($pkg -match '"@angular/core"\s*:\s*"[~^]?(\d+)') { $ver = $Matches[1] }
      $result.PrimaryTech = 'TypeScript'
      $result.Framework = "Angular $ver"
      $result.VerifyCmds = 'ng build, ng test, ng lint'
      [void]$result.StackParts.Add("Angular $ver")
    }
    elseif ($pkg -match '"next"') {
      $result.PrimaryTech = 'TypeScript/JS'; $result.Framework = 'Next.js'
      $result.VerifyCmds = 'npm run build, npm run lint'
      [void]$result.StackParts.Add('Next.js')
    }
    elseif ($pkg -match '"react"') {
      $result.PrimaryTech = 'TypeScript/JS'; $result.Framework = 'React'
      $result.VerifyCmds = 'npm run build, npm test'
      [void]$result.StackParts.Add('React')
    }
    elseif ($pkg -match '"vue"') {
      $result.PrimaryTech = 'TypeScript/JS'; $result.Framework = 'Vue.js'
      $result.VerifyCmds = 'npm run build, npm test'
      [void]$result.StackParts.Add('Vue.js')
    }
    elseif ($pkg -match '"svelte"') {
      $result.PrimaryTech = 'TypeScript/JS'; $result.Framework = 'Svelte'
      $result.VerifyCmds = 'npm run build, npm run check'
      [void]$result.StackParts.Add('Svelte')
    }
    elseif ($pkg -match '"nuxt"') {
      $result.PrimaryTech = 'TypeScript/JS'; $result.Framework = 'Nuxt'
      $result.VerifyCmds = 'npm run build, npm run lint'
      [void]$result.StackParts.Add('Nuxt')
    }
  }

  $pomPath = Join-Path $RepoPath 'pom.xml'
  if (Test-Path $pomPath) {
    $pom = Get-Content -Path $pomPath -Raw
    if ($pom -match 'spring-boot-starter') {
      $sbVersion = ''
      if ($pom -match 'spring-boot-starter-parent[\s\S]*?<version>([^<]+)') {
        $sbVersion = ($Matches[1] -split '\.')[0..1] -join '.'
      }
      $javaVersion = ''
      if ($pom -match '<java\.version>([^<]+)') { $javaVersion = $Matches[1] }
      elseif ($pom -match '<maven\.compiler\.source>([^<]+)') { $javaVersion = $Matches[1] }

      $jvSuffix = if ($javaVersion) { " $javaVersion" } else { '' }
      $sbSuffix = if ($sbVersion) { " $sbVersion" } else { '' }
      $result.PrimaryTech = "Java$jvSuffix"
      $result.Framework = "Spring Boot$sbSuffix + Maven"
      $result.VerifyCmds = 'mvn compile, mvn test, mvn verify'
      [void]$result.StackParts.Add("Spring Boot$sbSuffix")
      [void]$result.StackParts.Add('Maven')
      if ($javaVersion) { [void]$result.StackParts.Add("Java $javaVersion") }

      if ($pom -match 'spring-boot-starter-data-jpa') { [void]$result.StackParts.Add('JPA') }
      if ($pom -match 'spring-cloud-starter-openfeign') { [void]$result.StackParts.Add('Feign') }
      if ($pom -match 'postgresql') { [void]$result.StackParts.Add('PostgreSQL') }
      if ($pom -match 'mysql-connector') { [void]$result.StackParts.Add('MySQL') }
      if ($pom -match 'spring-boot-starter-data-mongodb') { [void]$result.StackParts.Add('MongoDB') }
    }
  }

  $gradleKts = Join-Path $RepoPath 'build.gradle.kts'
  $gradleGroovy = Join-Path $RepoPath 'build.gradle'
  $gradleFile = if (Test-Path $gradleKts) { $gradleKts } elseif (Test-Path $gradleGroovy) { $gradleGroovy } else { $null }
  if ($gradleFile) {
    $gradle = Get-Content -Path $gradleFile -Raw
    if ($gradle -match 'org\.springframework\.boot' -and -not $result.PrimaryTech) {
      $result.PrimaryTech = if ($gradleFile -like '*.kts') { 'Kotlin' } else { 'Java/Kotlin' }
      $result.Framework = 'Spring Boot + Gradle'
      $result.VerifyCmds = 'gradle build, gradle test'
      [void]$result.StackParts.Add('Spring Boot')
      [void]$result.StackParts.Add('Gradle')
    }
  }

  $pyprojectPath = Join-Path $RepoPath 'pyproject.toml'
  $requirementsPath = Join-Path $RepoPath 'requirements.txt'
  if (Test-Path $pyprojectPath) {
    $pyproj = Get-Content -Path $pyprojectPath -Raw
    if ($pyproj -match '(?i)django') {
      $result.PrimaryTech = 'Python'; $result.Framework = 'Django'
      $result.VerifyCmds = 'python manage.py test'
      [void]$result.StackParts.Add('Django')
    }
    elseif ($pyproj -match '(?i)fastapi') {
      $result.PrimaryTech = 'Python'; $result.Framework = 'FastAPI'
      $result.VerifyCmds = 'pytest'
      [void]$result.StackParts.Add('FastAPI')
    }
    elseif ($pyproj -match '(?i)flask') {
      $result.PrimaryTech = 'Python'; $result.Framework = 'Flask'
      $result.VerifyCmds = 'pytest'
      [void]$result.StackParts.Add('Flask')
    }
  }
  elseif (Test-Path $requirementsPath) {
    $reqs = Get-Content -Path $requirementsPath -Raw
    if ($reqs -match '(?i)django') {
      $result.PrimaryTech = 'Python'; $result.Framework = 'Django'
      $result.VerifyCmds = 'python manage.py test'
      [void]$result.StackParts.Add('Django')
    }
    elseif ($reqs -match '(?i)fastapi') {
      $result.PrimaryTech = 'Python'; $result.Framework = 'FastAPI'
      $result.VerifyCmds = 'pytest'
      [void]$result.StackParts.Add('FastAPI')
    }
    elseif ($reqs -match '(?i)flask') {
      $result.PrimaryTech = 'Python'; $result.Framework = 'Flask'
      $result.VerifyCmds = 'pytest'
      [void]$result.StackParts.Add('Flask')
    }
  }

  if ((Test-Path (Join-Path $RepoPath 'go.mod')) -and -not $result.PrimaryTech) {
    $goMod = Get-Content -Path (Join-Path $RepoPath 'go.mod') -Head 5
    $goVer = ''
    foreach ($line in $goMod) {
      if ($line -match '^go\s+(.+)') { $goVer = $Matches[1]; break }
    }
    $goSuffix = if ($goVer) { " $goVer" } else { '' }
    $result.PrimaryTech = "Go$goSuffix"
    $result.VerifyCmds = 'go build ./..., go test ./...'
    [void]$result.StackParts.Add("Go$goSuffix")
  }

  if ((Test-Path (Join-Path $RepoPath 'Cargo.toml')) -and -not $result.PrimaryTech) {
    $result.PrimaryTech = 'Rust'
    $result.VerifyCmds = 'cargo build, cargo test'
    [void]$result.StackParts.Add('Rust')
  }

  $pubspecPath = Join-Path $RepoPath 'pubspec.yaml'
  if ((Test-Path $pubspecPath) -and -not $result.PrimaryTech) {
    $pubspec = Get-Content -Path $pubspecPath -Raw
    if ($pubspec -match 'flutter') {
      $result.PrimaryTech = 'Dart'; $result.Framework = 'Flutter'
      $result.VerifyCmds = 'flutter analyze, flutter test'
      [void]$result.StackParts.Add('Flutter')
    }
    else {
      $result.PrimaryTech = 'Dart'
      $result.VerifyCmds = 'dart analyze, dart test'
      [void]$result.StackParts.Add('Dart')
    }
  }

  if ((Get-ChildItem -Path $RepoPath -Filter '*.csproj' -ErrorAction SilentlyContinue) -and -not $result.PrimaryTech) {
    $result.PrimaryTech = 'C#'; $result.Framework = '.NET'
    $result.VerifyCmds = 'dotnet build, dotnet test'
    [void]$result.StackParts.Add('.NET')
  }

  # Supplementary
  if (Test-Path (Join-Path $RepoPath 'tsconfig.json')) {
    if ($result.StackParts -notcontains 'TypeScript' -and $result.PrimaryTech -ne 'TypeScript') {
      [void]$result.StackParts.Add('TypeScript')
    }
  }

  $srcPath = Join-Path $RepoPath 'src'
  if (Test-Path $srcPath) {
    if (Get-ChildItem -Path $srcPath -Filter '*.scss' -Recurse -ErrorAction SilentlyContinue) {
      [void]$result.StackParts.Add('SCSS')
    }
  }

  if (Get-ChildItem -Path $RepoPath -Filter 'tailwind.config.*' -ErrorAction SilentlyContinue) {
    [void]$result.StackParts.Add('Tailwind CSS')
  }

  if (Test-Path $pkgPath) {
    $pkg = Get-Content -Path $pkgPath -Raw
    if ($pkg -match '"bootstrap"') { [void]$result.StackParts.Add('Bootstrap') }
    if ($pkg -match '"@angular/material"') { [void]$result.StackParts.Add('Angular Material') }
  }

  if (Test-Path (Join-Path $RepoPath 'Dockerfile')) {
    [void]$result.StackParts.Add('Docker')
  }

  # Fallback
  if (-not $result.PrimaryTech) {
    $result.PrimaryTech = 'Generic'
  }

  # Sanitize all values before returning
  $result.PrimaryTech = Invoke-Sanitize $result.PrimaryTech 50
  $result.Framework = Invoke-Sanitize $result.Framework 100
  $result.VerifyCmds = Invoke-Sanitize $result.VerifyCmds 200

  $sanitized = [System.Collections.ArrayList]::new()
  foreach ($part in $result.StackParts) {
    [void]$sanitized.Add((Invoke-Sanitize $part 50))
  }
  $result.StackParts = $sanitized

  if ($result.StackParts.Count -gt 0) {
    $result.StackCsv = $result.StackParts -join ', '
  }
  else {
    $result.StackCsv = $result.PrimaryTech
  }

  return $result
}

function Get-RepoAlias {
  param([string]$RepoPath)
  $alias = Split-Path -Leaf $RepoPath
  $alias = $alias -replace '[_.]', '-'
  if ($alias.Length -gt 30) { $alias = $alias.Substring(0, 30) }
  return $alias
}

# --- Managed Block ---

function Sync-ManagedBlock {
  param([string]$TargetFile, [string]$Block)

  $startMarker = '<!-- MULTIREPO_SPACE_MANAGED:START -->'
  $endMarker = '<!-- MULTIREPO_SPACE_MANAGED:END -->'

  if ($script:DryRun) {
    Write-Info "[dry-run] Would sync managed block in: $TargetFile"
    return
  }

  if (Test-Path $TargetFile) {
    $content = Get-Content -Path $TargetFile -Raw
    if ($content -match [regex]::Escape($startMarker)) {
      $pattern = "(?s)$([regex]::Escape($startMarker)).*?$([regex]::Escape($endMarker))"
      $content = $content -replace $pattern, $Block.TrimEnd()
      Set-Content -Path $TargetFile -Value $content -NoNewline
    }
    else {
      Add-Content -Path $TargetFile -Value "`n$Block"
    }
  }
  else {
    Set-Content -Path $TargetFile -Value $Block -NoNewline
  }
  Write-Verbose_ "Synced managed block: $TargetFile"
}

# --- regenerate workspace docs ---

function Invoke-RegenerateWorkspaceDocs {
  param([string]$WorkspacePath)

  $today = Get-Date -Format 'yyyy-MM-dd'

  # Load saved config
  Import-WorkspaceConfig -WorkspacePath $WorkspacePath

  # Scan current repos from symlinks
  $regenAliases = @()
  $regenPaths = @()
  $regenTechs = @()
  $regenCsvs = @()
  $regenVcmds = @()

  $reposDir = Join-Path $WorkspacePath 'repos'
  if (Test-Path $reposDir) {
    foreach ($item in Get-ChildItem -Path $reposDir) {
      if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
      $a = $item.Name
      $p = @($item.Target)[0]
      if (-not (Test-Path $p -PathType Container)) { continue }

      $det = Invoke-DetectStack -RepoPath $p
      $regenAliases += $a
      $regenPaths += $p
      $regenTechs += $det.PrimaryTech
      $regenCsvs += $det.StackCsv
      $regenVcmds += $det.VerifyCmds
    }
  }

  $N = $regenAliases.Count
  $reposWord = if ($N -eq 1) { 'repositorio' } else { 'repositorios' }

  # 1. Regenerate coordinator
  $specialistList = ''
  for ($i = 0; $i -lt $N; $i++) {
    if ($i -gt 0) {
      $specialistList += if ($i -eq ($N - 1)) { ' y ' } else { ', ' }
    }
    $specialistList += "``$($regenAliases[$i])``"
  }

  $skillsSection = ''
  $mcpSection = ''

  $coordinator = Get-Template (Join-Path $TmplDir 'coordinator.md.tmpl')
  $coordinator = $coordinator -replace '\{\{N\}\}', $N
  $coordinator = $coordinator -replace '\{\{repos_word\}\}', $reposWord
  $coordinator = $coordinator -replace '\{\{specialist_list\}\}', $specialistList
  $coordinator = $coordinator -replace '\{\{skills_section\}\}', $skillsSection
  $coordinator = $coordinator -replace '\{\{mcp_section\}\}', $mcpSection

  Write-AgentFile -WorkspacePath $WorkspacePath -AgentFilename 'coordinator.md' -Body $coordinator `
    -Model $script:ModelCoordinator `
    -Description "Orquestador multi-repo. Coordina $N repos, delega a especialistas y consolida resultados." `
    -AllowedTools '"Read", "Glob", "Grep", "Task", "Bash"'

  # 2. Regenerate AGENTS.md + CLAUDE.md
  $reposTable = ''
  for ($i = 0; $i -lt $N; $i++) {
    $repoBase = Split-Path -Leaf $regenPaths[$i]
    $reposTable += "| **Repo $($i+1)** ($($regenAliases[$i])) | $repoBase | ``$($regenPaths[$i])`` | $($regenCsvs[$i]) |`n"
  }

  $symlinksTable = ''
  for ($i = 0; $i -lt $N; $i++) {
    $symlinksTable += "| $($regenAliases[$i]) | ``$($regenPaths[$i])`` |`n"
  }

  $agentsTable = "| ``coordinator`` | Orquesta trabajo multi-repo, delega a especialistas | Workspace completo |`n"
  for ($i = 0; $i -lt $N; $i++) {
    $agentsTable += "| ``$($regenAliases[$i])`` | Especialista $($regenTechs[$i]) | Repo $($i+1) |`n"
  }

  $instructions = Get-Template (Join-Path $TmplDir 'workspace-instructions.md.tmpl')
  $instructions = $instructions -replace '\{\{N\}\}', $N
  $instructions = $instructions -replace '\{\{repos_word\}\}', $reposWord
  $instructions = $instructions -replace '\{\{repos_table\}\}', $reposTable
  $instructions = $instructions -replace '\{\{symlinks_table\}\}', $symlinksTable
  $instructions = $instructions -replace '\{\{agents_table\}\}', $agentsTable
  $instructions = $instructions -replace '\{\{today\}\}', $today

  Write-OutputFile (Join-Path $WorkspacePath 'AGENTS.md') $instructions
  Write-OutputFile (Join-Path $WorkspacePath 'CLAUDE.md') $instructions

  # 3. Regenerate .claude/settings.json
  $additionalDirs = @()
  for ($i = 0; $i -lt $N; $i++) {
    $comma = if ($i -lt ($N - 1)) { ',' } else { '' }
    $additionalDirs += "    `"$($regenPaths[$i])`"$comma"
  }
  $settingsContent = Get-Template (Join-Path $TmplDir 'settings.json.tmpl')
  $settingsContent = $settingsContent -replace '\{\{additional_directories\}\}', ($additionalDirs -join "`n")
  Write-OutputFile (Join-PathSegments $WorkspacePath, '.claude', 'settings.json') $settingsContent


  Write-Verbose_ "Regenerated workspace docs ($N repos)"
}

# --- setup ---

function Invoke-Setup {
  param([string[]]$Args_)

  $workspacePath = Resolve-Path $Args_[0] | Select-Object -ExpandProperty Path
  $repoPaths = @()
  for ($i = 1; $i -lt $Args_.Count; $i++) {
    $repoPaths += (Resolve-Path $Args_[$i] | Select-Object -ExpandProperty Path)
  }

  if (-not (Test-Path $workspacePath -PathType Container)) {
    throw "Workspace path does not exist: $workspacePath"
  }
  foreach ($rp in $repoPaths) {
    if (-not (Test-Path $rp -PathType Container)) { throw "Repo path does not exist: $rp" }
  }

  $settingsJson = Join-PathSegments $workspacePath, '.claude', 'settings.json'
  $agentsMd = Join-Path $workspacePath 'AGENTS.md'
  if ((Test-Path $settingsJson) -or (Test-Path $agentsMd)) {
    Write-Warn 'Workspace already has configuration files.'
    if (-not (Confirm-Action 'Overwrite existing configuration?')) { Write-Info 'Aborted.'; return }
  }

  $workspaceName = Split-Path -Leaf $workspacePath
  $today = Get-Date -Format 'yyyy-MM-dd'
  $N = $repoPaths.Count

  Write-Info "Detecting stacks for $N repos..."

  $aliases = @()
  $primaryTechs = @()
  $stackCsvs = @()
  $verifyCmdsList = @()

  foreach ($rp in $repoPaths) {
    $det = Invoke-DetectStack -RepoPath $rp
    $alias = Get-RepoAlias -RepoPath $rp
    $aliases += $alias
    $primaryTechs += $det.PrimaryTech
    $stackCsvs += $det.StackCsv
    $verifyCmdsList += $det.VerifyCmds
  }

  # Detect and resolve duplicate aliases
  $aliasSeen = @{}
  for ($i = 0; $i -lt $aliases.Count; $i++) {
    $a = $aliases[$i]
    if ($aliasSeen.ContainsKey($a)) {
      $aliasSeen[$a]++
      $aliases[$i] = "$a-$($aliasSeen[$a])"
      Write-Warn "Duplicate alias '$a' resolved to '$($aliases[$i])'"
    } else {
      $aliasSeen[$a] = 1
    }
  }

  Write-Host ''
  Write-Info "Workspace: $workspacePath"
  Write-Info "Models: coordinator=$($script:ModelCoordinator), specialist=$($script:ModelSpecialist)"
  Write-Host ''
  '{0,-4} {1,-25} {2,-45} {3}' -f '#', 'Alias', 'Path', 'Stack' | Write-Host
  '{0,-4} {1,-25} {2,-45} {3}' -f '---', '-------------------------', '---------------------------------------------', '--------------------' | Write-Host
  for ($i = 0; $i -lt $N; $i++) {
    '{0,-4} {1,-25} {2,-45} {3}' -f ($i + 1), $aliases[$i], $repoPaths[$i], $stackCsvs[$i] | Write-Host
  }
  Write-Host ''

  if (-not (Confirm-Action 'Proceed with this configuration?')) { Write-Info 'Aborted.'; return }

  Write-Info 'Generating workspace files...'

  # 1. settings.json
  $additionalDirs = @()
  for ($i = 0; $i -lt $N; $i++) {
    $comma = if ($i -lt ($N - 1)) { ',' } else { '' }
    $additionalDirs += "    `"$($repoPaths[$i])`"$comma"
  }
  $settingsContent = Get-Template (Join-Path $TmplDir 'settings.json.tmpl')
  $settingsContent = $settingsContent -replace '\{\{additional_directories\}\}', ($additionalDirs -join "`n")
  Write-OutputFile (Join-PathSegments $workspacePath, '.claude', 'settings.json') $settingsContent

  # 2. AGENTS.md + CLAUDE.md
  $reposTable = ''
  for ($i = 0; $i -lt $N; $i++) {
    $repoBase = Split-Path -Leaf $repoPaths[$i]
    $reposTable += "| **Repo $($i+1)** ($($aliases[$i])) | $repoBase | ``$($repoPaths[$i])`` | $($stackCsvs[$i]) |`n"
  }

  $symlinksTable = ''
  for ($i = 0; $i -lt $N; $i++) {
    $symlinksTable += "| $($aliases[$i]) | ``$($repoPaths[$i])`` |`n"
  }

  $agentsTable = "| ``coordinator`` | Orquesta trabajo multi-repo, delega a especialistas | Workspace completo |`n"
  for ($i = 0; $i -lt $N; $i++) {
    $agentsTable += "| ``$($aliases[$i])`` | Especialista $($primaryTechs[$i]) | Repo $($i+1) |`n"
  }

  $reposWord = if ($N -eq 1) { 'repositorio' } else { 'repositorios' }

  $instructions = Get-Template (Join-Path $TmplDir 'workspace-instructions.md.tmpl')
  $instructions = $instructions -replace '\{\{N\}\}', $N
  $instructions = $instructions -replace '\{\{repos_word\}\}', $reposWord
  $instructions = $instructions -replace '\{\{repos_table\}\}', $reposTable
  $instructions = $instructions -replace '\{\{symlinks_table\}\}', $symlinksTable
  $instructions = $instructions -replace '\{\{agents_table\}\}', $agentsTable
  $instructions = $instructions -replace '\{\{today\}\}', $today

  Write-OutputFile (Join-Path $workspacePath 'AGENTS.md') $instructions
  Write-OutputFile (Join-Path $workspacePath 'CLAUDE.md') $instructions

  # 3. Coordinator
  $specialistList = ''
  for ($i = 0; $i -lt $N; $i++) {
    if ($i -gt 0) {
      $specialistList += if ($i -eq ($N - 1)) { ' y ' } else { ', ' }
    }
    $specialistList += "``$($aliases[$i])``"
  }

  $skillsSection = ''
  $mcpSection = ''

  $coordinator = Get-Template (Join-Path $TmplDir 'coordinator.md.tmpl')
  $coordinator = $coordinator -replace '\{\{N\}\}', $N
  $coordinator = $coordinator -replace '\{\{repos_word\}\}', $reposWord
  $coordinator = $coordinator -replace '\{\{specialist_list\}\}', $specialistList
  $coordinator = $coordinator -replace '\{\{skills_section\}\}', $skillsSection
  $coordinator = $coordinator -replace '\{\{mcp_section\}\}', $mcpSection

  Write-AgentFile -WorkspacePath $workspacePath -AgentFilename 'coordinator.md' -Body $coordinator `
    -Model $script:ModelCoordinator `
    -Description "Orquestador multi-repo. Coordina $N repos, delega a especialistas y consolida resultados." `
    -AllowedTools '"Read", "Glob", "Grep", "Task", "Bash"'

  # 4. Specialist agents
  for ($i = 0; $i -lt $N; $i++) {
    $stackList = ''
    foreach ($part in ($stackCsvs[$i] -split ',')) {
      $part = $part.Trim()
      $stackList += "- $part`n"
    }

    $specialist = Get-Template (Join-Path $TmplDir 'specialist.md.tmpl')
    $specialist = $specialist -replace '\{\{alias\}\}', $aliases[$i]
    $specialist = $specialist -replace '\{\{primary_tech\}\}', $primaryTechs[$i]
    $specialist = $specialist -replace '\{\{repo_path\}\}', $repoPaths[$i]
    $specialist = $specialist -replace '\{\{stack_list\}\}', $stackList
    $specialist = $specialist -replace '\{\{verify_cmds\}\}', $verifyCmdsList[$i]
    $specialist = $specialist -replace '\{\{skills_section\}\}', $skillsSection
    $specialist = $specialist -replace '\{\{mcp_section\}\}', $mcpSection

    Write-AgentFile -WorkspacePath $workspacePath -AgentFilename "repo-$($aliases[$i]).md" -Body $specialist `
      -Model $script:ModelSpecialist `
      -Description "Especialista $($primaryTechs[$i]) — repo $($aliases[$i])" `
      -AllowedTools '"Read", "Edit", "Write", "Glob", "Grep", "Bash"'
  }

  # 5. Output directories
  Write-OutputFile (Join-PathSegments $workspacePath, 'docs', '.gitkeep') ''
  Write-OutputFile (Join-PathSegments $workspacePath, 'scripts', '.gitkeep') ''

  # 6. Symlinks
  Write-Info 'Creating repo symlinks...'
  $reposDir = Join-Path $workspacePath 'repos'
  if (-not $script:DryRun) {
    if (-not (Test-Path $reposDir)) { New-Item -ItemType Directory -Path $reposDir -Force | Out-Null }
  }
  for ($i = 0; $i -lt $N; $i++) {
    $linkPath = Join-Path $reposDir $aliases[$i]
    if ($script:DryRun) {
      Write-Info "[dry-run] Would symlink: $linkPath -> $($repoPaths[$i])"
    }
    else {
      New-RepoLink -LinkPath $linkPath -Target $repoPaths[$i]
    }
  }

  # 7. Sync managed blocks
  Write-Info 'Syncing managed blocks in repos...'
  for ($i = 0; $i -lt $N; $i++) {
    $verifyCmdListStr = ''
    if ($verifyCmdsList[$i]) {
      foreach ($vc in ($verifyCmdsList[$i] -split ',')) {
        $vc = $vc.Trim()
        $verifyCmdListStr += "- ``$vc```n"
      }
    }

    $block = Get-Template (Join-Path $TmplDir 'managed-block.md.tmpl')
    $block = $block -replace '\{\{workspace_name\}\}', $workspaceName
    $block = $block -replace '\{\{workspace_path\}\}', $workspacePath
    $block = $block -replace '\{\{alias\}\}', $aliases[$i]
    $block = $block -replace '\{\{verify_cmds_list\}\}', $verifyCmdListStr

    foreach ($targetFile in @('AGENTS.md', 'CLAUDE.md')) {
      Sync-ManagedBlock (Join-Path $repoPaths[$i] $targetFile) $block
    }
  }

  # 8. Save workspace config
  Save-WorkspaceConfig -WorkspacePath $workspacePath


  # 10. Verify
  Write-Info 'Verifying workspace integrity...'
  $fileCount = (Get-ChildItem -Path $workspacePath -Recurse -File -Include '*.md', '*.json', '.gitkeep', '*.conf' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }).Count
  $symlinkCount = (Get-ChildItem -Path $reposDir -ErrorAction SilentlyContinue |
    Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count

  Write-Host ''
  Write-Ok 'Workspace created successfully!'
  Write-Info "  Files generated: $fileCount"
  Write-Info "  Symlinks created: $symlinkCount"
  Write-Info "  Repos configured: $N"
  Write-Host ''
  Write-Info "Next steps:"
  Write-Info "  cd $workspacePath; claude"
  Write-Info "  cd $workspacePath; codex"
}

# --- add ---

function Invoke-Add {
  param([string[]]$Args_)

  $workspacePath = Resolve-Path $Args_[0] | Select-Object -ExpandProperty Path
  $repoPath = Resolve-Path $Args_[1] | Select-Object -ExpandProperty Path

  if (-not (Test-Path (Join-Path $workspacePath 'AGENTS.md'))) {
    throw "Not a valid workspace: $workspacePath (no AGENTS.md found)"
  }
  if (-not (Test-Path $repoPath -PathType Container)) { throw "Repo path does not exist: $repoPath" }

  # Load saved config
  Import-WorkspaceConfig -WorkspacePath $workspacePath

  $workspaceName = Split-Path -Leaf $workspacePath

  $det = Invoke-DetectStack -RepoPath $repoPath
  $aliasName = Get-RepoAlias -RepoPath $repoPath

  # Check for alias collision with existing repos
  $existingLink = Join-PathSegments $workspacePath, 'repos', $aliasName
  if (Test-Path $existingLink) {
    $suffix = 2
    while (Test-Path (Join-PathSegments $workspacePath, 'repos', "$aliasName-$suffix")) {
      $suffix++
    }
    Write-Warn "Alias '$aliasName' already exists, using '$aliasName-$suffix'"
    $aliasName = "$aliasName-$suffix"
  }

  Write-Info "Adding repo: $aliasName ($($det.StackCsv))"
  if (-not (Confirm-Action "Add '$aliasName' to workspace?")) { Write-Info 'Aborted.'; return }

  # Create specialist
  $stackList = ''
  foreach ($part in ($det.StackCsv -split ',')) {
    $stackList += "- $($part.Trim())`n"
  }

  $skillsSection = ''
  $mcpSection = ''

  $specialist = Get-Template (Join-Path $TmplDir 'specialist.md.tmpl')
  $specialist = $specialist -replace '\{\{alias\}\}', $aliasName
  $specialist = $specialist -replace '\{\{primary_tech\}\}', $det.PrimaryTech
  $specialist = $specialist -replace '\{\{repo_path\}\}', $repoPath
  $specialist = $specialist -replace '\{\{stack_list\}\}', $stackList
  $specialist = $specialist -replace '\{\{verify_cmds\}\}', $det.VerifyCmds
  $specialist = $specialist -replace '\{\{skills_section\}\}', $skillsSection
  $specialist = $specialist -replace '\{\{mcp_section\}\}', $mcpSection

  Write-AgentFile -WorkspacePath $workspacePath -AgentFilename "repo-$aliasName.md" -Body $specialist `
    -Model $script:ModelSpecialist `
    -Description "Especialista $($det.PrimaryTech) — repo $aliasName" `
    -AllowedTools '"Read", "Edit", "Write", "Glob", "Grep", "Bash"'

  # Symlink
  if (-not $script:DryRun) {
    $reposDir = Join-Path $workspacePath 'repos'
    if (-not (Test-Path $reposDir)) { New-Item -ItemType Directory -Path $reposDir -Force | Out-Null }
    $linkPath = Join-Path $reposDir $aliasName
    New-RepoLink -LinkPath $linkPath -Target $repoPath
  }

  # Managed block
  $verifyCmdListStr = ''
  if ($det.VerifyCmds) {
    foreach ($vc in ($det.VerifyCmds -split ',')) {
      $verifyCmdListStr += "- ``$($vc.Trim())```n"
    }
  }

  $block = Get-Template (Join-Path $TmplDir 'managed-block.md.tmpl')
  $block = $block -replace '\{\{workspace_name\}\}', $workspaceName
  $block = $block -replace '\{\{workspace_path\}\}', $workspacePath
  $block = $block -replace '\{\{alias\}\}', $aliasName
  $block = $block -replace '\{\{verify_cmds_list\}\}', $verifyCmdListStr

  foreach ($tf in @('AGENTS.md', 'CLAUDE.md')) {
    Sync-ManagedBlock (Join-Path $repoPath $tf) $block
  }

  # Regenerate all workspace docs
  Invoke-RegenerateWorkspaceDocs -WorkspacePath $workspacePath

  Write-Ok "Repo '$aliasName' added to workspace."
}

# --- remove ---

function Invoke-Remove {
  param([string[]]$Args_)

  $workspacePath = Resolve-Path $Args_[0] | Select-Object -ExpandProperty Path
  $aliasName = $Args_[1]

  if (-not (Test-Path (Join-Path $workspacePath 'AGENTS.md'))) {
    throw "Not a valid workspace: $workspacePath"
  }

  # Load saved config
  Import-WorkspaceConfig -WorkspacePath $workspacePath

  if (-not (Confirm-Action "Remove '$aliasName' from workspace?")) { Write-Info 'Aborted.'; return }

  # Remove specialist agents
  foreach ($dir in @('.agents', (Join-Path '.claude' 'agents'))) {
    $agentFile = Join-PathSegments $workspacePath, $dir, "repo-$aliasName.md"
    if (Test-Path $agentFile) {
      if ($script:DryRun) { Write-Info "[dry-run] Would remove: $agentFile" }
      else { Remove-Item $agentFile -Force; Write-Verbose_ "Removed: $agentFile" }
    }
  }

  # Remove symlink
  $linkPath = Join-PathSegments $workspacePath, 'repos', $aliasName
  if (Test-Path $linkPath) {
    $repoPath = @((Get-Item $linkPath).Target)[0]
    if ($script:DryRun) { Write-Info "[dry-run] Would remove symlink: $linkPath" }
    else {
      Remove-Item $linkPath -Force
      Write-Verbose_ "Removed symlink: $aliasName"
    }

    # Clean managed block from repo
    if ($repoPath -and (Test-Path $repoPath)) {
      $startMarker = '<!-- MULTIREPO_SPACE_MANAGED:START -->'
      $endMarker = '<!-- MULTIREPO_SPACE_MANAGED:END -->'
      foreach ($tf in @('AGENTS.md', 'CLAUDE.md')) {
        $repoFile = Join-Path $repoPath $tf
        if ((Test-Path $repoFile) -and -not $script:DryRun) {
          $content = Get-Content -Path $repoFile -Raw
          $pattern = "(?s)`n?$([regex]::Escape($startMarker)).*?$([regex]::Escape($endMarker))`n?"
          $content = $content -replace $pattern, ''
          Set-Content -Path $repoFile -Value $content -NoNewline
          Write-Verbose_ "Cleaned managed block: $repoFile"
        }
      }
    }
  }

  # Regenerate all workspace docs
  Invoke-RegenerateWorkspaceDocs -WorkspacePath $workspacePath

  Write-Ok "Repo '$aliasName' removed from workspace."
}

# --- status ---

function Invoke-Status {
  param([string[]]$Args_)

  $workspacePath = Resolve-Path $Args_[0] | Select-Object -ExpandProperty Path

  if (-not (Test-Path (Join-Path $workspacePath 'AGENTS.md'))) {
    throw "Not a valid workspace: $workspacePath"
  }

  # Load saved config
  Import-WorkspaceConfig -WorkspacePath $workspacePath

  $workspaceName = Split-Path -Leaf $workspacePath
  Write-Host ''
  Write-Info "Workspace: $workspaceName ($workspacePath)"
  Write-Host ''

  $total = 0; $healthy = 0; $broken = 0
  $reposDir = Join-Path $workspacePath 'repos'
  if (Test-Path $reposDir) {
    '{0,-25} {1,-10} {2}' -f 'Alias', 'Status', 'Target' | Write-Host
    '{0,-25} {1,-10} {2}' -f '-------------------------', '----------', '--------------------' | Write-Host
    foreach ($item in Get-ChildItem -Path $reposDir) {
      if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
      $total++
      $alias = $item.Name
      $target = @($item.Target)[0]
      if (Test-Path $target -PathType Container) {
        '{0,-25} {1,-10} {2}' -f $alias, 'OK', $target | Write-Host -ForegroundColor Green
        $healthy++
      }
      else {
        '{0,-25} {1,-10} {2}' -f $alias, 'BROKEN', $target | Write-Host -ForegroundColor Red
        $broken++
      }
    }
  }

  Write-Host ''
  $agentsCount = (Get-ChildItem -Path (Join-Path $workspacePath '.agents') -Filter 'repo-*.md' -ErrorAction SilentlyContinue).Count
  $claudeAgentsCount = (Get-ChildItem -Path (Join-PathSegments $workspacePath, '.claude', 'agents') -Filter 'repo-*.md' -ErrorAction SilentlyContinue).Count
  $parityStatus = if ($agentsCount -eq $claudeAgentsCount) { 'OK' } else { 'MISMATCH' }

  Write-Info "Repos: $total (healthy: $healthy, broken: $broken)"
  Write-Info "Agents: .agents/=$agentsCount, .claude/agents/=$claudeAgentsCount ($parityStatus)"
  $settingsExists = if (Test-Path (Join-PathSegments $workspacePath, '.claude', 'settings.json')) { 'EXISTS' } else { 'MISSING' }
  $agentsMdExists = if (Test-Path (Join-Path $workspacePath 'AGENTS.md')) { 'EXISTS' } else { 'MISSING' }
  $claudeMdExists = if (Test-Path (Join-Path $workspacePath 'CLAUDE.md')) { 'EXISTS' } else { 'MISSING' }
  Write-Info "Config: .claude/settings.json $settingsExists"
  Write-Info "AGENTS.md $agentsMdExists"
  Write-Info "CLAUDE.md $claudeMdExists"

  # Config persistence
  $configFile = Join-PathSegments $workspacePath, '.claude', '.multirepo-space.conf'
  if (Test-Path $configFile) {
    Write-Info "Workspace config: $configFile EXISTS"
    Write-Info "  MODEL_COORDINATOR=$($script:ModelCoordinator)"
    Write-Info "  MODEL_SPECIALIST=$($script:ModelSpecialist)"
  } else {
    Write-Info 'Workspace config: MISSING (using defaults)'
  }


}

# --- Usage ---

function Show-Usage {
  @"
multirepo-space v$ScriptVersion - Multi-repo workspace manager for AI coding agents

Usage:
  multirepo-space.ps1 <command> [options] <args>

Commands:
  setup   <workspace_path> <repo1> [repo2...]   Scaffold a new workspace
  add     <workspace_path> <repo_path>           Add a repo to existing workspace
  remove  <workspace_path> <alias>               Detach a repo from workspace
  status  <workspace_path>                       Check workspace health

Options:
  -Yes                          Non-interactive mode (skip confirmations)
  -DryRun                       Preview changes without writing
  -Verbose_                     Detailed output
  -Help                         Show this help
  -Version_                     Show version

  Model flags (pass as remaining args after command):
    --model-coordinator=MODEL   Model for coordinator agent (default: opus)
    --model-specialist=MODEL    Model for specialist agents (default: sonnet)

Examples:
  .\multirepo-space.ps1 setup ~\workspace ~\repos\frontend ~\repos\backend
  .\multirepo-space.ps1 setup ~\workspace ~\repos\fe ~\repos\be --model-coordinator=sonnet
  .\multirepo-space.ps1 add ~\workspace ~\repos\shared-lib
  .\multirepo-space.ps1 remove ~\workspace shared-lib
  .\multirepo-space.ps1 status ~\workspace
"@ | Write-Host
}

# --- Parse extra flags from RemainingArgs ---

function Split-ExtraFlags {
  param([string[]]$ArgsIn)
  $cleanArgs = @()
  foreach ($arg in $ArgsIn) {
    if ($arg -match '^--model-coordinator=(.+)$') { $script:ModelCoordinator = $Matches[1] }
    elseif ($arg -match '^--model-specialist=(.+)$') { $script:ModelSpecialist = $Matches[1] }
    else { $cleanArgs += $arg }
  }
  return $cleanArgs
}

# --- Main ---

if ($Help) { Show-Usage; return }
if ($Version_) { Write-Host "multirepo-space v$ScriptVersion"; return }

# Parse extra flags from remaining args
if ($RemainingArgs) {
  $RemainingArgs = @(Split-ExtraFlags $RemainingArgs)
}

switch ($Command) {
  'setup' {
    if ($RemainingArgs.Count -lt 2) { throw 'Usage: multirepo-space.ps1 setup <workspace_path> <repo1> [repo2...]' }
    Invoke-Setup -Args_ $RemainingArgs
  }
  'add' {
    if ($RemainingArgs.Count -ne 2) { throw 'Usage: multirepo-space.ps1 add <workspace_path> <repo_path>' }
    Invoke-Add -Args_ $RemainingArgs
  }
  'remove' {
    if ($RemainingArgs.Count -ne 2) { throw 'Usage: multirepo-space.ps1 remove <workspace_path> <alias>' }
    Invoke-Remove -Args_ $RemainingArgs
  }
  'status' {
    if ($RemainingArgs.Count -ne 1) { throw 'Usage: multirepo-space.ps1 status <workspace_path>' }
    Invoke-Status -Args_ $RemainingArgs
  }
  default { Show-Usage }
}
