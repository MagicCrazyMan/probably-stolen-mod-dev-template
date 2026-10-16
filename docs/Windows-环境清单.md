# Windows 编译打包环境清单

> ⚠️ **2026-10-17 更新**：本文写于调研阶段（2026-10-16），是在**尚未装任何东西**之前
> 按理想情况写的。实测后有几处不符，动手前请先看
> **[`IL2CPP-Mod-实战笔记.md`](IL2CPP-Mod-实战笔记.md) 第 1 节**。
>
> 主要差异：
> 1. **VS 2022 编译不了 C#** —— 本机 VS 2022 Community 只装了 C++ 工作负载，
>    没有 Roslyn `csc.exe`，也没有 `Microsoft.DotNet.MSBuildSdkResolver`。
>    命令行 `dotnet` SDK 才是唯一途径。
> 2. **目标框架取决于路线** —— 本文说的 `netstandard2.1` 是**正式版 / Mono（路线 A）**的要求；
>    当前实际走的 MelonLoader（路线 B）必须用 **`net6.0`**。
> 3. **不需要 `Probably Stolen_Data\Managed\`** —— IL2CPP 构建没有这个目录，
>    引用改从 `MelonLoader\Il2CppAssemblies\*.dll` + `MelonLoader\net6\*.dll` 取。
> 4. **本机游戏装在 `F:\SteamLibrary`**，不是 `Program Files (x86)`，所以「写保护」那个坑不存在。
>
> 仍然有效的部分：.NET SDK 10 的建议、`<Private>false</Private>` 的必要性、
> Steam 库 / AppID 信息、创意工坊发布流程。

> 用途：在 Windows 上完成《深空当铺：可能是偷的》(Probably Stolen) Mod 的**开发、编译与打包**。
> 编写日期：2026-10-16

---

## 结论：装 2 个软件就能开工

| 类别 | 项目 | 状态 |
|---|---|---|
| ① 必须装 | **.NET SDK 10** | 约 300 MB |
| ② 必须装 | **Steam + 游戏本体** | 提供编译所需的引用 DLL + 运行环境 |
| ③ 建议装 | 编辑器（VS Code / VS 2022 / Rider） | 可选，纯命令行也能干活 |
| ④ 打包工具 | PowerShell 内置 `Compress-Archive` | ✅ **系统自带，无需安装** |
| ⑤ 仅发布工坊 | steamcmd | 按需，**winget 上没有，需手动下载** |

### 🎉 相比 Linux 最大的好消息

**Linux 上那个"必须从别的机器拷贝游戏程序集"的硬阻塞，在 Windows 上自动消失了。**

因为 Windows 上你会直接装游戏，`csproj` 可以直接指向游戏安装目录里的 DLL，**不需要拷贝、不需要维护 `refs/` 目录、也不会有版权分发风险**。

---

## 1.【必须】.NET SDK 10

### 为什么是 10

| 版本 | 支持状态 | 结论 |
|---|---|---|
| .NET 6 | ❌ 2024-11-12 已 EOL | 官方指南虽写"6.0 或更高"，但**别用 6** |
| .NET 8 | ⚠️ 2026-11-10 EOL | 不推荐（不到一个月就到期） |
| **.NET 10** | ✅ **LTS，支持到 2028-11-14** | **选这个** |

> SDK 版本只影响**编译**。产物是 `netstandard2.1` 程序集，游戏侧的 Mono 运行时能正常加载，与 SDK 版本无关。

### 安装方式（任选一种）

**方式 1：winget（推荐，最省事）**

```powershell
winget install Microsoft.DotNet.SDK.10
```

**方式 2：官网安装包**

下载 https://dotnet.microsoft.com/download/dotnet/10.0 → **SDK x64** 安装包（不是 Runtime）

**方式 3：Visual Studio 2022 安装器**

装 VS 时勾选 **".NET 桌面开发"** 工作负载，会一并带上 SDK。

### 验证

```powershell
dotnet --version        # 期望 10.x.x
dotnet --list-sdks      # 期望出现 10.0.x
```

> 💡 若命令找不到，关掉终端重开（PATH 需要刷新）。

---

## 2.【必须】Steam + 游戏本体

| 项 | 内容 |
|---|---|
| 正式版 | AppID **4348910**，2026-10-28 上市 |
| Demo | AppID **4349200**，已可玩 |
| 默认安装路径 | `C:\Program Files (x86)\Steam\steamapps\common\Probably Stolen\` |

### 装好后第一件事：确认引擎类型

**这决定你走哪条技术路线**，务必先做：

```powershell
# 在游戏目录下执行（把路径换成你的实际路径）
$game = "C:\Program Files (x86)\Steam\steamapps\common\Probably Stolen"

