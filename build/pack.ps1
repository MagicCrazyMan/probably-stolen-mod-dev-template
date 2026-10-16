<#
.SYNOPSIS
  打发布 zip：给其他人直接复制使用。

.DESCRIPTION
  从 workspace\src\<模组>\ 读代码，构建后组装发布包：

      <模组名>-v<版本>.zip
      ├── README.txt                      ← 使用者说明（人工维护）
      └── Mods\<模组名>.dll               ← 模组本体

  压缩包结构按「解压到游戏根目录即用」组织，与 MelonLoader 官方安装说明一致。

  版本号从源码的 MelonInfo 属性解析，并**校验它确实写进了 DLL** ——
  避免出现「zip 名和实际版本对不上」这种低级错误。

  使用者说明从 workspace\src\<模组>\README.txt 读取；不存在则跳过并提示。

.EXAMPLE
  .\pack.ps1 -Mod QuickSort
  打包 QuickSort。

.EXAMPLE
  .\pack.ps1 -Mod MyMod -Readme 'C:\path\to\README.txt'
  指定自定义的使用者说明文件。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Mod,
    [ValidateSet('Debug', 'Release')]
    [string] $Configuration = 'Release',
    [string] $Readme,
    [string] $GameDir
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot      # build -> 模板库根
$projDir = Join-Path $repoRoot "workspace\src\$Mod"
$dist = Join-Path $repoRoot 'workspace\dist'
$pack = Join-Path $dist 'pack'

if (-not (Test-Path $projDir)) { throw "找不到模组工程：$projDir" }

# ── 1. 从源码读版本号，保证 zip 名与 DLL 内的版本一致 ──────────
$csFiles = Get-ChildItem $projDir -Filter '*.cs' -Recurse |
           Where-Object { $_.FullName -notmatch '\\obj\\|\\bin\\' }
$version = $null
foreach ($f in $csFiles) {
    $m = [regex]::Match((Get-Content $f.FullName -Raw),
                        'MelonInfo\(typeof\([^)]*\),\s*"[^"]*",\s*"([^"]+)"')
    if ($m.Success) { $version = $m.Groups[1].Value; break }
}
if (-not $version) { throw "在 $projDir 的源码里找不到 MelonInfo 版本号" }
Write-Host "[pack] 模组：$Mod   版本：$version" -ForegroundColor Cyan

# ── 2. 构建 ────────────────────────────────────────────────────
Write-Host "[pack] 构建 $Configuration..." -ForegroundColor Cyan
$buildArgs = @('build', (Join-Path $projDir "$Mod.csproj"), '-c', $Configuration, '-v', 'minimal', '--nologo')
if ($GameDir) { $buildArgs += "-p:GameDir=$GameDir" }
& dotnet @buildArgs
if ($LASTEXITCODE -ne 0) { throw "构建失败，终止打包" }

$dll = Join-Path $projDir "bin\$Configuration\net6.0\$Mod.dll"
if (-not (Test-Path $dll)) { throw "找不到产物：$dll" }

# ── 3. 校验版本号确实进了 DLL ──────────────────────────────────
$dllText = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($dll))
if ($dllText -notmatch [regex]::Escape($version)) {
    throw "DLL 里找不到版本号 $version —— 请确认 MelonInfo 的版本号与启动日志里打的一致"
}
Write-Host "[pack] 版本号已确认写入 DLL ✓" -ForegroundColor Green

# ── 4. 组装 ────────────────────────────────────────────────────
if (-not $Readme) { $Readme = Join-Path $projDir 'README.txt' }
if (Test-Path $pack) { Remove-Item $pack -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $pack 'Mods') | Out-Null
Copy-Item $dll (Join-Path $pack 'Mods') -Force

if (Test-Path $Readme) {
    Copy-Item $Readme (Join-Path $pack 'README.txt') -Force
} else {
    Write-Host "[pack] 没有使用者说明（$Readme 不存在），发布包里将只有 DLL。" -ForegroundColor Yellow
    Write-Host "[pack] 建议在 workspace\src\$Mod\README.txt 写一份安装与使用说明。" -ForegroundColor Yellow
}

Write-Host "[pack] 内容：" -ForegroundColor Cyan
Get-ChildItem $pack -Recurse -File | ForEach-Object {
    Write-Host ("  {0,-40} {1,8} bytes" -f $_.FullName.Replace($pack + '\', ''), $_.Length)
}

# ── 5. 压缩 ────────────────────────────────────────────────────
$zip = Join-Path $dist "$Mod-v$version.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $pack '*') -DestinationPath $zip -Force

$hash = (Get-FileHash $zip -Algorithm SHA256).Hash
Write-Host ""
Write-Host "[pack] 发布包：$zip" -ForegroundColor Green
Write-Host "[pack]   大小  ：$((Get-Item $zip).Length) bytes" -ForegroundColor Green
Write-Host "[pack]   SHA256：$hash" -ForegroundColor Green
Write-Host ""
Write-Host "[pack] 解压到游戏根目录即可（里面是 README.txt + Mods\）" -ForegroundColor Gray
