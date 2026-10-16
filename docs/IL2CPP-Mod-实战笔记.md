# 《深空当铺：可能是偷的》IL2CPP Mod 实战笔记

> 编写日期：2026-10-17　　作者：DSH 协作会话（MagicCrazyMan）
> 适用对象：**接手这个仓库的下一个人**，或几个月后忘了细节的自己。
> 内容全部来自本机实测，不是文档抄录。凡标注「实测」的都有日志或命令输出为证。

**这份文档解决什么问题**：官方 [ModdingGuide](https://github.com/dragonpan2/probably-stolen-modding) 描述的是**正式版 / Mono** 的路线，而当前能拿到的公开构建是 **Demo 0.46D / IL2CPP / 且模组加载器被禁用**。两者的工具链、命名空间、可用 API 都不一样，照抄官方文档会连续踩坑。

> ⚠️ 本库**不收录**那份官方指南的副本 —— 它面向尚未上市的正式版，
> 且本构建缺其中一大批 API，抄进仓库容易误导。需要时去上面的官网链接看最新版。

配套阅读：
- [`从未开始到第一个模组.md`](从未开始到第一个模组.md) —— 按步骤做的入门流程
- [`Windows-环境清单.md`](Windows-环境清单.md) —— ⚠️ 部分内容已过时，见本文第 1 节

---

## 目录

1. [环境实录（2026-10-17）](#1-环境实录2026-10-17)
2. [关键路线修正：Demo 到底是什么](#2-关键路线修正demo-到底是什么)
3. [游戏架构：窗口 / 背包 / 元素图](#3-游戏架构窗口--背包--元素图)
4. [API 探测方法论](#4-api-探测方法论)
5. [用游戏原生框架编写 UI](#5-用游戏原生框架编写-ui)
6. [踩坑清单](#6-踩坑清单)
7. [用法验证：从零到「游戏里能看到日志」](#7-用法验证从零到游戏里能看到日志)
8. [还没搞清楚的](#8-还没搞清楚的)

---

## 1. 环境实录（2026-10-17）

### 1.1 实际在用的版本

| 项 | 实测值 |
|---|---|
| OS | Windows 11 |
| .NET SDK | **10.0.402**（`C:\Program Files\dotnet\sdk`） |
| 游戏 | `F:\SteamLibrary\steamapps\common\Probably Stolen Demo`，895 MB |
| 游戏版本 | **0.46D**（存档内标记 `VERSION 049-Rev5-L`） |
| 引擎 | Unity **2021.3.45f2**，**IL2CPP** |
| MelonLoader | **0.7.3 Open-Beta**（`version.dll` 注入 + `MelonLoader\`） |
| 代理程序集 | `MelonLoader\Il2CppAssemblies\`，138 个 DLL |
| 生成工具链 | Cpp2IL 2022.1.0-pre-release.21 + Il2CppInterop 1.5.1-ci.845 |
| **Mod 目标框架** | **`net6.0`**（不是官方文档说的 `netstandard2.1`） |
| Harmony | **HarmonyX 2.10.2**（MelonLoader 自带 `net6\0Harmony.dll`） |
| 显示器 / 分辨率 | 3840×2160 物理，游戏内 1920×1080 渲染 |

### 1.2 与旧文档的差异（重要）

[`Windows-环境清单.md`](Windows-环境清单.md) 说「装 .NET SDK 10 + Steam + 游戏，2 个软件就能开工」。实测有三处不符：

| 旧文档说法 | 实测 |
|---|---|
| 需装 .NET SDK | ✅ 对。但**只装了运行时是不够的** —— `dotnet --list-sdks` 必须能列出 10.0.x |
| VS 2022 可以编译 C# | ❌ **不行**。本机 VS 2022 Community 17.14.40 只装了 C++ 工作负载：`MSBuild.exe` 在，但 `Roslyn\csc.exe` 不存在、`SdkResolvers` 里没有 `Microsoft.DotNet.MSBuildSdkResolver`。**命令行 SDK 才是唯一能编译 C# 的途径** |
| 游戏在 `Program Files` 受写保护是个坑 | ⚠️ 本机游戏装在 `F:\SteamLibrary`，无此问题 |

### 1.3 一个容易忽略的限制：沙箱

DSH 会话的文件沙箱默认只允许写工作区。这影响两件事：

- `dotnet build` 往游戏目录写 `bin\obj` → 被拒（所以工程放工作区、游戏目录只用来读引用）
- 「构建后自动部署到游戏 `Mods\`」这种后置事件 → 被拒（要么切 full access，要么手动拷）

---

## 2. 关键路线修正：Demo 到底是什么

### 2.1 三个反直觉的事实

**① Demo 内部其实有完整的官方 Mod 系统**

扫 `global-metadata.dat` 可以找到：`ModLoader`、`ModManifest`、`LoadedMod`、`ModHook`、`ModHelper`、`ModItemDirectory`、`CustomUIManager`、`LootRegistry`、`ModUIManager`，以及钩子 `OnModItemDirectoryInit` / `OnGameLoaded{Normal…}` / `OnShutterOpened*` / `OnLootRolled` 等。

所以最初调研里「Demo 只能用第三方加载器」的说法**需要修正** —— Demo 内建的就是官方系统。

**② 但加载器被硬关了**

游戏自己的日志 `%USERPROFILE%\AppData\LocalLow\Questing Goose Studio\Probably Stolen\Player.log`：

```
[ModLoader] Limited build: mod loading disabled.
```

存档 `SaveFile.es3` 里的版本号印证了这点：

```json
"welcomeVersion": {"__type":"string","value":"VERSION 049-Rev5-L"}
```

末尾那个 **`-L` 就是 Limited**。

**③ 官方文档的 API 清单在这个构建里缺一大半**

| 文档里有、本构建**没有** |
|---|
| `SetModData` / `GetModData`（存档内模组数据） |
| `AddLootEntry` / `SetLootWeight` / `RemoveLootEntry`（掉落表编辑） |
| `PlaySound` / `GetSoundIdentifier` |
| `SetSpriteAndShapeFromMod` / `CreateEmptyItem` |
| `AddDebugFunction` / `AddStartingPerk` / `AddStartingScenario` / `AddDifficulty` / `AddNetworkUpgrade` |
| `ReadModFileText` / `WriteModDataFileText` |
| `ModScanner` / `ModTrust` / `Capabilities` / `mod-scan`（整套能力声明与扫描器） |

**本构建确实有**：`IMod`、`ModManifest`（属性 `ID`/`Name`/`Author`/`ModVersion`/`Description`/`GameVersions`/`Prerequisites`）、`LoadedMod`、`ModHook`、`ModHelper`、`ModItemDirectory`、`ModUIManager`、`LootRegistry`、`GameItem`、`StoreClientManager`、`GetLocalized`。

> ⚠️ **教训**：写代码前**必须查代理程序集**，不要照抄 ModdingGuide。

### 2.2 那到底能不能做 Mod？——能，走 MelonLoader

关键实证：MelonLoader 的注入路径**与上述开关无关**。装了第三方模组后：

```
Melon Assembly loaded: '.\Mods\ProbablyStolenWindowGroups.dll'
1 Mod loaded.
```

而同一份 `Player.log` 里 `[ModLoader] Limited build: mod loading disabled.` 依然在。**两个加载器互不影响。**

### 2.3 正式版（未来）的差异

正式版 2026-10-28 发售（AppID 4348910），预计是 **Mono + 官方 Mod 系统**。届时：

- 需要**重写**：目标框架 `netstandard2.1`、引用 `*_Data\Managed\*.dll`、`IMod` + `manifest.xml`、`ModLog`
- 可以**保留**：业务逻辑（若与游戏耦合层隔离）、打包脚本思路
- 判断方法：看游戏目录有没有 `Probably Stolen_Data\Managed\`（有 → Mono）

---

## 3. 游戏架构：窗口 / 背包 / 元素图

这一节是本文最有价值的部分 —— 官方文档完全没写，而这几个「反直觉」事实决定了很多方案可不可行。

### 3.1 三个对象的真实身份

| 类型 | 基类 | 是不是 Component？ | 说明 |
|---|---|---|---|
| `Il2Cpp.PixelWindow` | `Il2CppObjectBase` | ❌ **纯数据对象** | 一个窗口。成员只有渲染节点：`inner` / `background` / `titleText` / `topCloseButton` / `handler` / `rectTransform` / `focusStamp` / `titleString` … |
| `Il2Cpp.GameInventory` | `Il2CppObjectBase` | ❌ **纯数据对象** | 背包。**没有 `gameObject` / `transform`** |
| `Il2Cpp.TreeNodeRender` | `UnityEngine.MonoBehaviour` | ✅ 是 | 屏幕上的一个界面节点，有 `gameObject` / `transform` / `GetComponent*` |

**这三个身份带来的连锁后果：**

- `window.inner.GetComponentInChildren<GameGridInventory>()` → **永远返回 null**（实测对全部 9 个可见窗口都失败）。因为背包不是挂在 GameObject 上的组件。
- `GetComponent<GameGridInventory>()` 这类写法从根上就不成立，不管怎么调参数。
- **`PixelWindow` 不引用任何背包。** 从窗口对象往下找背包这条路不存在。

### 3.2 元素图（Element Graph）—— 真正的关联方式

界面节点之间存在**父子图**，而背包**也是图上的一个节点**。所以正确的反查方式是：

```csharp
// 沿元素图往上找背包
GameGridInventory inv = someTreeNodeRender.FindParentElement<GameGridInventory>();

// 或者往上找窗口
PixelWindow win = someTreeNodeRender.FindParentWindow();
```

`TreeNodeRender` 上的相关 API（均已核实签名）：

```csharp
PixelWindow  FindParentWindow();
PixelElement FindParentElement();
T            FindParentElement<T>();          // ← 关键，泛型版
```

**这条是本项目最关键的发现。** 它把「屏幕上的一点」和「它属于哪个背包」连了起来。

### 3.3 字符串跳跃法：从符号名反推类型

Cpp2IL/Il2CppInterop 不会保留方法体，但会保留 `NativeMethodInfoPtr_*` 这类静态字段名，
而**名字里编码了完整签名**。这是一个极高效的探测手段：

```
NativeMethodInfoPtr_get_focusStamp_Public_get_Int64_0
                          ↑方法名          ↑可见性 ↑返回类型

NativeMethodInfoPtr_Sort_Public_Static_Boolean_GameGridInventory_Boolean_Boolean_0
                        ↑方法  ↑静态  ↑返回bool    ↑参数1类型         ↑参数2  ↑参数3

NativeMethodInfoPtr_get_inner_Public_Virtual_Final_New_get_TreeNodeRender_0
                                                          ↑返回 TreeNodeRender
```

用一行 PowerShell 就能提取：

```powershell
$dll = "$game\MelonLoader\Il2CppAssemblies\Assembly-CSharp.dll"
$txt = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($dll))
[regex]::Matches($txt,'NativeMethodInfoPtr_Sort_[A-Za-z0-9_]*') | ForEach-Object { $_.Value }
```

如果 `NativeMethodInfoPtr_*` 没覆盖到你要的方法（例如泛型），退回 `Assembly-CSharp.dll` 的
**IL 元数据签名 blob**，或直接用第 4 节的反射工具。

### 3.4 游戏自己的「窗口 ↔ 背包」表（用不上，但值得知道）

真正的静态映射藏在 `Il2Cpp.EmporiumEntry` 的**私有字段对**里：

```
_invWindow            / _invElement              ← 玩家背包
_frontInvWindow       / _frontInvinvElement      ← 前台
_backInvWindow        / _backInvinvElement       ← 后台
_hiddenWindow         / _hiddenElement
_trashInvWindow       / _trashInvElement
_bazarLeftInvWindow   / _bazarLeftinvElement
_faucetWindow         / _faucetElement
_cassettePlayerWindow / _cassettePlayerElement
_vendingMachineWindow / _vendingMachineElement
…（还有 drain / docInv / showcase 等）
```

两个坏消息：

1. 只有 `invWindow` / `invElement` / `showcaseWindow` / `showcaseElement` 是**公开属性**，其余都是私有。
2. **玩家动态打开的箱子/容器窗口根本不在这张表里** —— 它们是运行时 `CreateGridWindow(x, y)` 创建的，返回 `ValueTuple<PixelWindow, GameGridInventory>`，对应关系不入表。

所以想「枚举所有背包」或「按窗口找背包」，走 `FindParentElement<T>()` 才是正路。

### 3.5 窗口前后顺序

```csharp
Il2Cpp.WindowsHandler.current.visibleWindows   // Il2CppSystem.Collections.Generic.List<PixelWindow>
Il2Cpp.PixelWindow.focusStamp                  // Int64，越大 = 越靠前
```

游戏每次聚焦窗口时用 `NextFocusStamp()` 盖一个**单调递增**的戳，所以 `focusStamp` 最大的窗口就是最前面的。实测正确：打开「储藏区」时它 `stamp=249` 排第一。

> 这条本身很有用（例如做窗口管理类模组），但**光有窗口没用**，因为窗口不引用背包（见 3.1）。

---

## 4. API 探测方法论

### 4.1 首选：本仓库自带的反射工具

位置 `tools/Inspect`。用独立 .NET 进程加载代理程序集，输出权威签名：

```powershell
$env:PS_GAME_ASM_DIR = "$game\MelonLoader\Il2CppAssemblies"
$insp = 'tools\Inspect\bin\Release\net6.0\Inspect.dll'

dotnet $insp find 'Inventory|Sort|Window'           # 按类型名正则搜索，打印全部成员
dotnet $insp show PixelWindow 'focus|window|title'  # 看某类型成员（第二个参数是成员名正则）
dotnet $insp base TreeNodeRender                    # 看继承链

# 看 Unity 侧的类型要加 -asm
dotnet $insp -asm UnityEngine.CoreModule show Object 'FindObjectsOfType'
dotnet $insp -asm MelonLoader show MelonPreferences  # 加载器的 API 在 ..\net6\MelonLoader.dll
```

重建：`dotnet build tools\Inspect\Inspect.csproj -c Release`

**⚠️ 两个使用陷阱：**

1. **别把它复制进 `Il2CppAssemblies\`** —— 游戏运行时会把 `Inspect.dll` 锁住，之后构建直接报 `MSB3027 文件被 Probably Stolen.exe 锁定`。就地运行 + `PS_GAME_ASM_DIR` 即可。
2. **`-asm` 要放在子命令前面**。`dotnet $insp find ... -asm X` 会被当成子命令参数，然后它去加载默认的 `Assembly-CSharp` 并失败。

### 4.2 备选：直接读 IL 元数据

不加载程序集，不会崩，适合脚本化：

```powershell
$dll = "$game\MelonLoader\Il2CppAssemblies\Assembly-CSharp.dll"
$fs=[IO.File]::OpenRead($dll); $pe=[Reflection.PortableExecutable.PEReader]::new($fs)
$md=[Reflection.Metadata.PEReaderExtensions]::GetMetadataReader($pe)
foreach ($h in $md.TypeDefinitions) {
  $t=$md.GetTypeDefinition($h)
  if ($md.GetString($t.Name) -match 'Sort|Inventory') {
    "  $($md.GetString($t.Namespace)).$($md.GetString($t.Name))"
  }
}
$pe.Dispose(); $fs.Dispose()
```

### 4.3 ⚠️ 千万不要在 PowerShell 里做这件事

```powershell
# ❌ 会把 PowerShell 进程直接搞崩（我崩过一次）
[AppDomain]::CurrentDomain.add_AssemblyResolve({ ... })
[Reflection.Assembly]::LoadFrom($interopDll)
$asm.GetTypes()
```

那个 `AssemblyResolve` 处理器会连 **PowerShell 自身的模块加载**一起拦截，递归到栈溢出。
要反射就用独立 exe（就是 4.1 那个工具）。

### 4.4 别忘了 IL2CPP 是 AOT

泛型方法**只有游戏自己实例化过的类型参数**才真正可用。但是：

- 好消息：不可用时通常会**抛异常**（`MissingMethodException` 之类），比较容易发现
- 坏消息：也有「能调用、不抛异常，但返回 null」的情况 —— 见 5.1

所以**每个新用到的泛型 API 都要实机验证**，别只看编译通过。

---

## 5. 用游戏原生框架编写 UI

**结论先行：不要自己拼 UI。** 游戏自带一套给模组用的 UI 框架 —— `Il2Cpp.CustomUIManager`，
它持有一整套**与游戏本体同款的预制件**，所以用它画出来的界面**天然就是官方风格**，
字体、配色、边距、点击音效全都不用操心。

> 这一节是实际做模组设置界面时趟出来的，不是纸上推演。

### 5.1 先找对入口，别急着动手

做 UI 前的第一件事是**侦察有哪些现成框架**，而不是打开 `UnityEngine.UI` 开始摆控件。
本项目当时的侦察顺序与结论：

| 找到的类型 | 性质 | 结论 |
|---|---|---|
| `Il2Cpp.ModUIManager` | 游戏「模组」菜单窗口本身 | ❌ 只是那个窗口，无扩展点 |
| `Il2Cpp.GameOptionUIManager` | 游戏「选项」窗口 | ❌ 全是硬编码控件（`masterAudioSlider`、`resolutionDropdown`…），**不能挂自定义选项** |
| **`Il2Cpp.CustomUIManager`** | 持有一整套 prefab | ✅ **就是它** —— 官方给模组留的 UI 入口 |

`CustomUIManager` 的 prefab 字段一眼就能确认它的用途：

```
windowPrefab / labelPrefab / buttonPrefab / imagePrefab / togglePrefab / sliderPrefab
inputFieldPrefab / dropdownPrefab / progressBarPrefab / scrollViewPrefab / tooltipPrefab
```

**教训**：先花十分钟侦察，胜过花两小时手工仿制。我原本准备"照着官方样式自己拼"，侦察后发现根本不用。

### 5.2 完整 API（已核实）

```csharp
// ── 创建窗口，拿到链式构建器（static，内部自己处理 manager 实例）──
CustomUIBuilder b = CustomUIManager.Window(string id, string title, string layerId);

// 图层常量（都是 public 属性）
CustomUIManager.LAYER_FRONT / LAYER_PAPER / LAYER_REAR / LAYER_META / LAYER_MENU / LAYER_OVERLAY

// ── 窗口属性 ──
b.SetSize(float width, float height);
b.SetPosition(Vector2 anchoredPosition);
b.Center();
b.SetCloseOnEscape(bool);
b.SetDraggable(bool);

// ── 加控件（每个都要一个 id，之后可用 window.Get(id) 取回读写）──
b.AddLabel(string text, string id);
b.AddButton(string text, Action onClick, string id);
b.AddToggle(string label, bool initial, Action<bool> onChanged, string id);
b.AddSlider(float min, float max, float initial, Action<float> onChanged, bool wholeNumbers, string id);
b.AddInput(string placeholder, string initial, Action<string> onChanged, string id);
b.AddImage(Sprite sprite, float width, float height, string id);
b.AddProgressBar(float initial, string id);
b.AddDropdown(IList<string> options, int initialIndex, Action<int> onChanged, string id);  // ⚠️ 见 5.4

// ── 布局（必须与 End() 配对，数量不配对会错乱）──
b.BeginRow(float spacing) / b.BeginColumn(float spacing)
b.BeginGrid(int columns, float cellWidth, float cellHeight, float spacing)
b.BeginScroll(float height)
b.End();

// ── 落地 ──
CustomUIWindow w = b.Show();
w.Close() / w.Show() / w.SetTitle(string) / w.SetSize(w,h) / w.Center() / w.BringToFront();
w.IsAlive / w.IsVisible / w.Rect / w.ContentRoot;
w.Get(string elementId);        // 取回控件
w.RegisterElement(CustomUIElement);
```

拿回控件后可以读写值（`CustomUIElement`）：

```csharp
CustomUIElement e = w.Get("t_enabled");
e.SetText(string) / e.SetSprite(Sprite) / e.SetTooltip(string);
e.SetBool(bool value, bool notify);
e.OnToggle(...) / e.SetFloat(float, bool) / e.OnSlider(...) / e.SetString(string, bool)
e.OnInput(...) / e.SetIndex(int, bool) / e.SetOptions(IList<string>) / e.OnDropdown(...)
e.SetProgress(float normalized, string labelText) / e.SetPreferredSize(w, h) / e.OnClick(...)
```

窗口生命周期由框架管：`CustomUIManager.IsOpen(id)` / `CloseWindow(id)` / `CloseAllWindows()`。

### 5.3 最小可用示例

```csharp
using Il2Cpp;
using Il2CppInterop.Runtime;

private CustomUIWindow _window;

// ⚠️ 回调要 Il2Cpp 委托，见 5.4 坑 1
private static Il2CppSystem.Action Act(System.Action a)
    => DelegateSupport.ConvertDelegate<Il2CppSystem.Action>(a);
private static Il2CppSystem.Action<T> Act<T>(System.Action<T> a)
    => DelegateSupport.ConvertDelegate<Il2CppSystem.Action<T>>(a);

void Build()
{
    var b = CustomUIManager.Window("my_mod_config", "我的模组 · 设置", CustomUIManager.LAYER_MENU);
    b.SetSize(560f, 520f);
    b.Center();
    b.SetCloseOnEscape(true);
    b.SetDraggable(true);

    b.BeginScroll(430f);                       // 内容多就套滚动区

    b.AddLabel("<b>分组标题</b>　说明文字", "h1");
    b.AddToggle("启用某功能", true, Act<bool>(v => { _cfg.Value = v; Save(); }), "t_x");

    b.BeginRow(8f);                            // 一行里并排放
    b.AddLabel("按键", "l_key");
    b.AddInput("KeyCode", "R", Act<string>(s => ApplyKey(s)), "in_key");
    b.End();

    b.End();                                   // 结束滚动区

    b.AddButton("保存并关闭", Act(() => { Save(); _window.Close(); }), "btn_save");

    _window = b.Show();
}
```

### 5.4 ⚠️ 三个 Il2Cpp 互操作坑（都实际卡过）

#### 坑 1：回调参数要 Il2Cpp 的委托，不是 .NET 的

`AddToggle` 的 `onChanged` 形参类型是 **`Il2CppSystem.Action<bool>`**，不是 `System.Action<bool>`。
直接塞 lambda **编译不过**：

```
error CS1660: 无法将 lambda 表达式转换为类型“Action<bool>”，原因是它不是委托类型
```

`Il2CppSystem.Action<T>` 的构造函数要**方法指针**（`IntPtr`），所以也不能 `new`。
正解是走 `Il2CppInterop.Runtime.DelegateSupport`：

```csharp
using Il2CppInterop.Runtime;
Il2CppSystem.Action<bool> cb = DelegateSupport.ConvertDelegate<Il2CppSystem.Action<bool>>(netDelegate);
```

封装成 5.3 里那两个 `Act` / `Act<T>` 辅助方法，调用点就干净了。

> `Il2CppInterop.Runtime.dll` 在 **`MelonLoader\net6\`**，不在 `Il2CppAssemblies\`。

#### 坑 2：`AddDropdown` 的选项参数喂不进去 → 改用按钮组

形参类型是 `Il2CppSystem.Collections.Generic.IList<string>`。三种写法**全被编译器拒**：

| 写法 | 结果 |
|---|---|
| `Il2CppSystem.Collections.Generic.List<string>` | ✗ 无法转换 |
| `Il2CppInterop...Il2CppReferenceArray<string>` | ✗ `string` 不满足 `T : Il2CppObjectBase` |
| `Il2CppReferenceArray<Il2CppSystem.String>` | ✗ 仍不满足那个 `IList` |

**对策：用按钮组代替下拉框。**

```csharp
b.AddLabel("用哪个方案：", "l_scheme");
b.BeginRow(8f);
for (int i = 0; i < 4; i++)
{
    int idx = i;
    bool current = (_scheme.Value == i + 1);
    b.AddButton(current ? $"▶ {i + 1}" : $"{i + 1}",
        Act(() => { _scheme.Value = idx + 1; Save(); Rebuild(); }), $"btn_scheme{idx}");
}
b.End();
```

这不只是绕过问题 —— **游戏里点按钮本来也比开下拉框顺手**，而且当前项显示成 `▶ 2` 一眼可见。
如果你确实需要下拉框，去研究 `CustomUIManager` 内部怎么构造那个 `IList`（`dropdownPrefab` 相关代码）。

#### 坑 3：布局必须 `Begin*` / `End()` 配对

`BeginRow` / `BeginColumn` / `BeginGrid` / `BeginScroll` 都要有对应的 `End()`。
数量不配对**布局会错乱**（而且不一定报错，只是显示不对）。写的时候按缩进对齐，一眼能看出配对。

### 5.5 配置文件 vs UI：两者都要

推荐形态是**两条路并存**：

- **配置文件**（`UserData\MelonPreferences.cfg`）：MelonLoader 标准机制，
  改默认值、脚本化、备份都靠它。注意它有「退出时被写回」的坑（见 6.2）。
- **UI（F7）**：给不想编辑配置文件的玩家用。改完 `MelonPreferences.Save()` **即时存盘**，
  比改配置文件的「改完重启」体验好得多。

**建议**：配置项少就直接读配置；超过三五个、或者有键位这种不查文档填不出来的项，就配一个 UI。

### 5.6 加 UI 时要顺手加的配置项

做一个「打开设置界面」的按键，并**让它可配置** —— 否则一旦和别的模组撞键，玩家没法自救：

```csharp
_configKey = _cfg.CreateEntry<KeyCode>(
    "ConfigKey", KeyCode.F7,
    "打开设置界面的按键",
    "按这个键打开本模组的设置界面。设为 None 可禁用。");
```

---

## 6. 踩坑清单

按「坑有多难查」排序。

### 6.1 「能调用但返回 null」的 API —— 最阴的一类

实测同一个场景下：

| 方法 | 结果 |
|---|---|
| `RenderHandler.RaycastElement<TreeNodeRender>(pos, null)` | ❌ **一直返回 null** |
| `RenderHandler.RaycastFindParentElement<TreeNodeRender>(pos, null)` | ❌ **一直返回 null** |
| `EventSystem.current.RaycastAll(...)` | ✅ 成功 |

前两条**能调用、不抛异常**，所以不是 IL2CPP 泛型实例化问题（那会抛异常），
而是它内部的前置条件（可能与 `PixelWindow.forceRaycast` 或 canvas 选择有关）。

**对策**：
- 优先用 **Unity 标准 API**（`EventSystem`），而不是游戏自研的辅助方法
- 写多路径探测 + 日志，一次实测定位；**别一条路走死**
- 我曾把它当「游戏自己提供的正路」直接用，浪费了一轮实机测试

### 6.2 MelonLoader 会覆盖你的配置文件

**实测证据**（同一局游戏）：

```
21:44:29.702  [QuickSort] 已更新 UserData\MelonPreferences.cfg（该段全部注释）  ← 模组写的
21:44:38      （退出游戏）→ 文件被写回未注释形式，修改时间 21:44:38          ← MelonLoader 盖的
```

**MelonLoader 是 `MelonPreferences.cfg` 的唯一所有者**，它在游戏退出时按自己内存里的状态重写。
而且 `CreateCategory(..., is_hidden, should_save: false)` 的 `should_save: false` **也拦不住**。

**对策**：不要试图改写那个文件。想控制呈现方式，只能控制 `CreateEntry` 的默认值与 `description`。
真想要「注释掉的模板」那种形态，用**独立文件**。

### 6.3 偏好项一旦进了玩家配置，就再也不会被新默认值覆盖

**这个坑导致整套功能静默失效，查了好几轮。**

时间线：
1. v1.x 代码里有个 `RequireCtrl` 开关，默认 `true` → 写进了玩家的 `MelonPreferences.cfg`
2. v2.0 把代码里的默认值改成 `false`
3. **完全没生效** —— 玩家配置里的 `RequireCtrl = true` 一直压着
4. 表现是「按数字键没反应」，而日志里连一行提示都没有（按键在早期 return 就被拦了）

**对策**：**改默认值、删配置项、或重命名配置项之后，必须同步清理玩家侧的旧配置。**
`MelonPreferences_Category` 提供了平滑迁移的工具：

```csharp
MelonPreferences_Category.DeleteEntry(identifier);
MelonPreferences_Category.RenameEntry(identifier, oldIdentifier);
```

### 6.4 `.gitignore` 不支持行尾注释

```
foo/     # 说明文字      ← ❌ 整行连注释一起当模式，这条规则静默失效
```

**我因此有 10 条规则失效**（`workspace/dist`、`refs/`、`Managed/`、`Il2CppAssemblies/`、`*.user` 等），
`tools/` 目录被误提交进仓库。注释必须**单独成行**。

验证方式：

```powershell
git check-ignore -v <路径>      # 打不出东西 = 没被忽略
```

### 6.5 Il2CppInterop 的几个类型/API 差异

| 直觉写法 | 实际 |
|---|---|
| `List<PixelWindow>` | 是 **`Il2CppSystem.Collections.Generic.List<PixelWindow>`**，不是 .NET 的 `List<T>` |
| `Object.FindObjectsOfTypeAll<T>()` | 代理程序集里**只有非泛型重载** `FindObjectsOfTypeAll(Type)`，而且参数是 **`Il2CppSystem.Type`** 不是 `System.Type` |
| `comp.gameObject` on `GameInventory` | ❌ 编译报错 —— 它压根不是 Component |
| `obj as UnityEngine.Object` where obj is `GameInventory` | ❌ 无法转换，同上 |

### 6.6 命名空间：`Il2Cpp` 前缀，但文件名没有前缀

- 游戏类型全在 **`Il2Cpp`** 命名空间下：`Il2Cpp.InventorySortHelper`、`Il2Cpp.GameItem` …
- 但代理程序集的文件名是 **`Assembly-CSharp.dll`**（**没有** `Il2Cpp` 前缀）
- 里面的类型如 `Il2CppTMPro.TMP_InputField`、`Il2CppStringArray` 也带前缀

**别被文件名骗了。**

### 6.7 `Il2Cpp.IMod` 不是 interface

它是 `Il2CppObjectBase` 的**代理类**，不是接口 —— 所以官方文档那套
`public class X : IMod` 在 IL2CPP 下**写不出来**（编译器会报「无法继承密封类/非接口」之类）。
用 `MelonMod` 子类。

### 6.8 加载 DLL 的顺序陷阱

`dotnet build` 出错后**先看错误码**：

- `MSB3027 / MSB3021 文件被 xxx.exe 锁定` → 游戏还在运行，把 `Mods\` 下的 DLL 锁住了。**先退游戏再构建。**
- `error PS001 / PS002`（本仓库自定义） → 引用程序集不齐，按提示改 `GameDir`

### 6.9 别在 `Init` / `OnEnable` 里访问游戏系统

（这条来自官方文档，实测同样适用）
MelonLoader 的 `OnInitializeMelon` 跑在**主菜单阶段**，游戏玩法系统还没初始化。
要在游戏内时机做事，用 `MelonHook` 钩子或 `OnUpdate`。

---
## 7. 用法验证：从零到「游戏里能看到日志」

这一节是**最小闭环**，按顺序做，每一步都有明确的成功判据。
做完它你就有了一个能加载、能打日志的模组骨架，之后再加功能。

### 7.1 准备（只做一次）

```powershell
# 1) 确认 .NET SDK（要能列出 10.x，只有运行时是不够的）
dotnet --list-sdks

# 2) 确认游戏与 MelonLoader
$game = "F:\SteamLibrary\steamapps\common\Probably Stolen Demo"
Test-Path "$game\version.dll"                              # MelonLoader 引导器
Test-Path "$game\MelonLoader\Il2CppAssemblies\Assembly-CSharp.dll"   # 代理程序集
```

若第 3 项为 `False`：**先启动一次游戏**。MelonLoader 首次运行会联网下载
Cpp2IL 并生成代理程序集（几分钟）。没有它，任何模组都编译不了。

### 7.2 新建工程

在 `workspace/src/` 下建目录，`.csproj` 照抄这个形状（**重点是 `net6.0`**）：

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net6.0</TargetFramework>
    <LangVersion>latest</LangVersion>
    <Nullable>disable</Nullable>
    <ImplicitUsings>disable</ImplicitUsings>
    <AssemblyName>MyFirstMod</AssemblyName>
    <RootNamespace>MyFirstMod</RootNamespace>
    <ProduceReferenceAssembly>false</ProduceReferenceAssembly>
  </PropertyGroup>
</Project>
```

引用不用自己写 —— 根目录的 `Directory.Build.props` 已经把那 12 个程序集
（MelonLoader / 0Harmony / Il2CppInterop / Assembly-CSharp / UnityEngine.*）都配好了。

### 7.3 最小可加载的模组

```csharp
using System;
using Il2Cpp;
using MelonLoader;
using UnityEngine;

[assembly: MelonInfo(typeof(MyFirstMod.Mod), "My First Mod", "1.0.0", "你的名字")]
// 游戏名与开发商取自 <游戏>_Data\app.info：第一行是开发商，第二行是游戏名
// 注意是 "Probably Stolen"，不是 "Probably Stolen Demo"
[assembly: MelonGame("Questing Goose Studio", "Probably Stolen")]

namespace MyFirstMod
{
    public class Mod : MelonMod
    {
        public override void OnInitializeMelon()
        {
            MelonLogger.Msg("[MyFirstMod] 已加载。");
        }

        public override void OnUpdate()
        {
            if (Input.GetKeyDown(KeyCode.F9))
                MelonLogger.Msg("[MyFirstMod] F9 被按下。");
        }
    }
}
```

**⚠️ 注意 `Il2Cpp.IMod` 不是 interface**（是 `Il2CppObjectBase` 的代理类），
所以官方文档那套 `class X : IMod` 在当前路线下写不出来。用 `MelonMod` 子类。

### 7.4 构建、部署、验证

```powershell
pwsh build\deploy.ps1 -Deploy -Log
```

脚本会：探测游戏目录 → 编译 → 拷进 `<游戏>\Mods\` → 打印 MelonLoader 最新日志。

**成功判据**（日志里出现这几行）：

```
Melon Assembly loaded: '.\Mods\MyFirstMod.dll'
My First Mod v1.0.0
[MyFirstMod] 已加载。
```

按 F9 应再出现一行。**到这一步，工具链就算通了。**

### 7.5 接下来

1. **先查 API，再写代码** —— 用第 4 节的 `tools/Inspect`。
   不要凭官方文档写（见第 2 节：本构建缺一大批 API）。
2. **确认可用的扩展点** —— 第 3 节讲了游戏的对象模型，
   尤其是「背包不是 Component」这类反直觉事实。
3. **要加 UI 就看第 5 节** —— 用游戏自己的 `CustomUI` 框架。
4. **动手前扫一眼第 6 节踩坑清单** —— 能省很多时间。

### 7.6 一个完整案例

**QuickSort**（深空当铺的整理快捷键模组）是照着这套流程做出来的完整例子
（从逆向游戏自带功能、到绕开不可用的 API、到做设置界面）。
它的源码可作为真实参考，但它**是这个项目自己的产物，不属于模板库**。
---

## 8. 还没搞清楚的

留给下一个接手的人：

| 问题 | 已知线索 |
|---|---|
| `RenderHandler.RaycastElement` 为什么返回 null | 能调用、不抛异常，坐标也正确。怀疑与 `PixelWindow.forceRaycast` 或 canvas 选择有关 |
| `CustomEventHandler.GetRayCast()` / `rayCastResult` 怎么用 | 是 public 的（`GetRayCast()` 返回 `TreeNodeRender`），但 `CustomEventHandler` 没有静态 `current`，没找到实例入口 |
| `StoreUIManager.PerformRaycastOnCanvas(Canvas, PointerEventData)` 的用法 | 签名已知，未实验 |
| `ModHook` 钩子在本构建会不会 fire | 游戏的加载器被禁用，**尚未验证**。建议不依赖它，直接调 API 更稳 |
| `CustomUIBuilder.AddDropdown` 的选项参数到底该传什么 | `IList<string>` 的三种写法都被编译器拒（见 5.4 坑 2）。需要时去看 `CustomUIManager` 内部怎么构造它 |
| `AddSlider` / `AddImage` / `AddProgressBar` 在本 build 是否可用 | 签名已核实，未实机验证（目前只用了 Label / Toggle / Button / Input） |
| 游戏给界面节点命名的规律 | EventSystem 命中到的 GameObject 名字是 `"Node"`（很泛）。多抓几个名字可能有规律 |
| 正式版（Mono）的实际 API 差异 | 需要拿到正式版后重新探测一遍 |

---

---

## 附：常用命令速查

```powershell
# 游戏目录
$game = "F:\SteamLibrary\steamapps\common\Probably Stolen Demo"

# 构建 + 部署 + 看日志
pwsh build\deploy.ps1 -Deploy -Log

# 打发布包
pwsh build\pack.ps1 -Mod <你的模组名>

# 反射查游戏 API
$env:PS_GAME_ASM_DIR = "$game\MelonLoader\Il2CppAssemblies"
dotnet tools\Inspect\bin\Release\net6.0\Inspect.dll find 'Sort|Inventory'

# 看游戏自己的日志（ModLoader 状态、游戏内错误）
Get-Content "$env:USERPROFILE\AppData\LocalLow\Questing Goose Studio\Probably Stolen\Player.log"

# 看 MelonLoader 日志（模组加载情况）
Get-ChildItem "$game\MelonLoader\Logs" | Sort-Object LastWriteTime -Descending |
  Select-Object -First 1 | Get-Content
```

---

*本文档基于 2026-10-17 的本机实测整理。所有「实测」结论都有当次日志或命令输出为据；
凡属推断的地方均已标注。*