# 路线 A 标志：存在 Managed 目录 → Unity Mono → 官方 Mod 系统
Test-Path "$game\Probably Stolen_Data\Managed\Assembly-CSharp.dll"

# 路线 B 标志：存在 GameAssembly.dll → Unity IL2CPP → 需要 MelonLoader/BepInEx
Test-Path "$game\GameAssembly.dll"

# 看有没有官方 Mod 系统留下的目录
Get-ChildItem $game -Directory | Where-Object Name -in 'Mods','Modding','UserData'
```

- 有 `Managed\` → **路线 A**，按本文档继续，编译无障碍
- 有 `GameAssembly.dll` → **路线 B**，见第 7 节

---

## 3.【建议】编辑器

| 方案 | 安装 | 说明 |
|---|---|---|
| **VS Code**（轻量推荐） | `winget install Microsoft.VisualStudioCode`<br>再装扩展 **C# Dev Kit** | 启动快，够用 |
| **Visual Studio 2022 Community** | `winget install Microsoft.VisualStudio.2022.Community`<br>勾选 **".NET 桌面开发"** | 调试体验最好，体积大（数 GB） |
| **JetBrains Rider** | https://www.jetbrains.com/rider/ | C# 体验最佳，**内置 ILSpy 反编译器**（读游戏代码很方便） |

> 反编译看游戏代码是**官方默许**的（研究、找补丁目标），但**禁止再分发**游戏代码或资源。

---

## 4. ⚠️ Windows 特有的坑（重点看）

### 坑 1：`C:\Program Files (x86)` 受写保护

官方指南建议把源码放在 `Modding\` **游戏目录内**。但 Windows 上 `C:\Program Files (x86)` 默认**普通用户不可写**，会导致：

- 无法在里面创建 `Modding\` 文件夹
- `dotnet build` 往 `bin\` / `obj\` 写入时失败或需要管理员权限
- VS Code / VS 打开工程时报权限错误

**推荐做法：工程放在用户目录，用绝对路径引用游戏 DLL。**

```
C:\Users\<你>\source\probably-stolen-mods\      ← 工程放这里（可自由读写）
├── HelloMod\
│   ├── HelloMod.csproj
│   ├── HelloMod.cs
│   └── manifest.xml
└── build.ps1
```

> 如果坚持要用官方指南的相对路径写法，先给游戏目录提权：
> `icacls "C:\Program Files (x86)\Steam\steamapps\common\Probably Stolen" /grant "%USERNAME%:(OI)(CI)M" /T`
> **但更推荐上面的绝对路径方案**，别动 Steam 目录权限（Steam 校验/更新可能重置）。

### 坑 2：路径含空格

游戏目录名 `Probably Stolen` 带空格。影响：

- **csproj 的 `HintPath` 里没问题**，XML 会正确处理
- **命令行/脚本里必须加引号**：`cd "C:\...\Probably Stolen"`
- PowerShell 变量赋值：`$game = "C:\...\Probably Stolen"`（引号别漏）

### 坑 3：Windows Defender 可能误报

编译出的 DLL 会被游戏加载（相当于代码注入），可能被实时保护拦截或隔离。

**若遇到**：把工程目录和游戏目录加入排除项
`设置 → 隐私和安全性 → Windows 安全中心 → 病毒和威胁防护 → 排除项`

### 坑 4：反斜杠

Windows 上 `csproj` 用反斜杠 `\` 是**原生正确**的（官方指南就是这么写的），不需要像 Linux 那样改成 `/`。

### 坑 5：`<Private>false</Private>` 不能省

所有引用游戏的 DLL 都必须加 `<Private>false</Private>`。否则这些 DLL 会被复制进输出目录，可能被 Mod 扫描器判定为"冒用游戏程序集"而**直接拒绝加载**。

---

## 5. 工程配置（Windows 版）

### 创建

```powershell
cd "$HOME\source\probably-stolen-mods"
dotnet new classlib -n HelloMod --framework netstandard2.1
cd HelloMod
```

### `HelloMod.csproj`

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>netstandard2.1</TargetFramework>
    <LangVersion>latest</LangVersion>
    <AssemblyName>HelloMod</AssemblyName>
    <RootNamespace>HelloMod</RootNamespace>
  </PropertyGroup>

  <ItemGroup>
    <!-- 改成你的实际游戏路径；反斜杠在 Windows 上是正确的 -->
    <Reference Include="Assembly-CSharp">
      <HintPath>C:\Program Files (x86)\Steam\steamapps\common\Probably Stolen\Probably Stolen_Data\Managed\Assembly-CSharp.dll</HintPath>
      <Private>false</Private>
    </Reference>
    <Reference Include="UnityEngine">
      <HintPath>C:\Program Files (x86)\Steam\steamapps\common\Probably Stolen\Probably Stolen_Data\Managed\UnityEngine.dll</HintPath>
      <Private>false</Private>
    </Reference>
    <Reference Include="UnityEngine.CoreModule">
      <HintPath>C:\Program Files (x86)\Steam\steamapps\common\Probably Stolen\Probably Stolen_Data\Managed\UnityEngine.CoreModule.dll</HintPath>
      <Private>false</Private>
    </Reference>
    <Reference Include="0Harmony">
      <HintPath>C:\Program Files (x86)\Steam\steamapps\common\Probably Stolen\Probably Stolen_Data\Managed\0Harmony.dll</HintPath>
      <Private>false</Private>
    </Reference>
  </ItemGroup>

</Project>
```

