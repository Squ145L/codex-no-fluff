$ErrorActionPreference = 'Stop'

# Every path is derived from the script's own location and the current user's
# profile, so the repo works from any checkout path and any Windows account.
$promptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$codexHome = Join-Path $env:USERPROFILE '.codex'
$config    = Join-Path $codexHome 'config.toml'
$catalog   = Join-Path $promptDir 'codex-catalog.json'
$tmp       = Join-Path $env:TEMP 'codex-catalog-refresh.json'
$backup    = "$config.refresh-backup"

if (-not (Test-Path $config)) { throw "Codex config not found: $config" }

# codex.exe moves to a new versioned bin folder on every update, so resolve it
# instead of hardcoding a build hash.
$codex = (Get-Command codex.exe -ErrorAction SilentlyContinue).Source
if (-not $codex) {
    $binDir = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
    $codex = Get-ChildItem $binDir -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object { Join-Path $_.FullName 'codex.exe' } |
        Where-Object { Test-Path $_ } |
        Select-Object -First 1
}
if (-not $codex) { throw 'codex.exe not found. Add it to PATH or install the Codex app.' }

Copy-Item $config $backup -Force
try {
    # Temporarily disable the catalog override so `debug models` dumps the default catalog.
    $text = [IO.File]::ReadAllText($config)
    $text = $text -replace '(?m)^model_catalog_json\s*=.*$', '# TEMP_DISABLED_FOR_REFRESH'
    [IO.File]::WriteAllText($config, $text, (New-Object Text.UTF8Encoding($false)))

    & $codex debug models | Set-Content -Path $tmp -Encoding utf8
    $j = [IO.File]::ReadAllText($tmp) | ConvertFrom-Json

    $count = 0
    foreach ($m in $j.models) {
        $m.base_instructions = $null
        if ($m.model_messages) {
            $m.model_messages.instructions_template = 'OVERRIDDEN_BY_MODEL_INSTRUCTIONS_FILE'
        }
        $count++
    }

    $out = $j | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($catalog, $out, (New-Object Text.UTF8Encoding($false)))
    "Refreshed $count models -> $catalog"
}
finally {
    Copy-Item $backup $config -Force
    Remove-Item $backup -Force -ErrorAction SilentlyContinue
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
