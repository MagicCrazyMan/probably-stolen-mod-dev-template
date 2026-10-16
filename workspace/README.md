# workspace/ —— 你的模组工作区

**这个目录被 `.gitignore` 忽略了** —— 你在这里写的东西不会进模板库，
模板库更新（`git pull`）也不会碰你的代码。

## 怎么开始

```
workspace/
├── src/
│   └── MyFirstMod/          ← 每个模组一个子目录
│       ├── MyFirstMod.csproj
│       ├── MyFirstMod.cs
│       └── README.txt       ← 使用者说明，pack.ps1 会打进发布包
└── dist/                    ← 构建/打包产物（也可忽略）
```

照着 [`../docs/从未开始到第一个模组.md`](../docs/从未开始到第一个模组.md) 做一遍就有骨架了。

## 常用命令（在库根目录执行）

```powershell
# 构建 + 部署到游戏 Mods\ + 打印 MelonLoader 日志
pwsh build\deploy.ps1 -Deploy -Log

# 只构建某个模组
pwsh build\deploy.ps1 -Mod MyFirstMod

# 打发布 zip → workspace/dist/MyFirstMod-v1.0.0.zip
pwsh build\pack.ps1 -Mod MyFirstMod
```

## 想给模组单独建 git 仓库？

在 `workspace/src/MyFirstMod/` 里自己 `git init` 就行 —— 它和模板库的 git
不冲突（这个目录整个被忽略了）。

**建议一开始就写好下面那份出处说明** —— 事后补写往往已经忘了基线是哪个版本。

## 为什么不让模组代码进模板库

模板库是**可复用的知识与工具**（skill、文档、探测工具、构建脚本），
不是某个具体模组的家。分开之后：

- 游戏更新 → 更新模板库 → 所有开发者 `git pull` 拿到新知识
- 你的模组代码始终是你自己的

---

## ⚠️ 要分享模组源码时，务必说明它基于本模板库构建

### 为什么必须说明

**你的模组工程本身不完整。** 它依赖模板库提供两样东西：

| 依赖 | 由谁提供 |
|---|---|
| 十几个程序集引用（MelonLoader / 0Harmony / Il2CppInterop / Assembly-CSharp / UnityEngine.*） | 模板库根目录的 `Directory.Build.props` |
| 目标框架与构建配置（`net6.0`、`NoWarn` 等） | 同上 |

所以别人只拿到 `workspace/src/MyMod/` 是**构建不出来的** —— 一编译就会撞上：

```
error PS002: MelonLoader 引用程序集不完整
```

或者自己乱加引用，然后踩上一堆坑（`Private` 没设、程序集同名冲突、目标框架选错）。
**告诉他「这是基于 probably-stolen-mod-dev-template 建的」，他 clone 一次就全有了。**

### 顺带一提：不说明还会丢可复现性

模板库会随游戏更新而变（例如某次改动了目标框架或引用清单）。
只给源码不说基线，别人可能在**不同版本的模板库**上试，行为不一致还很难查。

### 建议的做法

在你的模组目录里放一份出处说明（例如 `BUILD.md`），**直接抄下面这个模板**：

```markdown
# <模组名> —— 构建说明

本模组基于 **probably-stolen-mod-dev-template** 构建：
https://github.com/MagicCrazyMan/probably-stolen-mod-dev-template

- 基线提交：`<填 git rev-parse HEAD 的输出>`
- 目标框架：`net6.0`（MelonLoader + IL2CPP 路线）
- 开发时的游戏版本：`0.46D`（`VERSION 049-Rev5-L`）

## 怎么构建

1. clone 模板库，并让它成为你的工作区根：
   `git clone https://github.com/MagicCrazyMan/probably-stolen-mod-dev-template ps-mod-dev`
2. 把本模组目录放进 `workspace/src/`
3. 在模板库根目录执行：
   `pwsh build\deploy.ps1 -Deploy -Log`

程序集引用由模板库的 `Directory.Build.props` 提供，**不要在本模组工程里另加**。

## 本模组特有的前置条件

<例如依赖某个框架模组、需要特定的游戏版本、需要额外资源文件……没有就删掉这节>

## 出处说明

<是谁做的、基于什么、遇到问题找谁>
```

**同时在使用者说明 `README.txt` 里也提一句** —— 使用者虽然不需要构建，
但当他们想自己改、或者你停止维护时，这个出处就是他们唯一的线索。

### 怎么拿基线提交

```powershell
git -C <模板库路径> rev-parse HEAD
```
