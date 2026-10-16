<#
.SYNOPSIS
  构建 / 部署 Probably Stolen 的 MelonLoader 模组（路线 B：IL2CPP）。

.DESCRIPTION
  自动探测游戏目录 → 编译 net6.0 类库 → 可选部署到 <游戏>\Mods\ → 可选打 zip。
  最后可顺手打印 MelonLoader 最新日志，方便确认模组是否被加载。

  游戏目录解析优先级：
    1. -GameDir 参数
    2. 环境变量 $env:GAME_DIR
    3. 自动探测常见 Steam 库路径
    4. 回落到 Directory.Build.props 里的默认值

.EXAMPLE
  .\deploy.ps1
  构建 workspace\src 下全部工程。

.EXAMPLE
  .\deploy.ps1 -Mod MyMod -Deploy -Log
  构建 MyMod、部署到游戏 Mods\、并打印 MelonLoader 最新日志。
#>
[CmdletBinding()]
param(
    [string] $Mod,
    [ValidateSet('Debug', 'Release')]
    [string] $Configuration = 'Release',
    [switch] $Deploy,
    [switch] $Package,
    [switch] $NoRestore,
    [switch] $Log,
    [string] $GameDir
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot   # build -> 模板库根
$srcDir = Join-Path $repoRoot 'workspace\src'
$distDir = Join-Path $repoRoot 'workspace\dist'

function Resolve-GameDir {
    param([string] $Explicit)
    if ($Explicit) {
        if (-not (Test-Path $Explicit)) { throw "-GameDir 指向的目录不存在：$Explicit" }
        return (Resolve-Path $Explicit).Path
    }
    if ($env:GAME_DIR) {
        if (-not (Test-Path $env:GAME_DIR)) { throw "环境变量 GAME_DIR 指向的目录不存在：$($env:GAME_DIR)" }
        return (Resolve-Path $env:GAME_DIR).Path
    }
    $candidates = @()
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root)) {
        foreach ($sub in 'SteamLibrary\steamapps\common', 'Program Files (x86)\Steam\steamapps\common', 'Steam\steamapps\common', 'Games') {
            foreach ($name in 'Probably Stolen', 'Probably Stolen Demo') {
                $candidates += (Join-Path $drive (Join-Path $sub $name))
            }
        }
    }
    # 判据：有 exe 且有 _Data
    foreach ($c in $candidates) {
        if ((Test-Path (Join-Path $c 'Probably Stolen.exe')) -and (Test-Path (Join-Path $c 'Probably Stolen_Data'))) {
            return (Resolve-Path $c).Path
        }
    }
    return $null
}

# ── 1. 定位游戏 & 体检 ─────────────────────────────────────────
$game = Resolve-GameDir -Explicit $GameDir
if ($game) {
    Write-Host "[PS] 游戏目录：$game" -ForegroundColor Cyan
    $melon = Join-Path $game 'MelonLoader'
    $interop = Join-Path $melon 'Il2CppAssemblies'
    $managed = Join-Path $game 'Probably Stolen_Data\Managed'

    if (Test-Path $managed) {
        Write-Host "[PS] 引擎：Mono（有 Managed\）→ 官方 Mod 系统路线（本仓库当前按 MelonLoader 配置）" -ForegroundColor Yellow
    } else {
        Write-Host "[PS] 引擎：IL2CPP（无 Managed\）→ 需要 MelonLoader" -ForegroundColor Green
    }
    Write-Host ("[PS] MelonLoader : {0}" -f $(if (Test-Path (Join-Path $melon 'net6\MelonLoader.dll')) { '已装 ✓' } else { '未装 ✗' })) -ForegroundColor $(if (Test-Path (Join-Path $melon 'net6\MelonLoader.dll')) { 'Green' } else { 'Red' })
    Write-Host ("[PS] 代理程序集  : {0}" -f $(if (Test-Path (Join-Path $interop 'Assembly-CSharp.dll')) { '已生成 ✓' } else { '缺失 ✗（先启动一次游戏）' })) -ForegroundColor $(if (Test-Path (Join-Path $interop 'Assembly-CSharp.dll')) { 'Green' } else { 'Red' })
    $versionDll = Join-Path $game 'version.dll'
    if (Test-Path $versionDll) {
        Write-Host ("[PS] version.dll  : {0}" -f (Get-Item $versionDll).VersionInfo.FileVersion) -ForegroundColor Green
    }
} else {
    Write-Host "[PS] ⚠️ 未探测到游戏目录，将用 Directory.Build.props 里的默认值" -ForegroundColor Yellow
}

