<#
.SYNOPSIS
  查询游戏代理程序集里的类型与成员签名。

.DESCRIPTION
  包一层 tools\Inspect\Inspect.exe，自动设置 PS_GAME_ASM_DIR 与游戏目录探测。
  首次使用会自动构建工具。

  为什么需要这个工具：游戏类型在 `Il2Cpp` 命名空间下、且很多 API 与官方文档
  不一致，**写代码前必须先查真实签名**。详见 docs/IL2CPP-Mod-实战笔记.md 第 4 节。

.EXAMPLE
  .\tools\inspect.ps1 find 'Inventory|Sort|Window'
  按类型名正则搜索，打印全部成员。

.EXAMPLE
  .\tools\inspect.ps1 show PixelWindow 'focus|title'
  看某个类型的成员（第二个参数是成员名正则）。

.EXAMPLE
  .\tools\inspect.ps1 base TreeNodeRender
  看继承链（判断能不能用 GameObject / GetComponent 那套）。

.EXAMPLE
  .\tools\inspect.ps1 -Asm UnityEngine.CoreModule find '^Input$'
  看 Unity 侧的类型（默认只看 Assembly-CSharp）。
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('find', 'show', 'base')]
    [string] $Command,

    [Parameter(Position = 1)]
    [string] $Arg1,

    [Parameter(Position = 2)]
    [string] $Arg2,

    [string] $Asm,
    [string] $GameDir
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot      # tools -> 库根

# ── 定位游戏目录 ───────────────────────────────────────────────
function Resolve-Game {
    param([string] $Explicit)
    if ($Explicit) { return (Resolve-Path $Explicit).Path }
    if ($env:GAME_DIR -and (Test-Path $env:GAME_DIR)) { return (Resolve-Path $env:GAME_DIR).Path }
    foreach ($c in @(
        'F:\SteamLibrary\steamapps\common\Probably Stolen',
        'C:\Program Files (x86)\Steam\steamapps\common\Probably Stolen',
        'F:\SteamLibrary\steamapps\common\Probably Stolen Demo',
        'C:\Program Files (x86)\Steam\steamapps\common\Probably Stolen Demo',
        'D:\SteamLibrary\steamapps\common\Probably Stolen Demo',
        'E:\SteamLibrary\steamapps\common\Probably Stolen Demo')) {
        if (Test-Path (Join-Path $c 'Probably Stolen.exe')) { return (Resolve-Path $c).Path }
    }
    return $null
}

$game = Resolve-Game -Explicit $GameDir
if (-not $game) {
    throw "没找到游戏目录。用 -GameDir '<路径>' 或设环境变量 GAME_DIR 指定。"
}

$asmDir = Join-Path $game 'MelonLoader\Il2CppAssemblies'
if (-not (Test-Path (Join-Path $asmDir 'Assembly-CSharp.dll'))) {
    throw "找不到代理程序集：$asmDir\Assembly-CSharp.dll`n请先装 MelonLoader 并**成功启动一次游戏**（首次会联网生成）。"
}

# ── 确保工具已构建 ─────────────────────────────────────────────
$proj = Join-Path $root 'tools\Inspect\Inspect.csproj'
$exe = Join-Path $root 'tools\Inspect\bin\Release\net6.0\Inspect.dll'
if (-not (Test-Path $exe)) {
    Write-Host "[inspect] 首次使用，正在构建工具..." -ForegroundColor Cyan
    & dotnet build $proj -c Release -v quiet --nologo
    if ($LASTEXITCODE -ne 0) { throw "工具构建失败" }
}

# ── 转发命令 ───────────────────────────────────────────────────
$env:PS_GAME_ASM_DIR = $asmDir

$args = @()
if ($Asm) { $args += @('-asm', $Asm) }
if ($Command) { $args += $Command }
if ($Arg1) { $args += $Arg1 }
if ($Arg2) { $args += $Arg2 }

if ($args.Count -eq 0) {
    Write-Host "用法示例：" -ForegroundColor Cyan
    Write-Host "  .\tools\inspect.ps1 find 'Inventory|Sort'"
    Write-Host "  .\tools\inspect.ps1 show PixelWindow 'focus|title'"
    Write-Host "  .\tools\inspect.ps1 base TreeNodeRender"
    Write-Host "  .\tools\inspect.ps1 -Asm UnityEngine.CoreModule find '^Input$'"
    exit 0
}

& dotnet $exe @args