> 💡 **更好维护的写法**：用一个 MSBuild 属性集中管理游戏路径，避免每加一个引用就复制一遍长路径。
>
> ```xml
> <PropertyGroup>
>   <GameDir>C:\Program Files (x86)\Steam\steamapps\common\Probably Stolen</GameDir>
>   <ManagedDir>$(GameDir)\Probably Stolen_Data\Managed</ManagedDir>
> </PropertyGroup>
> <ItemGroup>
>   <Reference Include="Assembly-CSharp"><HintPath>$(ManagedDir)\Assembly-CSharp.dll</HintPath><Private>false</Private></Reference>
>   <Reference Include="UnityEngine"><HintPath>$(ManagedDir)\UnityEngine.dll</HintPath><Private>false</Private></Reference>
>   <Reference Include="UnityEngine.CoreModule"><HintPath>$(ManagedDir)\UnityEngine.CoreModule.dll</HintPath><Private>false</Private></Reference>
>   <Reference Include="0Harmony"><HintPath>$(ManagedDir)\0Harmony.dll</HintPath><Private>false</Private></Reference>
> </ItemGroup>
> ```
> 换机器 / 换路径时只改 `GameDir` 一行。想更灵活可以放到 `Directory.Build.props` 或环境变量里。

### 代码与 manifest.xml

完整可抄的最小示例见 [`从未开始到第一个模组.md`](从未开始到第一个模组.md) 第 5 节。

⚠️ 两个最容易忘的点：
- `manifest.xml` **必须**和 DLL 放在一起，否则游戏直接跳过整个文件夹
- 清单里的 `<ID>` 才是 API 里用的 `modId`，**不是文件夹名**

---

## 6. 编译与打包

### 编译

```powershell
dotnet build -c Release
# 产物：bin\Release\netstandard2.1\HelloMod.dll
```

### 部署到游戏

