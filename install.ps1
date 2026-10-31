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

if ($Rollback) {
    $bak = Get-ChildItem "$config.bak-*" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $bak) { throw '找不到 config.toml 备份，无法回滚。' }
    Copy-Item $bak.FullName $config -Force
    Write-Host "已还原：$($bak.Name)" -ForegroundColor Green
    Write-Host '新开的 Codex 会话会恢复原版行为。'
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
$bakPath = "$config.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
Copy-Item $config $bakPath -Force
Write-Host "      -> $(Split-Path -Leaf $bakPath)"

Write-Host "[2/4] 复制提示词到 $targetDir" -ForegroundColor Cyan
if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir | Out-Null
}
Copy-Item (Join-Path $sourceDir 'claude-code-system.md') $promptFile -Force
Copy-Item (Join-Path $sourceDir 'refresh-catalog.ps1') $refreshScript -Force
Write-Host '      -> claude-code-system.md / refresh-catalog.ps1'

Write-Host '[3/4] 写入 config.toml' -ForegroundColor Cyan
$text = [IO.File]::ReadAllText($config)
$eol = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
$body = foreach ($line in ($text -split "`r?`n")) {
    if ($line -match '^(model_catalog_json|model_instructions_file|project_doc_fallback_filenames)\s*=') { continue }
    $line
}
$block = @(
    'model_catalog_json = "' + ($catalogFile -replace '\\', '/') + '"'
    'model_instructions_file = "' + ($promptFile -replace '\\', '/') + '"'
    'project_doc_fallback_filenames = ["CLAUDE.md"]'
    ''
) -join $eol
[IO.File]::WriteAllText($config, $block + $eol + ($body -join $eol), (New-Object Text.UTF8Encoding($false)))
Write-Host '      -> 三行配置已写入（原有同名行已替换）'

Write-Host '[4/4] 生成模型目录，大约需要十几秒' -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $refreshScript
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $catalogFile)) {
    Copy-Item $bakPath $config -Force
    throw '模型目录生成失败，已自动还原 config.toml。可以稍后手动运行 refresh-catalog.ps1 重试。'
}
Write-Host '      -> codex-catalog.json'

Write-Host ''
Write-Host '安装完成' -ForegroundColor Green
Write-Host "  提示词   $promptFile"
Write-Host "  模型目录 $catalogFile"
Write-Host "  配置备份 $(Split-Path -Leaf $bakPath)"
Write-Host ''
Write-Host '新开一个 Codex 会话即可生效。要撤销就双击 uninstall.cmd。'
