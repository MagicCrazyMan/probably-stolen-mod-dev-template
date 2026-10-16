# Windows 环境与常见坑

> 这份文档只讲**Windows 上特有的问题**。装什么、怎么建第一个模组，
> 见 [`从未开始到第一个模组.md`](从未开始到第一个模组.md)；
> 当前路线的技术细节见 [`IL2CPP-Mod-实战笔记.md`](IL2CPP-Mod-实战笔记.md)。

---

## 1. 需要什么

| 项 | 要求 | 说明 |
|---|---|---|
| **.NET SDK** | **10.x** | 用 `dotnet --list-sdks` 验证。**只装 Runtime 不够** |
| **MelonLoader** | **0.7.3** | 解压到游戏根目录；启动一次游戏生成代理程序集 |
| **游戏** | Demo 或正式版 | 提供引用程序集与测试环境 |
| 编辑器 | 任意（VS Code / VS / Rider） | 可选，纯命令行也能干活 |
| steamcmd | 仅发布创意工坊需要 | 见第 4 节 |

**磁盘空间**：代理程序集约几百 MB；构建产物很小。

### 为什么不能只装 Visual Studio

VS 的 **C++ 工作负载不包含 C# 编译器**。只装它的话，`MSBuild.exe` 在，
但 `Roslyn\csc.exe` 不在，`SdkResolvers` 里也没有 `Microsoft.DotNet.MSBuildSdkResolver`
—— **编译不了 C#**。想用 VS 就得勾选「**.NET 桌面开发**」工作负载；
否则用 `dotnet` CLI（推荐，跨平台、行为一致）。

---

## 2. Windows 特有的坑

### 坑 1：`C:\Program Files (x86)` 受写保护

游戏若装在默认位置（`C:\Program Files (x86)\Steam\...`），该目录**普通用户不可写**：

