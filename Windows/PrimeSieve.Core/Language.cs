namespace PrimeSieve.Core;

public sealed record Language(string Id, string Name, string Runtime, string Source, string Family,
    string Note, string[] Executables, string VersionArgument)
{
    public static readonly Language[] All =
    [
        new("assembly", "Assembly", "Windows x64 assembler", "assembly.c", "Native", "Handwritten Windows x64 assembly; C provides allocation, timing and verification.", ["clang", "gcc"], "--version"),
        new("c", "C", "Clang / GCC", "sieve.c", "Native", "", ["clang", "gcc"], "--version"),
        new("cpp", "C++", "Clang++ / G++", "sieve.cpp", "Native", "", ["clang++", "g++"], "--version"),
        new("csharp", "C#", ".NET", "sieve.cs", ".NET", "", ["dotnet"], "--version"),
        new("java", "Java", "OpenJDK", "Sieve.java", "JVM", "", ["javac"], "-version"),
        new("swift", "Swift", "Swift", "sieve.swift", "Native", "", ["swiftc"], "--version"),
        new("rust", "Rust", "rustc", "sieve.rs", "Native", "", ["rustc"], "--version"),
        new("lisp", "Common Lisp", "SBCL", "sieve.lisp", "Lisp", "", ["sbcl"], "--version"),
        new("go", "Go", "Go", "sieve.go", "Native", "", ["go"], "version"),
        new("zig", "Zig", "Zig", "sieve.zig", "Native", "Uses libc for allocation, timing and output; the sieve is Zig.", ["zig"], "version"),
        new("d", "D", "LDC", "sieve.d", "Native", "", ["ldc2"], "--version"),
        new("fortran", "Fortran", "GNU Fortran", "sieve.f90", "Native", "", ["gfortran", "gfortran-15", "gfortran-14"], "--version"),
        new("nim", "Nim", "Nim", "sieve.nim", "Native", "", ["nim"], "--version"),
        new("fsharp", "F#", ".NET", "sieve.fs", ".NET", "", ["dotnet"], "--version"),
        new("kotlin", "Kotlin", "Kotlin/JVM", "sieve.kt", "JVM", "", ["kotlinc"], "-version"),
        new("scala", "Scala", "Scala CLI", "sieve.scala", "JVM", "First compilation may download Scala dependencies.", ["scala"], "version"),
        new("clojure", "Clojure", "Clojure/JVM", "sieve.clj", "JVM", "", ["clojure"], "-Sdescribe"),
        new("haskell", "Haskell", "GHC", "sieve.hs", "Native", "", ["ghc"], "--version"),
        new("ocaml", "OCaml", "OCaml", "sieve.ml", "Native", "", ["ocamlopt"], "--version"),
        new("crystal", "Crystal", "Crystal", "sieve.cr", "Native", "", ["crystal"], "--version"),
        new("julia", "Julia", "Julia", "sieve.jl", "Dynamic", "", ["julia"], "--version"),
        new("elixir", "Elixir", "Erlang/OTP", "sieve.exs", "BEAM", "Uses an Erlang array; storage differs from mutable byte arrays.", ["elixir"], "--version"),
        new("python", "Python", "CPython", "sieve.py", "Interpreted", "", ["python", "python3"], "--version"),
        new("ruby", "Ruby", "CRuby", "sieve.rb", "Interpreted", "", ["ruby"], "--version"),
        new("javascript", "JavaScript", "Node.js", "sieve.js", "Dynamic", "", ["node"], "--version"),
        new("typescript", "TypeScript", "TypeScript → Node.js", "sieve.ts", "Dynamic", "Types are erased before execution; uses Node.js like JavaScript.", ["tsc"], "--version"),
        new("lua", "Lua", "Lua", "sieve.lua", "Interpreted", "Uses a Lua table; allocation and storage differ from byte arrays.", ["lua"], "-v"),
        new("perl", "Perl", "Perl", "sieve.pl", "Interpreted", "", ["perl"], "--version"),
        new("php", "PHP", "PHP CLI", "sieve.php", "Interpreted", "", ["php"], "--version"),
        new("r", "R", "R", "sieve.R", "Interpreted", "", ["Rscript"], "--version"),
        new("pascal", "Pascal", "Free Pascal", "sieve.pas", "Native", "", ["fpc"], "-iV"),
        new("erlang", "Erlang", "Erlang/OTP", "sieve.erl", "BEAM", "Uses an Erlang array; storage differs from mutable byte arrays.", ["escript"], "--version"),
        new("racket", "Racket", "Racket", "sieve.rkt", "Lisp", "", ["racket"], "--version"),
        new("scheme", "Scheme", "Guile", "sieve.scm", "Lisp", "", ["guile"], "--version"),
        new("groovy", "Groovy", "Groovy/JVM", "sieve.groovy", "JVM", "", ["groovy"], "--version"),
    ];
    public string SetupAdvice => Id switch
    {
        "csharp" or "fsharp" => "Install the .NET 10 SDK (the desktop runtime alone cannot compile workers).",
        "c" or "cpp" or "assembly" => "Install LLVM with C/C++ build tools, or MSYS2 UCRT64 GCC. Run from the configured developer environment if required.",
        "python" => "Install Python from python.org and add it to PATH. Windows Store app aliases are ignored.",
        "javascript" => "Install Node.js for Windows.",
        "typescript" => "Install Node.js and TypeScript (npm install -g typescript). Select Node in JavaScript setup.",
        "java" => "Install a JDK, then select javac.exe. java.exe must be in the same folder.",
        "lua" or "r" or "lisp" => "Install the Windows runtime and a C compiler for the QueryPerformanceCounter clock DLL. Lua must export its standard C API.",
        "ocaml" => "Install an OCaml Windows toolchain with its C compiler configured.",
        "scheme" => "Install Guile in MSYS2 and launch with its environment configured.",
        _ => $"Install {Runtime} for Windows and add its bin folder to PATH, or choose its executable below. Any required compiler environment must also be configured."
    };
}
public sealed record RuntimeStatus(Language Language, string? Executable, string Version)
{
    public bool Available => Executable != null;
    public string Name => Language.Name;
    public string Description => Version;
}
