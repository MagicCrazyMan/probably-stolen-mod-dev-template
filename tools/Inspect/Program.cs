using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Text;

namespace PsInspect
{
    /// <summary>
    /// 反射查看游戏代理程序集（Il2CppAssemblies）里的真实类型与签名。
    ///
    /// 为什么要这个工具：游戏类型在 Il2Cpp 命名空间下，成员签名靠猜很容易错；
    /// 用 PowerShell + Assembly.LoadFrom 去枚举还会把 PowerShell 自己搞崩。
    /// 这里用独立进程 + 正确的工作目录，反射结果是权威的。
    ///
    /// 用法：
    ///   Inspect.exe find &lt;正则&gt;                      按类型名搜索，打印参数/返回类型
    ///   Inspect.exe show &lt;类型名&gt; [成员正则]          打印该类型的成员
    ///   Inspect.exe base &lt;类型名&gt;                     打印继承链
    /// </summary>
    internal static class Program
    {
        private const string GameAsm = "Assembly-CSharp";

        /// <summary>
        /// 定位游戏代理程序集。优先用环境变量 PS_GAME_ASM_DIR，其次用本 exe 所在目录。
        /// 用 LoadFrom 显式路径比 Load(名字) 可靠 —— 后者依赖探测路径，容易找不到。
        /// </summary>
        private static Assembly LoadGameAssembly(string name)
        {
            var dir = Environment.GetEnvironmentVariable("PS_GAME_ASM_DIR");
            if (string.IsNullOrEmpty(dir)) dir = AppContext.BaseDirectory;
            var path = System.IO.Path.Combine(dir, name + ".dll");
            if (!System.IO.File.Exists(path))
                throw new System.IO.FileNotFoundException($"找不到 {path}");
            return Assembly.LoadFrom(path);
        }

        /// <summary>
        /// 解析依赖：Il2CppInterop.Runtime 等不在同目录时从 MelonLoader\net6 找。
        /// 这个 handler 只在独立进程里装，绝不要在 PowerShell 里做同样的事
        /// （会连 PowerShell 自身的模块加载一起拦，直接崩）。
        /// </summary>
        private static void HookResolver()
        {
            AppDomain.CurrentDomain.AssemblyResolve += (s, e) =>
            {
                var simple = new AssemblyName(e.Name).Name;
                foreach (var d in CandidateDirs())
                {
                    var p = System.IO.Path.Combine(d, simple + ".dll");
                    if (System.IO.File.Exists(p)) { try { return Assembly.LoadFrom(p); } catch { } }
                }
                return null;
            };
        }

        private static int Main(string[] args)
        {
            Console.OutputEncoding = Encoding.UTF8;

            // 允许 -asm <名字> 指定要查看的代理程序集（默认 Assembly-CSharp）
            string asmName = GameAsm;
            var rest = new List<string>();
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "-asm" && i + 1 < args.Length) { asmName = args[++i]; }
                else rest.Add(args[i]);
            }
            args = rest.ToArray();

            if (args.Length == 0) { Usage(); return 2; }

            HookResolver();

            Assembly game;
            try { game = LoadGameAssembly(asmName); }
            catch (Exception e)
            {
                Console.Error.WriteLine($"加载 {asmName} 失败：{e.Message}");
                Console.Error.WriteLine("提示：本 exe 需要和 Il2CppAssemblies\\*.dll 放在同一目录，");
                Console.Error.WriteLine("      或用环境变量 PS_GAME_ASM_DIR 指向该目录。");
                return 3;
            }