```powershell
$game = "C:\Program Files (x86)\Steam\steamapps\common\Probably Stolen"
$modId = "HelloMod"
$dest = "$game\Mods\$modId"

New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item "bin\Release\netstandard2.1\HelloMod.dll" $dest -Force
Copy-Item "manifest.xml" $dest -Force
```

### 打包发布（PowerShell 内置，无需装 zip 工具）

```powershell
# 组装 dist\HelloMod\ 后压缩为 zip
$name = "HelloMod"
$dist = "dist\$name"
New-Item -ItemType Directory -Force -Path $dist | Out-Null

Copy-Item "bin\Release\netstandard2.1\$name.dll" $dist -Force
Copy-Item "manifest.xml" $dist -Force
# 如有资源目录一并复制：
# Copy-Item "Textures" $dist -Recurse -Force

Compress-Archive -Path "$dist\*" -DestinationPath "dist\$name-1.0.0.zip" -Force
```

> ⚠️ 压缩包**根目录**必须直接是 `manifest.xml` 和 DLL，不要多套一层文件夹，否则玩家解压后游戏识别不到。

### 可选：一条命令完成编译+部署

在 `csproj` 里加后置事件，每次编译自动拷贝：

```xml
<Target Name="DeployToGame" AfterTargets="Build">
  <Copy SourceFiles="$(TargetPath)" DestinationFolder="$(GameDir)\Mods\HelloMod" />
  <Copy SourceFiles="manifest.xml"  DestinationFolder="$(GameDir)\Mods\HelloMod" />
</Target>
```

> 若游戏装在 `Program Files`，这会因权限失败 —— 又一个建议把游戏装到非系统盘、或用 `icacls` 提权的理由。

---

## 7. 若确认是路线 B（IL2CPP）

Windows 上做路线 B 比 Linux 容易得多，因为**游戏就在本机**：