- 无法在其中创建源码目录
- `dotnet build` 往 `bin\` / `obj\` 写入会失败，或需要管理员权限
- IDE 打开工程时报权限错误

**对策（推荐）**：工程放用户目录，引用游戏 DLL 的绝对路径即可。
本模板库就是这么做的 —— `workspace/` 在工作区内，游戏目录只用来**读**引用。

> 不建议给 Steam 目录提权：Steam 校验/更新可能重置权限。

### 坑 2：游戏目录名带空格

`Probably Stolen` / `Probably Stolen Demo` 都含空格，于是：

- **`csproj` 的 `<HintPath>` 里没问题** —— XML 会正确处理
- **命令行/脚本里必须加引号**：`cd "<路径>"`、`$game = "<路径>"`
- PowerShell 变量赋值时引号别漏

### 坑 3：Windows Defender 可能误报

编译出的 DLL 会被游戏加载（相当于代码注入），实时保护可能拦截或隔离。

**若遇到**：把工程目录和游戏目录加入排除项
（设置 → 隐私和安全性 → Windows 安全中心 → 病毒和威胁防护 → 排除项）。

### 坑 4：反斜杠是**对的**，别照 Linux 改

`csproj` 里用 `\` 是 Windows 原生写法。网上很多示例是 Linux/macOS 的 `/`，
在这个环境下改成 `/` 反而不一致。

### 坑 5：`<Private>false</Private>` 不能省

引用游戏程序集时必须加，否则它们会被复制进输出目录。两个后果：

- 发布包体积暴涨
- 可能与游戏自带程序集**同名冲突**，被判定为「冒用游戏程序集」而拒绝加载

本模板库的 `Directory.Build.props` 已统一设好，**不要在单个工程里覆盖**。

### 坑 6：游戏运行时会锁住已加载的 DLL

游戏跑着的时候，`<游戏>\Mods\<你的模组>.dll` 被占用，
重新构建 + 部署会失败：

```
MSB3027 / MSB3021: 文件被 xxx.exe 锁定
```

**对策**：退游戏再构建。这在迭代时很容易忘。

---

## 3. 构建产物与打包

本模板库的脚本已经处理好路径问题：

```powershell
pwsh build\deploy.ps1 -Deploy -Log      # 探测游戏 → 编译 → 部署 → 看日志
pwsh build\pack.ps1 -Mod <模组名>        # 打发布包（会自动校验版本号写进了 DLL）
```

打包用 PowerShell 内置的 `Compress-Archive`，**不需要额外装 zip 工具**。

**发布包结构**（解压到游戏根目录即用）：

```
<模组名>-v<版本>.zip
├── README.txt
└── Mods\<模组名>.dll
```

> ⚠️ 压缩包**根目录**必须直接是 `README.txt` 和 `Mods\`，不要多套一层文件夹，
> 否则玩家解压后放错位置。

---

## 4. 仅发布创意工坊才需要：steamcmd

**创意工坊只在正式版可用**（Demo 没有）。编译打包完全不需要 steamcmd。

> `winget` 上**没有** steamcmd 包，需手动下载：
> https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip
> 解压到如 `C:\steamcmd\`，首次运行会自动更新自身。

上传：

```powershell
C:\steamcmd\steamcmd.exe +login <你的Steam账号> +workshop_build_item "<你的 .vdf 路径>" +quit
```

`.vdf` 文件内容：

```
"workshopitem"
{
    "appid"            "4348910"
    "publishedfileid"  "0"
    "contentfolder"    "<模组文件夹绝对路径>"
    "previewfile"      "<预览图绝对路径>"
    "visibility"       "0"
    "title"            "模组名"
    "description"      "模组说明"
    "changenote"       "首次发布"
}
```

| 字段 | 说明 |
|---|---|
| `appid` | 游戏 AppID：正式版 `4348910` |
| `publishedfileid` | **首次填 `0`**；steamcmd 会创建新物品、打印新 ID **并写回该文件**。保留文件，之后填上 ID 再跑同一命令即为**更新** |
| `contentfolder` | 模组文件夹（根目录要有 `manifest.xml` 之类的清单，若是官方系统路线） |
| `previewfile` | 建议 < 1 MB 的图 |
| `visibility` | `0` 公开 / `1` 仅好友 / `2` 隐藏（首次测试建议隐藏） |

**前提**：

- Steam 账号**拥有正式版**
- 首次上传需在 Steam 网站接受一次创意工坊法律协议
- ⚠️ **不要把 Steam 密码或令牌写进脚本、提交到仓库**

---

## 5. 验证清单

装完环境后逐条跑，全绿即可开工：

```powershell
# 1) SDK 就位（要能看到 10.x 一行）
dotnet --list-sdks

# 2) 能编译 net6.0（顺手确认 SDK 完整）
$t = Join-Path $env:TEMP ("probe-" + [guid]::NewGuid().ToString('N').Substring(0,6))
New-Item -ItemType Directory -Force -Path $t | Out-Null
dotnet new classlib -n Probe --framework net6.0 -o $t | Out-Null
dotnet build (Join-Path $t 'Probe.csproj') -c Release -v quiet --nologo
Remove-Item $t -Recurse -Force

# 3) MelonLoader 与代理程序集
$game = "<你的 SteamLibrary>\steamapps\common\Probably Stolen Demo"
Test-Path "$game\version.dll"                                        # 期望 True
Test-Path "$game\MelonLoader\Il2CppAssemblies\Assembly-CSharp.dll"   # 期望 True（需先启动过游戏）

# 4) 引擎类型（判断走哪条路线）
Test-Path "$game\Probably Stolen_Data\Managed"   # True → Mono（路线 A）
Test-Path "$game\GameAssembly.dll"               # True → IL2CPP（路线 B）

# 5) 打包能力（系统自带）
Get-Command Compress-Archive | Select-Object -ExpandProperty Name
```

---

## 附：判断你手上是哪个版本

| 特征 | 结论 |
|---|---|
| 有 `<游戏>_Data\Managed\` | Unity **Mono** → 官方 Mod 系统（`manifest.xml` + `IMod`，`netstandard2.1`） |
| 有 `GameAssembly.dll` 且**没有** `Managed\` | Unity **IL2CPP** → MelonLoader 路线（`net6.0`） |

当前公开的 Demo 是后者。**两条路线的工具链、命名空间、可用 API 都不同，不要混用。**
