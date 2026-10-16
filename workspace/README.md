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

## 为什么不让模组代码进模板库

模板库是**可复用的知识与工具**（skill、文档、探测工具、构建脚本），
不是某个具体模组的家。分开之后：

- 游戏更新 → 更新模板库 → 所有开发者 `git pull` 拿到新知识
- 你的模组代码始终是你自己的