1. 安装 [MelonLoader](https://github.com/LavaGang/MelonLoader/releases/latest)（用 `MelonLoader.Installer.exe`，自动识别 Steam 库）
2. **启动一次游戏** —— 这会在 `<游戏目录>\MelonLoader\Il2CppAssemblies\` 下自动生成代理程序集（**没有这一步无法编译**）
3. 新建 Class Library 工程，目标框架 **`.NET 6.0`**（不是 netstandard2.1）
4. 引用 `<游戏目录>\MelonLoader\MelonLoader.dll` + 上一步生成的 `Il2CppAssemblies\*.dll`
5. 写 `MelonMod` 子类，DLL 直接丢进 `<游戏目录>\Mods\`（**没有** `manifest.xml`，也没有子文件夹）

**IL2CPP 特有的坑：**
- **Transpiler 不可用**（没有 IL 可改写），只有 Prefix / Postfix / Finalizer
- 自定义 `MonoBehaviour` 需要 `[RegisterTypeInIl2Cpp]` + 接收 `IntPtr` 的构造函数

> ⚠️ 但仍建议：**正式版（10-28）发售后先确认引擎**。若正式版是 Mono + 官方 Mod 系统，路线 B 的投入大概率要重写。

---

## 8.【仅发布创意工坊才需要】steamcmd

**编译打包不需要它。** 只有上传 Mod 到 Steam 创意工坊时才装。

⚠️ **winget 上没有 steamcmd 包**（已实际查证），需手动下载：

1. 下载 https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip
2. 解压到如 `C:\steamcmd\`
3. 首次运行 `steamcmd.exe` 会自动更新自身

**上传：**

```powershell
C:\steamcmd\steamcmd.exe +login <你的Steam账号> +workshop_build_item "C:\path\to\my_mod.vdf" +quit
```

**前提：**
- Steam 账号**拥有《Probably Stolen》正式版**（创意工坊仅正式版可用，Demo 没有）
- 首次上传需在 Steam 网站接受一次创意工坊法律协议
- ⚠️ **不要把 Steam 密码或令牌写进脚本、提交到仓库**

`.vdf` 的字段含义：`appid` 填游戏 AppID，`publishedfileid` 首次填 `0`，`contentfolder` 指向模组文件夹，`previewfile` 指向预览图。

---

## 9. 安装后验证清单

```powershell
# ── 1. SDK 就位 ────────────────────────────────────
dotnet --version                 # 期望 10.x.x
dotnet --list-sdks               # 期望出现 10.0.x

# ── 2. 能编译 netstandard2.1（提前暴露 targeting pack 问题）──
$t = "$env:TEMP\nstest"
New-Item -ItemType Directory -Force -Path $t | Out-Null
Set-Location $t
dotnet new classlib -n Probe --framework netstandard2.1
Set-Location Probe
dotnet build -c Release          # 期望 Build succeeded
Test-Path "bin\Release\netstandard2.1\Probe.dll"   # 期望 True
Set-Location $env:TEMP; Remove-Item $t -Recurse -Force

# ── 3. 游戏与引擎类型 ──────────────────────────────
$game = "C:\Program Files (x86)\Steam\steamapps\common\Probably Stolen"
Test-Path $game
Test-Path "$game\Probably Stolen_Data\Managed\Assembly-CSharp.dll"   # True → 路线 A
Test-Path "$game\GameAssembly.dll"                                   # True → 路线 B

# ── 4. 打包能力（系统自带）─────────────────────────
Get-Command Compress-Archive | Select-Object -ExpandProperty Name

# ── 5. 可选工具 ────────────────────────────────────
git --version
```

---

## 10. 汇总表

| # | 项目 | 必要性 | 安装方式 | 体积 | 备注 |
|---|---|---|---|---|---|
| 1 | **.NET SDK 10** | 🔴 必须 | `winget install Microsoft.DotNet.SDK.10` | ~300 MB | LTS，支持到 2028-11 |
| 2 | **Steam + 游戏** | 🔴 必须 | Steam 客户端 | 数 GB | 提供引用 DLL + 测试环境 |
| 3 | VS Code / VS 2022 / Rider | 🟡 建议 | `winget install Microsoft.VisualStudioCode`<br>`winget install Microsoft.VisualStudio.2022.Community` | 数百 MB ~ 数 GB | 纯命令行也能干活 |
| 4 | `Compress-Archive` | 🟢 自带 | 无需安装 | — | PowerShell 内置 |
| 5 | git | 🟡 可选 | `winget install Git.Git` | ~60 MB | 版本管理 |
| 6 | steamcmd | 🔵 仅发布工坊 | **手动下载**（winget 无包） | ~50 MB | 需拥有正式版的账号 |
| 7 | MelonLoader / BepInEx | ⚪ 仅路线 B | — | — | 确认引擎类型后再决定 |
| 8 | Unity Editor | ⚪ 不需要 | **不要装** | 数十 GB | 只引用 DLL 编译 |

---

## 11. 与 Linux 清单的差异对照

| 项目 | Linux（原机器） | Windows（新机器） |
|---|---|---|
| 游戏参考程序集 | ❌ 必须从别处拷贝 `Managed/` | ✅ **直接用游戏目录，无需拷贝** |
| `csproj` 路径分隔符 | `/`（需从 `\` 改） | `\`（原生，照抄官方指南即可） |
| 游戏目录写权限 | 一般无问题 | ⚠️ `Program Files` 受写保护，需规避 |
| 打包工具 | `zip` / `7z` / `tar` | PowerShell `Compress-Archive` |
| 运行/测试游戏 | ⚠️ 需 Proton + Wine + protontricks | ✅ 原生运行 |
| MelonLoader（路线 B） | ⚠️ 需 `WINEDLLOVERRIDES` 等特殊处理 | ✅ 官方安装器一键装 |
| 生成 Il2CppAssemblies | ❌ 本机做不到 | ✅ 启动一次游戏即可 |
| Defender 干扰 | — | ⚠️ 可能误报，需加排除项 |

**一句话**：Windows 上除了 `Program Files` 权限和 Defender 两个小坑，其余环节都比 Linux 顺畅。

---

*本清单中的 winget 包 ID、路径写法、PowerShell 命令均于 2026-10-16 核实。*
