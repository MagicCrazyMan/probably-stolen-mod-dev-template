# Probably Stolen Mod 开发模板库

一套可直接开工的《深空当铺：可能是偷的》（Probably Stolen）Mod 开发环境：
**agent skill + 实战文档 + API 探测工具 + 构建脚手架**。

> **当前路线**：Demo 0.46D / Unity 2021.3.45f2 / **IL2CPP** / **MelonLoader 0.7.3**
> 游戏内建的官方 Mod 系统在当前公开构建里**被禁用了**
> （`Player.log`: `[ModLoader] Limited build: mod loading disabled.`），
> 所以这里走的是 MelonLoader 路线，**目标框架 `net6.0`**（不是官方文档说的 `netstandard2.1`）。

---

## 为什么要有这个库

模组开发最容易卡住的不是写 C#，而是这几件事：

- **官方文档用不了** —— 它面向尚未上市的正式版，而且本构建**缺其中一大批 API**，
  照抄会连续踩坑
- **游戏对象模型反直觉** —— 背包不是 `Component`，`GetComponent*` 永远找不到它；
  得走元素图
- **Il2Cpp 互操作有隐藏陷阱** —— 委托、列表、泛型实例化都与普通 .NET 不同
- **Il2CPP 是 AOT** —— 有些泛型 API 能编译但运行时不可用

这些结论来自实际做出一个完整模组的过程，全部有日志或命令输出为证。
本库把它们固化下来：**clone 一次，agent 自动具备这些知识。**

---

## 快速开始

### 1. clone 下来，并让它成为你的工作区

```powershell
git clone --depth 1 https://github.com/MagicCrazyMan/probably-stolen-mod-dev-template ps-mod-dev
```

然后用 DSH（或任何支持 `.agents/skills/` 的 agent 工具）**把 `ps-mod-dev` 目录作为工作区打开**。

> ⚠️ **必须让它成为工作区根**。agent 只在「工作区的 `.git` 根」上发现 skill ——
> 把本库放进别的仓库的子目录里是**不会生效**的。

`--depth 1` 拿的是最新快照，不带历史提交。想要更干净的方式见
[「不想要 git 历史」](#不想要-git-历史)。

### 2. 按文档做第一个模组

打开 [`docs/从未开始到第一个模组.md`](docs/从未开始到第一个模组.md)，按顺序走。
大约 30–60 分钟，每步都有明确的成功判据。

### 3. 之后

```powershell
pwsh build\deploy.ps1 -Deploy -Log      # 构建 + 部署 + 看日志
pwsh build\pack.ps1 -Mod MyFirstMod     # 打发布包
```

---

## 目录结构

```
ps-mod-dev/
├── .agents/skills/ps-modding/SKILL.md   ← agent 技能：自动发现，只做触发与索引
├── docs/
│   ├── 从未开始到第一个模组.md             ★ 新手从这里开始（含成功判据）
│   ├── IL2CPP-Mod-实战笔记.md              ★★ 最有价值：对象模型 / API 探测 / UI / 踩坑
│   └── Windows-环境与常见坑.md            Windows 特有问题（写保护/空格路径/steamcmd）
├── tools/Inspect/                        API 探测工具（反射读游戏代理程序集）
├── build/
│   ├── deploy.ps1                        探测游戏 → 编译 → 部署 → 看日志
│   └── pack.ps1                          打发布 zip（自动校验版本号）
├── Directory.Build.props                 12 个程序集引用都配好了，模组工程零配置
└── workspace/                            ★ 你的模组工作区（git 忽略，不污染本库）
```

---

## 你的代码放哪

放 **`workspace/`** 下 —— 该目录已在 `.gitignore` 里忽略：

- 本库始终干净，`git pull` 更新不会碰到你的代码
- 想给模组单独建仓库：在 `workspace/src/<模组>/` 里自己 `git init`

详见 [`workspace/README.md`](workspace/README.md)。

### 如果 agent 没自动加载 skill

skill 靠 `.agents/skills/ps-modding/SKILL.md` 被自动发现。若你的工具不支持，
或者你把它放在了子目录里，可以**软链到用户级技能目录**作为退路：

```powershell
# 需要开发者模式或管理员权限
New-Item -ItemType SymbolicLink `
  -Path "$env:USERPROFILE\.agents\skills\ps-modding" `
  -Target "<本库路径>\.agents\skills\ps-modding"
```

---

## 不想要 git 历史

本库已标记为 **GitHub Template Repository**，最干净的方式是用模板生成
（得到全新仓库，只有一次初始提交，不含本库历史）：

```powershell
gh repo create my-mod-dev --template MagicCrazyMan/probably-stolen-mod-dev-template --public --clone
```

其他方式：

```powershell
# 浅克隆 —— 只要最新一次提交，之后还能 git pull 拿更新
git clone --depth 1 https://github.com/MagicCrazyMan/probably-stolen-mod-dev-template ps-mod-dev

# 完全不要 git 历史
git clone --depth 1 https://github.com/MagicCrazyMan/probably-stolen-mod-dev-template ps-mod-dev
Remove-Item ps-mod-dev\.git -Recurse -Force

# 从 GitHub 直接下压缩包（连 git 都不需要）
gh api repos/MagicCrazyMan/probably-stolen-mod-dev-template/tarball/main | tar -xz
```

**两种选择的取舍：**

| | 用模板生成 | `git clone --depth 1` |
|---|---|---|
| git 历史 | ✅ 全新，只有初始提交 | ⚠️ 带本库最新一次提交 |
| 以后拿本库更新 | ❌ 与上游无关联，需手动同步 | ✅ `git pull` 即可 |

想跟着本库持续更新就用 clone，想要绝对干净的起点就用模板生成。

---

## 更新

本库会随游戏版本更新而更新（尤其是游戏打补丁后，很多结论需要重测）：

```powershell
git pull
```

因为你的代码在 git 忽略的 `workspace/` 里，`git pull` **不会冲突**。

---

## 已知边界

- **只覆盖 Demo 0.46D 的 IL2CPP 路线**。正式版上市后若为 Mono + 官方系统，
  本库的工具链需要重做（文档里已标注哪些结论是版本特定的）
- **文档里的「当前版本事实」会随游戏更新失效**。方法论、Il2Cpp 互操作坑那类结论长期有效；
  具体 API 名、类型关系需要重测
- **本库不含游戏文件**。`Assembly-CSharp.dll` 等属游戏代码，官方允许研究性反编译、
  禁止再分发，所以引用是直接从你的游戏目录读的

---

## 致谢与来源

- 游戏：[Probably Stolen – Cyberpunk Shopkeeper Sim](https://store.steampowered.com/app/4348910/)（Questing Goose Studio / tinyBuild）
- 加载器：[MelonLoader](https://github.com/LavaGang/MelonLoader) 0.7.3
- 代理程序集生成：[Cpp2IL](https://github.com/SamboyCoding/Cpp2IL) + [Il2CppInterop](https://github.com/BepInEx/Il2CppInterop)
- 官方 Mod 文档仓库（面向正式版）：[dragonpan2/probably-stolen-modding](https://github.com/dragonpan2/probably-stolen-modding)

本库非官方，与游戏开发者无关。
