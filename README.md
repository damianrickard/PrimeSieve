# PrimeSieve

A native macOS application written in SwiftUI that compares the time taken to calculate the **first N prime numbers** in 35 programming languages. Requires macOS 14 or later. Benchmarks run locally in independent processes.

Download the **Developer ID signed and Apple-notarized** Apple Silicon app from [GitHub Releases](https://github.com/damianrickard/PrimeSieve/releases/latest). Extract the ZIP and drag PrimeSieve into Applications. macOS may still show its normal first-open confirmation for an internet download.

## Windows version

A native C# / WPF version is available in [`Windows`](Windows/README.md), with local benchmarks, runtime setup, history, exports and the 35-language code explorer. Build with the .NET 10 SDK. See the Windows guide for packaging, toolchain requirements and the Windows validation scope.

## Build and launch

```sh
./scripts/build-app.sh
open dist/PrimeSieve.app
```

The script produces a locally signed application. Distribution signing and notarization are separate release tasks. Full Xcode is recommended for running the XCTest suite; Command Line Tools can build the app using the native SwiftPM build system.

For public distribution, set `SIGNING_IDENTITY` to an installed **Developer ID Application** identity when running `scripts/build-app.sh`. This enables hardened runtime and secure timestamping. Each build assembles a fresh app bundle and verifies its signature before replacing `dist/PrimeSieve.app`; a failed build preserves the previous app.

Configure notarization credentials locally with `xcrun notarytool store-credentials` and keep credentials out of the repository. Then run `./scripts/notarize-app.sh KEYCHAIN_PROFILE`, using the profile name you saved. The script submits a copy, requires Apple's Accepted status, staples and validates the ticket, and checks Gatekeeper before producing a ZIP and SHA-256 checksum in the reported `dist/notarization.*` folder. Publish that ZIP, rather than the unstapled input app. If submission times out, inspect the saved submission ID and query it with `notarytool info` or `notarytool wait` before submitting again; the service may still be processing it.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --build-system native
swift build --build-system native --product primesieve-cli
.build/debug/primesieve-cli list
.build/debug/primesieve-cli verify
.build/debug/primesieve-cli run --languages assembly,c,cpp,swift,pascal \
  --count 100000 --repetitions 7 --warmups 3 --output results.json
```

`verify` runs every available language at 1, 2, 5 and 1,000 primes and checks every measurement against an independent reference. Tests can require the full roster using `PRIMESIEVE_REQUIRE_ALL=1`. No test result is an assertion that one language is universally faster than another.

## Using the application

1. Select installed languages in the sidebar. **All ready** selects every detected runtime.
2. Enter the number of primes, or select a preset.
3. Choose **Calculation** or **Startup + calculation** and select **1–30 iterations** per language in the main panel. Advanced settings control warm-ups and the worker timeout.
4. Start the comparison. Verified results appear in ascending median-time order as workers finish. Cancellation keeps completed results.
5. Open a language's result for its iteration count, mean, median, individual measurements, and compiler settings. Export CSV or JSON, or reopen a saved comparison from History.
6. Open **Code explorer** to browse the documented prime-calculation sections for all 35 languages. The explorer reads excerpts directly from the bundled worker sources and hides timing, command-line parsing, checksum verification, and output. It works without installing a runtime. Assembly includes both ARM64 and x86-64 kernels. Result details also open the explorer at the selected language.
7. Choose **History → Clear History…** to delete saved comparisons after confirmation. Results currently on screen and exported files are kept. Clearing is disabled during a comparison and when history is empty.

Each worker documents allocation, composite marking, and scanning to the Nth prime. Horizontal scrolling preserves code indentation; text size and Copy code are available in the explorer. These are excerpts within the worker's surrounding scope, rather than standalone programs. The interface uses international orange (`#FF4F00`).

The Language Setup panel shows installation suggestions and lets you choose custom executable paths. Runtime detection prefers known Homebrew, Cargo, Java and Julia locations ahead of system fallbacks, giving Finder and terminal launches the same default choices. Explicit executable selections take precedence; a missing custom executable is reported rather than silently replaced. Changes made during discovery queue another refresh before a comparison can start. Java selections also control the JVM used by Kotlin, Scala, Groovy and Clojure. The JavaScript selection controls Node for TypeScript compilation and execution; the C selection controls the Lua, R and Common Lisp clock-shim compiler. Helper paths and versions are shown in result details and exports. Toolchains are not bundled into the application. Compiled workers are built in a temporary directory and removed after each comparison; compilation time is recorded separately.

## Languages

Assembly, C, C++, C#, Java, Swift, Rust, Common Lisp, Go, Zig, D, Fortran, Nim, F#, Kotlin, Scala, Clojure, Haskell, OCaml, Crystal, Julia, Elixir, Python, Ruby, JavaScript, TypeScript, Lua, Perl, PHP, R, **Pascal**, Erlang, Racket, Scheme and Groovy.

Most dependencies can be installed using Homebrew:

```sh
brew install fpc typescript rust sbcl openjdk dotnet go zig ldc gcc nim ghc \
  ocaml crystal julia elixir scala clojure kotlin php r erlang guile groovy minimal-racket
```

Apple Command Line Tools provide assembly, C, C++ and Swift. The app checks executable versions before marking a runtime ready, then builds and verifies its worker when used. Some JVM tools may download dependencies during their first build. Homebrew OpenJDK is detected directly without changing system Java registration.

## Measurement contract

- Calculate the first N primes beginning with 2; N is restricted to 1–10,000,000.
- Use an odd-only Sieve of Eratosthenes with a common conservative search bound supplied by the coordinator.
- Include fresh buffer allocation, initialization, marking composites and scanning to the Nth prime in calculation timing.
- Exclude correctness checks, serialization, printing and compilation from calculation timing. Workers execute warm-ups and measured repetitions in the same process.
- Startup mode launches a fresh prepared worker for each measurement and includes process startup, calculation, checksum computation and output. It does not warm up or include compilation. Script runtimes that compile while loading include that loading cost in startup mode.
- Use monotonic clocks. Timer resolution differs between runtimes, so very small workloads may report zero or identical measurements.
- Run one language worker at a time and shuffle language order per comparison. Repetitions for a language are consecutive; order is not shuffled between individual samples. Background activity, CPU scheduling and temperature can still affect results.
- Use optimized release builds for ahead-of-time compiled languages. Guile Scheme is compiled to bytecode during preparation, before either timing mode. Clojure uses primitive arithmetic and direct byte-array access, with boxing and reflection diagnostics enabled. Flags and runtime versions are recorded with each result. C# and F# support .NET SDK 6 or newer; build-server flags are enabled only on SDK 7 or newer.
- The assembly kernel performs marking and scanning in handwritten assembly. Its C harness supplies allocation, monotonic timing, checksum verification and output.
- Use mutable byte storage where available. Lua uses a table; Erlang and Elixir use persistent Erlang arrays. These differences are disclosed in the setup and results views. TypeScript runs emitted JavaScript through Node.js.
- Compare each measurement's prime count, last prime and modular sum checksum against an independent full-number reference sieve. This catches common implementation failures but a checksum is not a mathematical proof of an identical prime sequence.

The leaderboard ranks medians and shows the arithmetic mean, minimum/maximum measurements and relative times. Both mean and median use only measured iterations, excluding warm-ups. With one iteration, mean and median equal that single measurement. CSV and JSON exports include iteration counts, mean, median, and raw samples; older saved comparisons derive the new statistics from their existing samples. Small differences should not be treated as definitive wins. There are no GPU, external prime-library or parallel sieve implementations in this roster. Runtime housekeeping threads may still exist.

## Data and project layout

Saved sessions live in `~/Library/Application Support/PrimeSieve/Sessions`. They contain configuration, machine/OS architecture, all measured timings, runtime paths and versions, source SHA-256 hashes, compiler or launch commands, and failures. Custom runtime paths are stored in application preferences. The app does not send benchmark results anywhere.

Source hashes use a versioned, length-prefixed manifest of file names and contents. Each manifest contains the worker source plus only its required assembly or clock support files; .NET manifests also include the generated project settings. Format 2 hashes cannot be compared directly with hashes in older sessions, which included unrelated helpers. Older saved results remain readable, with newly recorded helper metadata absent.

- `Sources/PrimeSieveApp`: SwiftUI interface and application state.
- `Sources/PrimeSieveCore`: runtime registry, process execution, benchmark coordination, correctness reference and local exports.
- `Sources/PrimeSieveCore/Resources/Workers`: implementations and clock/assembly support files.
- `Sources/PrimeSieveCLI`: command-line diagnostics, verification and benchmarking using the same coordinator.
- `Tests/PrimeSieveCoreTests`: correctness, protocol, process timeout/cancellation, toolchain resolution, provenance and integration checks.
- `Tests/PrimeSieveAppTests`: runtime-refresh race regression coverage.
- `scripts/build-app.sh`: reproducible macOS application packaging.
- `Assets/AppIcon.png`: graphite and international-orange app icon; the build generates all macOS icon sizes with `scripts/build-icon.sh`.

Apple Silicon is the initial validation platform. An Intel assembly kernel is included; Intel execution requires separate hardware validation.