            try
            {
                switch (args[0].ToLowerInvariant())
                {
                    case "find": return CmdFind(game, args.ElementAtOrDefault(1) ?? ".");
                    case "show": return CmdShow(game, args.ElementAtOrDefault(1), args.ElementAtOrDefault(2));
                    case "base": return CmdBase(game, args.ElementAtOrDefault(1));
                    default: Usage(); return 2;
                }
            }
            catch (ReflectionTypeLoadException e)
            {
                Console.Error.WriteLine("类型加载失败（依赖缺失）：");
                foreach (var le in e.LoaderExceptions.Where(x => x != null).Take(5)) Console.Error.WriteLine("  " + le.Message);
                return 4;
            }
        }

        private static IEnumerable<string> CandidateDirs()
        {
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var list = new List<string>();
            void Add(string d)
            {
                if (string.IsNullOrEmpty(d) || !System.IO.Directory.Exists(d)) return;
                if (seen.Add(d)) list.Add(d);
            }
            string Sib(string baseDir, string name)
            {
                try { return System.IO.Path.GetFullPath(System.IO.Path.Combine(baseDir, "..", name)); }
                catch { return null; }
            }

            var asmDir = Environment.GetEnvironmentVariable("PS_GAME_ASM_DIR");
            Add(asmDir);
            Add(AppContext.BaseDirectory);

            // 关键：Il2CppInterop.Runtime / MelonLoader / Il2Cppmscorlib 的依赖不在
            // Il2CppAssemblies 里，而在它的兄弟目录 ..\net6。
            // 工具从仓库里就地运行时（不在游戏目录下），这一步是必须的。
            if (!string.IsNullOrEmpty(asmDir))
            {
                Add(Sib(asmDir, "net6"));
                Add(Sib(asmDir, "net472"));
                Add(Sib(asmDir, "net35"));
            }
            Add(Sib(AppContext.BaseDirectory, "net6"));

            return list;
        }

        private static void Usage()
        {
            Console.WriteLine("用法：");
            Console.WriteLine("  Inspect.exe find <类型名正则>");
            Console.WriteLine("  Inspect.exe show <类型名> [成员名正则]");
            Console.WriteLine("  Inspect.exe base <类型名>");
        }

        /// <summary>短类型名，泛型会展开成 List&lt;GameItem&gt; 这种可读形式。</summary>
        private static string TN(Type t)
        {
            if (t == null) return "?";
            if (t.IsByRef) return TN(t.GetElementType()) + "&";
            if (t.IsArray) return TN(t.GetElementType()) + "[]";
            if (t.IsGenericType)
            {
                var name = t.Name.Contains('`') ? t.Name.Substring(0, t.Name.IndexOf('`')) : t.Name;
                return $"{name}<{string.Join(", ", t.GetGenericArguments().Select(TN))}>";
            }
            return t.Name;
        }

        private static Type FindType(Assembly asm, string name)
        {
            var types = SafeTypes(asm);
            return types.FirstOrDefault(t => t.Name == name)
                ?? types.FirstOrDefault(t => t.FullName == name)
                ?? types.FirstOrDefault(t => t.Name.EndsWith(name, StringComparison.OrdinalIgnoreCase));
        }

        private static Type[] SafeTypes(Assembly asm)
        {
            try { return asm.GetTypes(); }
            catch (ReflectionTypeLoadException e)
            {
                // 别静默吞掉：类型加载失败通常意味着依赖解析不出来，
                // 那样 find/show 会显示「0 个类型」而完全看不出原因。
                var ok = e.Types.Where(t => t != null).ToArray();
                if (ok.Length == 0)
                {
                    Console.Error.WriteLine("⚠️ 一个类型都没加载成功，依赖解析大概率失败了：");
                    Console.Error.WriteLine($"   PS_GAME_ASM_DIR = {Environment.GetEnvironmentVariable("PS_GAME_ASM_DIR") ?? "(未设置)"}");
                    foreach (var d in CandidateDirs()) Console.Error.WriteLine($"   已尝试依赖目录: {d}");
                    foreach (var le in e.LoaderExceptions.Where(x => x != null).Take(3))
                        Console.Error.WriteLine($"   {le.GetType().Name}: {le.Message}");
                }
                return ok;
            }
        }

        private static int CmdFind(Assembly asm, string pattern)
        {
            var re = new System.Text.RegularExpressions.Regex(pattern, System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            var hits = SafeTypes(asm).Where(t => re.IsMatch(t.Name)).OrderBy(t => t.Name).ToList();
            Console.WriteLine($"匹配 {hits.Count} 个类型：");
            foreach (var t in hits)
            {
                Console.WriteLine($"\n  {t.Namespace}.{TN(t)}   [接口={t.IsInterface} 抽象={t.IsAbstract} 枚举={t.IsEnum}]");
                foreach (var p in t.GetProperties(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly))
                    Console.WriteLine($"      属性 {TN(p.PropertyType)} {p.Name}");
                foreach (var f in t.GetFields(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly))
                    Console.WriteLine($"      字段 {TN(f.FieldType)} {f.Name}");
                foreach (var m in t.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly)
                                   .Where(m => !m.IsSpecialName))
                    Console.WriteLine($"      方法 {(m.IsStatic ? "static " : "")}{TN(m.ReturnType)} {m.Name}({string.Join(", ", m.GetParameters().Select(p => TN(p.ParameterType) + " " + p.Name))})");
            }
            return 0;
        }

        private static int CmdShow(Assembly asm, string typeName, string memberPattern)
        {
            if (typeName == null) { Usage(); return 2; }
            var t = FindType(asm, typeName);
            if (t == null) { Console.Error.WriteLine($"找不到类型：{typeName}"); return 1; }
            System.Text.RegularExpressions.Regex re = memberPattern == null
                ? null
                : new System.Text.RegularExpressions.Regex(memberPattern, System.Text.RegularExpressions.RegexOptions.IgnoreCase);

            Console.WriteLine($"类型 {t.FullName}  (base={t.BaseType?.FullName})");
            foreach (var p in t.GetProperties(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static)
                               .Where(p => re == null || re.IsMatch(p.Name)))
                Console.WriteLine($"  属性 {TN(p.PropertyType)} {p.Name}   [get={(p.GetMethod != null)} set={(p.SetMethod != null)}]");
            foreach (var f in t.GetFields(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static)
                               .Where(f => re == null || re.IsMatch(f.Name)))
                Console.WriteLine($"  字段 {TN(f.FieldType)} {f.Name}");
            foreach (var m in t.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static)
                               .Where(m => !m.IsSpecialName && (re == null || re.IsMatch(m.Name))))
                Console.WriteLine($"  方法 {(m.IsStatic ? "static " : "")}{TN(m.ReturnType)} {m.Name}({string.Join(", ", m.GetParameters().Select(p => TN(p.ParameterType) + " " + p.Name))})");
            return 0;
        }

        private static int CmdBase(Assembly asm, string typeName)
        {
            if (typeName == null) { Usage(); return 2; }
            var t = FindType(asm, typeName);
            if (t == null) { Console.Error.WriteLine($"找不到类型：{typeName}"); return 1; }
            for (var cur = t; cur != null; cur = cur.BaseType)
                Console.WriteLine($"  {cur.FullName}   (asm={cur.Assembly.GetName().Name})");
            Console.WriteLine("  接口：" + string.Join(", ", t.GetInterfaces().Select(i => i.FullName)));
            return 0;
        }
    }
}
