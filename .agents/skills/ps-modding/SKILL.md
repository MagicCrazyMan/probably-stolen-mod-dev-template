---
name: ps-modding
description: Develop MelonLoader mods for the game Probably Stolen (深空当铺 / Probably Stolen – Cyberpunk Shopkeeper Sim) on its IL2CPP Demo build. Use when a task involves writing, building, deploying, debugging, or reverse-engineering a mod for this game: C# mod source, IMod/MelonMod entry points, Harmony patches, Il2Cpp API probing, reading the game's IL2CPP interop assemblies, CustomUI configuration windows, inspecting game types with tools/Inspect, or diagnosing mod-load failures from MelonLoader logs.
---

# Probably Stolen modding (IL2CPP / MelonLoader)

The current public build is **Demo 0.46D — Unity 2021.3.45f2, IL2CPP**, and the game's own
mod loader is disabled (`Player.log`: `[ModLoader] Limited build: mod loading disabled.`).
So the official Mono modding guide does **not** apply. Follow what is in this repo, not that guide.

## Do these three things first

1. **Do not write code from the official ModdingGuide.** This build lacks a large part of its
   API (`SetModData`, `AddLootEntry`, `PlaySound`, `SetSpriteAndShapeFromMod`, `ModScanner`,
   `Capabilities`, …). **Probe the real assemblies before writing anything.**
2. **Target `net6.0`, not `netstandard2.1`.** References come from
   `MelonLoader\net6\` + `MelonLoader\Il2CppAssemblies\` in the game folder; they are
   already wired up in the root `Directory.Build.props`. Never override `<Private>false</Private>`.
3. **Read `docs/IL2CPP-Mod-实战笔记.md` before any non-trivial change.** It carries the game's
   object model, the API-probing method, the UI framework, and a 9-item pitfalls list.

## Probe the API this way

```powershell
$env:PS_GAME_ASM_DIR = "$game\MelonLoader\Il2CppAssemblies"
dotnet tools\Inspect\bin\Release\net6.0\Inspect.dll find 'Sort|Inventory'      # 类型名正则搜索
dotnet tools\Inspect\bin\Release\net6.0\Inspect.dll show <Type> <成员正则>      # 看成员签名
dotnet tools\Inspect\bin\Release\net6.0\Inspect.dll base <Type>                # 看继承链
```

Never enumerate interop types with `Assembly.LoadFrom` + `AppDomain.AssemblyResolve`
**inside PowerShell** — it intercepts PowerShell's own module loading and crashes the process.
Use the compiled tool above.

## Three pitfalls that cost the most time

- **`Il2Cpp.GameInventory` is not a Component.** It derives from `Il2CppObjectBase`
  (no `gameObject` / `transform`), so `GetComponent*` can never find it. Interface nodes form an
  **element graph**: get the hit node, then `node.FindParentElement<T>()`.
- **Callbacks and lists must be Il2Cpp types.** `Il2CppSystem.Action<T>` is not
  `System.Action<T>` — wrap with `DelegateSupport.ConvertDelegate<TIl2Cpp>(netDelegate)`.
  `Il2Cpp`'s `List<T>` / `Il2CppReferenceArray<T>` do not satisfy some `IList<T>` parameters.
- **MelonLoader owns `UserData\MelonPreferences.cfg`.** It rewrites the file on game exit, and
  a value already written there is *never* replaced by a new code default — a stale
  `RequireCtrl = true` once silently disabled an entire feature. When you change a default,
  delete an entry, or rename it, clean the player-side config too.

## Where to read more

| Need | Read |
|---|---|
| First mod, step by step | `docs/从未开始到第一个模组.md` |
| Build / deploy / package commands | `README.md`, `build/deploy.ps1`, `build/pack.ps1` |
| Game object model, API probing, UI, pitfalls | `docs/IL2CPP-Mod-实战笔记.md` |
| Windows toolchain notes (partly superseded) | `docs/Windows-环境清单.md` |

Put mod source under `workspace/` (git-ignored, so this repo stays clean).
Build and deploy with `pwsh build\deploy.ps1 -Deploy -Log`.
