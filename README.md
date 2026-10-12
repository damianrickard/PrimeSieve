# PrimeSieve

A native macOS application written in SwiftUI that compares verified prime-sieve implementations in **35 programming languages**, with first-N and inclusive upper-limit workloads. Requires macOS 14 or later. Benchmarks run locally in independent processes.

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
2. Choose **First N primes** or **Primes up to limit**, and enter the count or inclusive upper limit.
3. Choose **Calculation**, **Startup + calculation**, or **Sieve throughput**. Select baselines, tuned variants, or both. Advanced settings control warm-ups, randomized rounds, window duration and timeout. **Drag Race preset** selects the five supported languages, an inclusive limit of 1,000,000, and three five-second windows.
4. Start the comparison. Latency ranks lower median times; throughput ranks higher median passes/second. Storage filters separate byte and packed-bit variants. Rankings update after each complete round. Cancellation keeps the last complete round's accumulated samples and discards the unfinished round; cancellation in round one leaves no ranked results.
5. Open a language's result for its iteration count, mean, median, individual measurements, and compiler settings. Export CSV or JSON, or reopen a saved comparison from History.
6. Open **Code explorer** to browse the documented prime-calculation sections for all 35 baselines and eight named variants. The explorer reads excerpts directly from the bundled worker sources and hides timing, command-line parsing, checksum verification, and output. It works without installing a runtime. Assembly includes both ARM64 and x86-64 kernels. Result details also open the explorer at the selected language.
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

## Measurement contract (v3)

- **First N primes:** find 1–10,000,000 primes starting at 2 using a common conservative bound. **Upper limit:** find every prime at or below 2–200,000,000. These are different workloads and are never merged into one ranking.
- **Calculation:** time fresh allocation, initialization, marking and result scanning; exclude checksums, printing and preparation. **Startup + calculation:** time a fresh process per sample, including verification/output and process-supervision overhead, but excluding preparation. Startup has no warm-ups.
- **Sieve throughput:** count complete, freshly allocated sieves during a monotonic wall-clock window. Include initialization, marking, a small observable read on every pass, and release of prior buffers. Retain the last measured sieve and independently verify it after the window. Result scanning, checksum and output are outside the window. Passes/second uses the actual elapsed window, including its final complete pass. Dropping prior references does not force garbage collection; runtime collection costs remain wherever that runtime incurs them.
- The duration harness is available for eight variants across Python, R, Swift, Fortran and assembly. The 35 original workers support both latency workloads. Asking an original worker for throughput reports an unsupported combination rather than substituting another worker.
- Compile once per comparison using optimized release flags, then run workers sequentially in a newly shuffled order each round. Each round starts a new process; calculation and throughput repeat the configured warm-up passes in that process. Samples within a round are consecutive. Default settings retain the original one-round baseline comparison; the Drag Race preset uses three rounds.
- Record raw samples, actual throughput windows and pass counts, per-thread rates, median score, interquartile range (IQR), execution order, CPU/OS/host architecture, tool versions, commands, source hashes and implementation metadata. All current sieves use one computation thread; runtime housekeeping threads may exist. Host architecture metadata does not prove each interpreter/compiler emits native code.
- Compare every sample's count, last prime and modular-sum checksum with an independent full-number reference sieve. For protocol-3 workers at limits up to 100,000, also compare the complete sequence with an independent trial-division reference. Startup mode performs this sequence check in one separate, untimed launch after that implementation's first-round startup samples; timed launches emit compact signatures for both baselines and variants. The boundary-validation script does the same sequence checks across squares and layout boundaries. Checksums at larger limits are a practical check, not proof of sequence identity.
- The timeout applies to the full worker process for each round, including startup, warm-ups, the final pass beyond each window deadline, verification and output. Merely exceeding the sum of requested windows does not guarantee completion. Start with twice the window total (at least 30 seconds), then allow more for slow runtimes or large limits. This suggestion does not predict actual overhead or silently change the chosen timeout.
- Timer resolution differs. Very small latency workloads can report zero; use larger workloads or duration windows. IQR describes the middle 50% spread; it is not a confidence interval or a significance test. Treat small differences cautiously.

`implementations.json` defines eight original variants: Python bulk bytearray, R bulk raw-vector marking, Swift byte/packed/striped layouts, Fortran byte/packed layouts, and assembly with a conditional-count scan. The original 35 workers remain unchanged. A tuned variant is an optimization candidate, not a promise to beat the baseline. Result records snapshot metadata so registry changes cannot rename historical runs. Old history without a contract version remains **v1**; new runs use **v3**.

Assembly is explicitly **an assembly kernel with a C harness** for allocation, timing and output. R uses a C clock bridge. There are no GPU, external prime-library or parallel-sieve implementations. Mutable byte storage is used where available; Lua tables and Erlang/Elixir persistent arrays retain their disclosed representation differences.

The design is inspired by [PlummersSoftwareLLC/Primes](https://github.com/PlummersSoftwareLLC/Primes), whose submissions distinguish implementation, algorithm, storage and thread categories. Our Drag Race preset follows the one-million/five-second workload convention; it is **not an upstream-certified submission or directly comparable published score**. Our startup and first-N results are different tests. No upstream implementation source was imported. See [the validation record](Validation/README.md) for tested platforms and measured comparisons.

```sh
.build/debug/primesieve-cli implementations
.build/debug/primesieve-cli run --languages python,r,swift,fortran,assembly \
  --limit 1000000 --variants all --repetitions 5 --rounds 3
.build/debug/primesieve-cli run --languages python,r,swift,fortran,assembly --drag-race
# Select specific implementations instead of a registry group:
.build/debug/primesieve-cli run --languages swift --limit 1000000 \
  --implementations swift-byte,swift-striped --mode throughput --seconds 5 --rounds 3
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  python3 scripts/validate-variants.py --require-all --output Validation/variant-boundaries.json
```

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
