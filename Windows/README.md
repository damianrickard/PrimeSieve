# PrimeSieve for Windows

A native C# / WPF Windows desktop version of PrimeSieve, targeting .NET 10. The Swift/macOS application remains separate. The Windows application uses the existing language workers, with Windows-specific clock and assembly files in `Workers`.

## Build and run

Install the **.NET 10 SDK** on Windows, then run from the repository root:

```powershell
dotnet build Windows/PrimeSieve.slnx -c Release
dotnet run --project Windows/PrimeSieve.App -c Release
```

Open `Windows/PrimeSieve.slnx` in an editor supporting .NET 10. Build the portable, self-contained x64 app with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Windows/scripts/build.ps1
```

The execution-policy option applies only to that PowerShell process; it does not change the machine policy. This runs the regression executable, publishes to `Windows/artifacts/win-x64`, and creates a ZIP plus SHA-256 checksum. Extract the **whole folder**, then launch `PrimeSieve.exe`. The package includes the .NET desktop runtime, but language SDKs and interpreters are installed separately. The package is unsigned; no Microsoft signing or public release is implied. A successful replacement preserves the previous package in a timestamped folder. An ARM64 build can be requested with `-Runtime win-arm64`; the assembly worker is disabled there, and ARM64 execution has not been validated.

## Using the app

1. Select detected languages in the sidebar. **All ready** selects the detected runtimes; **Refresh** checks again after installation.
2. Choose first-N (1–10,000,000) or inclusive upper-limit (2–200,000,000), baselines/tuned/all, 1–30 samples per round, 1–10 rounds, and warm-ups.
3. Choose **Calculation**, **Startup + calculation**, or **Sieve throughput**, then start. The Drag Race preset uses a one-million limit and three five-second windows. Implementations run sequentially, shuffled each round. Rankings update after each complete round. **Cancel** terminates the running worker and keeps only the last complete round's accumulated samples; the unfinished round is discarded, including all ranked results if cancelled in round one.
4. Results rank median latency or median passes/second and display IQR, sample counts and relative scores. Filter byte or packed storage. Select **Details**, double-click a result, or press Enter to inspect raw timings, compilation time, source hashes, commands and helper tools.
5. Export JSON or CSV, reopen a comparison from History, or clear history after confirmation. Current results and exports survive clearing.
6. Browse all 35 baselines and eight named variants in **Code explorer**, including languages not installed. Excerpts come directly from the bundled calculation markers, with copying, font-size controls, and horizontal scrolling.
7. **Language setup** provides runtime guidance and custom executable paths. Saving paths triggers a fresh discovery before another run. Missing explicit paths never silently fall back to another tool.

Closing during runtime discovery cancels its active probe and closes after cleanup. Saved results from an unknown language remain readable in Details; unavailable calculation-code navigation is disabled.

The shared [v3 measurement contract](../README.md#measurement-contract-v3) defines the timing boundaries, correctness checks, registry metadata and history versioning. Throughput currently supports the pilot Python/R/Swift/Fortran/assembly variants; unsupported baseline combinations fail visibly. Windows history remains a separate schema.

## Windows runtimes and measurement rules

The full 35-language roster and build/launch recipes are present. **Detected** means a version probe succeeded, not that its compiler environment has passed an integration test. A selected worker must compile and return independently verified results before joining the leaderboard. Missing prerequisites and compilation failures are shown in the results and recorded in JSON; they are never replaced with C# timings.

- C and assembly use `QueryPerformanceCounter`; Windows x64 assembly follows the Microsoft calling convention. C/C++ recipes accept Clang or GCC and require a working Windows C/C++ development environment. MSVC `cl.exe` is not a supported direct selection.
- .NET workers use the selected SDK (6 or later). C# and F# share the installed SDK by default; their settings may select different SDK executables.
- Java selection determines the JVM used by the JVM family. Discovery asks that JVM for its actual JDK home and validates both Java tools, including when the launcher is an Oracle javapath shim or a directory link. TypeScript compilation and execution explicitly use the selected Node executable.
- Lua, R, Common Lisp and OCaml use Windows clock bridges. Lua requires a build that exports the standard C API and uses double-precision `lua_Number`. Lua and BEAM workers retain their disclosed storage differences. Guile and some native toolchains may require an MSYS2 or developer-shell environment.
- Batch launchers (`.cmd` / `.bat`) are supported with guarded quoting. Shell metacharacters in their paths or arguments are rejected visibly. Direct executable arguments use Windows C runtime quoting.
- Runtime versions, helper versions, commands, worker sources and version-2 source-manifest hashes are recorded. Windows-specific source hashes can legitimately differ from macOS.
- Calculation timing includes fresh allocation, initialization, composite marking and scanning, but excludes checksums and output. Startup timing launches a fresh process per sample, includes checksums and output, excludes compilation and uses no warm-ups. Process-launch timing includes the coordinator's Windows process containment overhead.
- Benchmark and discovery work run away from the UI thread, so startup samples do not wait for UI dispatch. Windows Job Objects contain workers from process creation, before they can launch descendants; cancellation and timeouts terminate the job. This uses Windows 10 or newer process attributes. Output capture is bounded to one million characters per stream by default; full-sequence worker verification allows four million stdout characters to fit 30 samples. Temporary workspaces are unique and cleaned after runs; files locked by third-party tools may remain in `%TEMP%`.
- Each sample must match an independent full-number reference sieve's count, last prime and modular checksum. Mean and median include only measured iterations. Checksum equality is not proof of an identical prime sequence; small timing differences are not definitive wins.

History and runtime paths are stored in `%LOCALAPPDATA%\PrimeSieve`. Damaged or unreadable runtime settings produce a visible warning and allow automatic discovery; the original file is preserved. Null, blank and relative path entries are ignored with warnings. JSON saves are replaced atomically. CSV includes raw samples and provenance and neutralizes formula-like metadata. Windows history uses ISO date strings and its own schema; importing macOS history is not implemented.

## Validation

```powershell
dotnet run --project Windows/PrimeSieve.Tests -c Release
dotnet run --project Windows/PrimeSieve.Tests -c Release -- --integration
dotnet run --project Windows/PrimeSieve.UiTests -c Release
dotnet run --project Windows/PrimeSieve.Cli -c Release -- list
dotnet run --project Windows/PrimeSieve.Cli -c Release -- verify
dotnet run --project Windows/PrimeSieve.Cli -c Release -- run --count 10000 --iterations 3 --startup --output results.json
```

The dependency-free regression executable covers reference values, configuration limits, malformed worker responses, statistics, all 35 code excerpts, source manifests, history, CSV, damaged runtime settings and registries, JVM shim/link fixtures, timeouts, cancellation, process arguments, Windows batch quoting, fast exits and child-process termination after a parent exits. With Python available, it checks cancellation in the first and second rounds and preserves only complete-round samples. `--integration` additionally checks startup/discovery with caller UI dispatch blocked and cancellation during the first round; it requires at least two detected runtimes. `verify` tests all detected workers at N=1, 2, 5 and 1,000.

`PrimeSieve.UiTests` runs only on Windows and drives real WPF windows with isolated temporary history. It checks closing during startup/refresh discovery, termination of an active slow probe, opening unknown-language result details, preservation of saved metadata, and normal code navigation for known languages. The packaging script runs these checks before publishing.

A built application accepts an opt-in UI check in an **interactive Windows session**:

```powershell
.\PrimeSieve.exe --smoke-test C:\path\to\ui-evidence
```

It runs 10,000-prime calculation/startup comparisons and a two-round, limit-1024 throughput comparison through the UI, saves JSON/CSV, exercises history and the code explorer, captures rendered PNGs and writes `ui-smoke.json`. This check uses isolated settings/history in the evidence folder's `state` subfolder. To verify recovery, place malformed JSON in `state/runtimes.json` before launching and check `preferencesWarning` in the report. Normal launches never run benchmarks automatically.

### Validation scope on bob

Windows x64, .NET SDK 10.0.303: Release build and regression checks run directly on bob. C#, F#, Python 3.13 and JavaScript/Node 24 are installed and have been checked end to end. The other 31 toolchains are not installed there, so their Windows recipes/adaptations remain unverified on that machine. No performance claim across operating systems follows from these functional checks.

## Layout

- `PrimeSieve.App`: native WPF interface, runtime setup and interactive smoke check.
- `PrimeSieve.Core`: runtime discovery, Windows process containment, builds, verification, history and exports.
- `PrimeSieve.Cli`: list, verify and benchmark commands using the same coordinator.
- `PrimeSieve.Tests`: dependency-free regression and cancellation integration executable.
- `PrimeSieve.UiTests`: Windows-only WPF lifecycle and history-details regression executable.
- `Workers`: Windows-only source overrides; all unchanged workers are packaged directly from the existing Swift resource folder.
- `scripts/build.ps1`: tested self-contained portable packaging.

The Windows CLI also accepts `implementations`, `--limit`, `--variants baseline|tuned|all`, `--implementations id,id`, `--mode calculation|startup|throughput`, `--seconds`, `--rounds`, and `--drag-race`. Windows uses `--iterations` where the Swift CLI uses `--repetitions`. Run `python scripts/validate-variants.py --output boundary-results.json` to check all installed pilot toolchains; `--require-all` makes missing tools a failure.