# ── 2. 收集工程 ────────────────────────────────────────────────
$projects = if ($Mod) {
    $p = Join-Path $srcDir "$Mod\$Mod.csproj"
    if (-not (Test-Path $p)) { throw "找不到工程：$p" }
    @(Get-Item $p)
} else {
    @(Get-ChildItem $srcDir -Filter '*.csproj' -Recurse | Where-Object { $_.DirectoryName -notmatch '\\obj\\' })
}
if ($projects.Count -eq 0) { throw "在 $srcDir 下没找到任何 .csproj" }
Write-Host "[PS] 待构建：$($projects.Count) 个工程（$Configuration）" -ForegroundColor Cyan

# ── 3. 构建 ────────────────────────────────────────────────────
$msbuildArgs = @()
if ($game)   { $msbuildArgs += "-p:GameDir=$game" }
if ($Deploy) { $msbuildArgs += '-p:DeployToGame=true' }

$failed = @()
foreach ($proj in $projects) {
    Write-Host "`n── $($proj.BaseName) ─────────────────────────────" -ForegroundColor Cyan
    $dotnetArgs = @('build', $proj.FullName, '-c', $Configuration, '-v', 'minimal', '--nologo')
    if ($NoRestore) { $dotnetArgs += '--no-restore' }
    if ($msbuildArgs.Count) { $dotnetArgs += $msbuildArgs }

    & dotnet @dotnetArgs
    if ($LASTEXITCODE -ne 0) { $failed += $proj.BaseName; Write-Host "[PS] ✗ $($proj.BaseName) 失败" -ForegroundColor Red; continue }
    Write-Host "[PS] ✓ $($proj.BaseName) 成功" -ForegroundColor Green

    $produced = Get-ChildItem (Join-Path $proj.DirectoryName "bin\$Configuration\net6.0") -Filter '*.dll' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notin @('MelonLoader.dll','0Harmony.dll','Il2CppInterop.Runtime.dll','Il2CppInterop.Common.dll','Assembly-CSharp.dll','Il2Cppmscorlib.dll') -and $_.Name -notlike 'UnityEngine*' -and $_.Name -notlike 'Unity.*' }
    if ($produced) { Write-Host "[PS] 产物：$($produced[0].FullName)" -ForegroundColor Gray }

    # ── 4. 打包（可选）────────────────────────────────────────
    if ($Package -and $produced) {
        $stage = Join-Path $distDir $proj.BaseName
        if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        Copy-Item $produced[0].FullName $stage -Force
        foreach ($extra in 'README.txt','LICENSE.txt') {
            $ep = Join-Path $proj.DirectoryName $extra
            if (Test-Path $ep) { Copy-Item $ep $stage -Force }
        }
        $zip = Join-Path $distDir "$($proj.BaseName)-$Configuration.zip"
        Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force
        Write-Host "[PS] 📦 发布包：$zip" -ForegroundColor Green
    }
}

# ── 5. MelonLoader 日志（可选）─────────────────────────────────
if ($Log -and $game) {
    $logs = Get-ChildItem (Join-Path $game 'MelonLoader\Logs') -Filter '*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if ($logs) {
        Write-Host "`n──── MelonLoader 最新日志：$($logs[0].Name) ────" -ForegroundColor Cyan
        Select-String -Path $logs[0].FullName -Pattern 'Mod|Melon Assembly|loaded\.|ERROR|Exception|\[QuickSort\]' |
            Select-Object -Last 40 | ForEach-Object { "  $($_.Line)" }
    } else {
        Write-Host "[PS] 没找到 MelonLoader 日志（游戏还没通过 MelonLoader 启动过？）" -ForegroundColor Yellow
    }
}

# ── 6. 汇总 ────────────────────────────────────────────────────
Write-Host ""
if ($failed.Count) { Write-Host "[PS] 失败：$($failed -join ', ')" -ForegroundColor Red; exit 1 }
Write-Host "[PS] 全部完成。" -ForegroundColor Green
if ($Deploy -and $game) {
    Write-Host "[PS] 部署位置：$(Join-Path $game 'Mods')" -ForegroundColor Gray
    Write-Host "[PS] 提醒：必须从 Steam 启动游戏；改设置要改 UserData\MelonPreferences.cfg 后重启。" -ForegroundColor Gray
}
