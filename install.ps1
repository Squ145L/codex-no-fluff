[CmdletBinding()]
param(
    [switch]$Rollback
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$sourceDir     = Split-Path -Parent $MyInvocation.MyCommand.Path
$codexHome     = Join-Path $env:USERPROFILE '.codex'
$config        = Join-Path $codexHome 'config.toml'
$targetDir     = Join-Path $codexHome 'prompts'
$promptFile    = Join-Path $targetDir 'claude-code-system.md'
$catalogFile   = Join-Path $targetDir 'codex-catalog.json'
$refreshScript = Join-Path $targetDir 'refresh-catalog.ps1'
$marker        = Join-Path $targetDir '.install-backup'

function Copy-WithBackup {
    param([string]$Source, [string]$Dest)
    if ((Test-Path $Dest) -and ((Get-FileHash $Source).Hash -ne (Get-FileHash $Dest).Hash)) {
        $bak = "$Dest.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
        Copy-Item $Dest $bak -Force
        Write-Host "      -> 已有同名文件，原文件备份为 $(Split-Path -Leaf $bak)"
    }
    Copy-Item $Source $Dest -Force
}

if ($Rollback) {
    if (-not (Test-Path $marker)) {
        throw "没有安装记录 $marker 。本工具不会猜测该还原哪个备份，请手动处理 config.toml。"
    }
    $original = ([IO.File]::ReadAllText($marker)).Trim()
    if (-not $original -or -not (Test-Path $original)) {
        throw "安装记录指向的备份不存在：$original"
    }
    Copy-Item $original $config -Force
    Remove-Item $marker -Force
    Write-Host "已还原：$(Split-Path -Leaf $original)" -ForegroundColor Green
    Write-Host '新开的 Codex 会话会恢复原版行为。'
    Write-Host "$targetDir 下复制过去的提示词文件没有删除，需要的话自行清理。"
    return
}

if (-not (Test-Path $codexHome)) {
    throw "没找到 $codexHome 。请先安装 Codex 并启动一次，再运行安装。"
}
if (-not (Test-Path $config)) {
    throw "没找到 $config 。请先启动一次 Codex 生成配置文件。"
}
foreach ($f in @('claude-code-system.md', 'refresh-catalog.ps1')) {
    if (-not (Test-Path (Join-Path $sourceDir $f))) {
        throw "缺少文件：$f （请从仓库目录运行 install.cmd，不要单独拷贝脚本）"
    }
}

Write-Host '[1/4] 备份 config.toml' -ForegroundColor Cyan
$markerCreated = $false
if (Test-Path $marker) {
    # 已经装过：回滚点始终是最初那一次安装前的状态，不跟着滚动。
    $originalBackup = ([IO.File]::ReadAllText($marker)).Trim()
    if (-not $originalBackup -or -not (Test-Path $originalBackup)) {
        throw "安装记录指向的备份不存在：$originalBackup"
    }
    Write-Host "      已经安装过，沿用最初的备份：$(Split-Path -Leaf $originalBackup)"
}
else {
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir | Out-Null
    }
    $originalBackup = "$config.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
    Copy-Item $config $originalBackup -Force
    [IO.File]::WriteAllText($marker, $originalBackup, (New-Object Text.UTF8Encoding($false)))
    $markerCreated = $true
    Write-Host "      -> $(Split-Path -Leaf $originalBackup)"
}

Write-Host "[2/4] 复制提示词到 $targetDir" -ForegroundColor Cyan
Copy-WithBackup (Join-Path $sourceDir 'claude-code-system.md') $promptFile
Copy-WithBackup (Join-Path $sourceDir 'refresh-catalog.ps1') $refreshScript

Write-Host '[3/4] 写入 config.toml' -ForegroundColor Cyan
$text = [IO.File]::ReadAllText($config)
$eol = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
# 只清理顶层同名键；进入第一个 [section] 之后不再匹配，避免误删 [projects.*] 里的键。
$inSection = $false
$body = foreach ($line in ($text -split "`r?`n")) {
    if (-not $inSection -and $line -match '^\s*\[') { $inSection = $true }
    if (-not $inSection -and $line -match '^(model_catalog_json|model_instructions_file|project_doc_fallback_filenames)\s*=') { continue }
    $line
}
$block = @(
    'model_catalog_json = "' + ($catalogFile -replace '\\', '/') + '"'
    'model_instructions_file = "' + ($promptFile -replace '\\', '/') + '"'
    'project_doc_fallback_filenames = ["CLAUDE.md"]'
    ''
) -join $eol
[IO.File]::WriteAllText($config, $block + $eol + ($body -join $eol), (New-Object Text.UTF8Encoding($false)))
Write-Host '      -> 三行配置已写入（顶层同名键已替换）'

Write-Host '[4/4] 生成模型目录，大约需要十几秒' -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $refreshScript
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $catalogFile)) {
    Copy-Item $originalBackup $config -Force
    if ($markerCreated) { Remove-Item $marker -Force -ErrorAction SilentlyContinue }
    throw '模型目录生成失败，已自动还原 config.toml。可以稍后手动运行 refresh-catalog.ps1 重试。'
}
Write-Host '      -> codex-catalog.json'

Write-Host ''
Write-Host '安装完成' -ForegroundColor Green
Write-Host "  提示词   $promptFile"
Write-Host "  模型目录 $catalogFile"
Write-Host "  配置备份 $(Split-Path -Leaf $originalBackup)"
Write-Host ''
Write-Host '新开一个 Codex 会话即可生效。要撤销就双击 uninstall.cmd。'
