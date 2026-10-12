# Validation evidence

Validated on Damian's Apple Silicon Mac on October 11, 2026.

This summary is published with the source. The named raw logs and benchmark exports are retained locally and excluded from Git because they contain machine names and local paths. To reproduce the checks, follow the build and test instructions in the project README and set `PRIMESIEVE_REQUIRE_ALL=1` to require all 35 languages.

## App icon and build 2

### Developer ID signing and notarization

- Version 0.1.0 build 2 was signed with Developer ID Application, hardened runtime and a secure timestamp. Apple accepted submission `e0069f7a-3d8f-4d28-8865-a055f669d60e`; the approval ticket was stapled to the app.
- The release ZIP was extracted and compared against the notarized bundle, including file contents and permissions. Strict signature verification, ticket validation and Gatekeeper assessment all passed; Gatekeeper reports `Notarized Developer ID`.
- The installed `/Applications/PrimeSieve.app` matches the notarized bundle, passes the same checks and launches successfully. The prior app was preserved locally for rollback.
- Packaging checks with temporary fixtures confirmed that deleted resources cannot survive from a previous app and that a signing failure preserves the previous build. Both release scripts passed shell syntax checks. Claude Opus 5.5 independently reviewed the final scripts and found no actionable defects; its review was static.
- Signing and packaging changed; benchmark sources did not. The language test results below predate this signing update.

- `icon-build.log`: release packaging succeeded with the new graphite-and-orange icon. All ten standard macOS icon representations were unpacked and checked for correct dimensions and transparency; the 32- and 128-pixel images were visually inspected.
- `CFBundleIconFile` resolves to the packaged `AppIcon.icns`; the installed About window visibly shows the icon and version 0.1.0 (2).
- `/Applications/PrimeSieve.app` matches the release bundle in file contents and permissions and passes strict code-signature verification. The previous installed build was retained in an ignored local `dist/previous-build-1-*` folder.
- This update changes artwork and packaging only; worker algorithms and application behavior are unchanged.

## Clear History option

- `history-tests.log`: six focused tests passed. Temporary histories cover deleting saved and corrupt JSON, repeated clearing, saving afterward, preserving exported files and nested folders, removing symlinks without deleting their targets, failure reporting, and blocking deletion during a run. App-model checks confirm the visible result is retained.
- The rebuilt app's History window and confirmation were checked through the UI; Cancel returned to the saved list. All eight existing user sessions were verified byte-for-byte unchanged. Actual deletion was exercised only against temporary test histories.
- `history-build.log`: release build succeeded; strict code-signature verification passed. No worker algorithms changed in this update.
- Claude Opus 5.5 independently reviewed the Clear History changes and reported no actionable defects; that review did not execute tests.
- Installed in `/Applications/PrimeSieve.app`. Installed file contents and permissions match the release bundle, strict signature verification passed, and the running process was confirmed to use the installed path. The installed UI shows Clear History, retains the eight existing sessions, and detects all 35 runtimes.

## Approved QA remediation

All seven accepted findings from Claude's two Opus reviews were addressed: consistent runtime discovery, helper overrides and provenance, queued runtime refresh, per-language source manifests, .NET 6 build arguments, primitive Clojure loops, and ahead-of-time Guile compilation.

- `qa-all-tests.log`: 18 tests passed with zero failures in 93.7 seconds. All 35 languages passed at 1, 2, 5, 1,000 and 10,000 primes. Regression tests cover minimal-PATH discovery, invalid overrides, renamed Node executables in compiler wrappers, custom helpers across nine language workers, source-manifest isolation, historical JSON compatibility, .NET 6/7/10 argument mapping, Clojure diagnostics, and overlapping runtime refreshes.
- `benchmark-qa-10000.json`: all 35 languages, three measurements after two warm-ups, zero failures. Sample counts and exported mean/median values were independently checked with Python statistics.
- `benchmark-qa-startup-1000.json` and `.csv`: all 35 languages in startup mode, two measurements, zero failures. All 70 samples and CSV sort order were independently checked.
- `qa-runtime-shell.txt` and `qa-runtime-minimal.txt`: identical runtime discovery results for all 35 languages under normal shell and Finder-style minimal PATH environments.
- `qa-release-build.log` and `qa-codesign.log`: successful release packaging and strict signature verification. Every bundled worker/support file matches the current source.
- `benchmark-qa-ui-500000.json`: the rebuilt app ran Swift, Rust and TypeScript at 500,000 primes, ten iterations each, with zero failures. Mean/median were independently checked. The rendered TypeScript details correctly show both tsc and Node paths/versions, the launch command, and a source manifest containing only `sieve.ts`. The user's original Swift/Rust selection and count/iteration settings were retained after this smoke test.
- Clojure compiled with reflection and boxed-arithmetic diagnostics enabled and emitted neither warning. Scheme preparation now explicitly compiles bytecode before measurement.
- Real C# and F# execution used installed .NET SDK 10.0.401. The SDK 6 flag branch was unit tested; SDK 6 itself was not installed or executed.
- The format-2 source hash covers file names, file contents and only actual dependencies; generated .NET project settings are included. Old hashes use different semantics and should not be compared directly.

## Code explorer, iteration selector, statistics and orange theme

- `explorer-tests.log`: 11 tests passed with zero failures. All 35 documented workers were checked at 1, 2, 5, 1,000 and 10,000 primes. Added tests cover documented excerpt extraction for every language and both assembly architectures, malformed markers, odd/even/single-sample statistics, exports, and older session compatibility.
- `benchmark-explorer-10000.json`: all 35 documented workers, three measurements after two warm-ups, zero failures.
- `benchmark-ui-five-iterations.json`: the packaged SwiftUI app was set to five iterations for Swift, then run at 100,000 primes. Its five saved samples and exported mean/median were independently checked against Python's statistics calculations.
- Rendered explorer layout was inspected. Language search, Pascal selection, ARM64/Intel switching, and navigation from result details to the corresponding code were exercised. The interface displays the international orange accent and the main iteration selector.
- Release build and strict code-signature verification passed after these changes.

The evidence in this section predates the approved QA remediation above.

## Initial build evidence

- `tests.log`: full eight-test suite passed, including all 35 workers at 1, 2, 5, 1,000 and 10,000 primes, correctness validation, protocol rejection and process timeout/cancellation.
- `cancellation-tests.log`: two focused tests passed after adding child-process cancellation coverage. Nine distinct tests have passed across these runs.
- `benchmark-10000.json`: all 35 languages, three measurements after two warm-ups, zero failures.
- `benchmark-startup-1000.json` and `.csv`: all 35 languages in startup mode, two measurements, zero failures.
- `benchmark-100000.json` and `.csv`: completed inside the packaged SwiftUI app, all 35 languages, seven measurements after three warm-ups, zero failures. Every worker reported the correct final prime, 1,299,709.

The saved 100,000-prime comparison was reopened through History. Result details and both CSV and JSON exports were exercised in the packaged app. Exported data was parsed to confirm 35 results, zero failures, and ascending median order in the CSV. The rendered window was inspected after correcting chart labels and table selection. Invalid input and runtime setup were also checked through the interface.

The final release app built successfully and passed strict code-signature verification. It is locally ad-hoc signed. Intel assembly was assembled, but Intel execution has not been tested. Results describe these implementations and runtime versions on this Mac, rather than a universal ranking of programming languages.


## Workloads and named variants (contract v3, 2026-10-12)

These results concern the new working-tree implementation; they do not describe the previously published v0.1.0 app.

- The Swift suite passed 24 core and three app tests, followed by five focused variant tests after the final coordinator changes. Native Windows passed 146 core checks, 17 WPF checks, and a three-round CLI throughput check.
- All 35 baselines passed inclusive-limit checks at 2 and 1,024. The packaged macOS UI completed an eight-variant, three-round throughput smoke run; storage filtering, per-thread detail and navigation to the exact variant in the explorer were exercised.
- Eight protocol-3 variants across Python, R, Swift, Fortran and assembly passed 592 independent complete-sequence/boundary checks on Apple Silicon. Boundaries cover primes, prime squares, byte/bit/stripe boundaries, first-N stopping and actual duration windows. `v3-boundaries-macos.json` records the roster. Original baseline source files are unchanged.
- On native Windows x64 (`bob`), Python passed the same 74 checks. R, Swift, Fortran and assembly are explicitly skipped because those toolchains are absent. Both macOS and Windows x64 assembly sources also passed cross-assembly syntax checks on the Mac; that does not establish x64 runtime correctness.
- The Windows rendered smoke check exercised calculation, startup, two-round throughput, history reopening, invalid inputs and the explorer. The revised minimum 1100×840 window passed and its screenshot was inspected. The evidence is in `v3-windows-ui/`; it uses isolated history/preferences.
- Windows maximum-repetition verification (30 complete sequences at limit 100,000) passed after adding a bounded four-million-character stdout allowance for that protocol path; normal capture limits are preserved.
- CPU and host architecture are recorded. Per-worker runtime architecture has not been inspected; do not infer that every toolchain uses native execution from the host metadata.

### Repeated performance observations

`v3-latency-macos.json`: Apple M5 Pro, macOS 27.2 arm64, inclusive limit 1,000,000, three randomized rounds, five samples and three warm-up passes per round. Compilation occurred before measurements. These are observations from one session, not statistical superiority claims.

| Implementation | Median calculation | Change relative to its baseline |
| --- | ---: | ---: |
| Python baseline / bulk bytearray | 78.242 / 4.947 ms | 15.8× faster |
| R baseline / bulk raw vector | 122.854 / 3.430 ms | 35.8× faster |
| Assembly baseline / conditional scan | 0.904 / 0.465 ms | 1.9× faster |
| Fortran baseline / byte variant | 0.466 / 0.465 ms | Effectively tied |
| Swift baseline / striped bits | 0.583 / 0.560 ms | Small difference; overlapping variability |

Plain packed bits were slower than their byte baseline in both Swift and Fortran. Keeping the alternatives visible is intentional.

`v3-throughput-macos.json`: the same limit, three five-second windows, three warm-up sieve passes per round. All eight variants passed verification. Median passes/second (IQR): Swift striped 9,313 (121); assembly conditional scan 3,338 (26); Fortran byte 3,330 (24); Python bulk 2,819 (16); Swift byte 2,516 (426); Fortran packed 2,239 (13); Swift packed 1,904 (18); R bulk 644 (2). Throughput excludes result scanning, so its ranking can differ substantially from calculation latency. Each score uses the actual elapsed window and raw pass count.

Machine-specific JSON, logs and screenshots remain ignored by Git. Reproduce boundary checks with `scripts/validate-variants.py`; reproduce comparisons with the commands in the main README. No upstream code was imported, no upstream submission certification is claimed, and these observations are not directly comparable to a different host's published Drag Race leaderboard.


### Approved QA remediation

The initial Claude Opus 5.5 review passed with three low-severity findings. All three were accepted and corrected: malformed worker JSON includes a bounded diagnostic excerpt; the Swift registry caches its load result, displays bundle failures and prevents an incomplete roster from being benchmarked; the assembly metadata correctly identifies x86-64 `setcc + add`.

Seven focused Swift tests passed, including missing/malformed/invalid registry cases, bounded diagnostic text, and normal calculation/startup/throughput execution with export round-trips. A disposable copy of the CLI separately verified all 43 valid entries and explicit nonzero failures for missing and malformed registry files. The local macOS app was rebuilt and its signature verified. Historical result snapshots retain their original descriptions; newly recorded assembly results use the corrected metadata.

The second Claude review requested two low-severity changes. Both were accepted: the active workload alone controls input validation, and throughput timeout guidance now accounts for startup, warm-ups, window overrun, verification and output. The timeout finding was accepted as a guidance gap, not as proof that every near-threshold configuration must fail. Both CLIs and interfaces explain the extra budget; twice the window total with a 30-second minimum is a planning suggestion, not a guarantee or an automatic timeout change.

Round-two validation passed: nine Swift core variant tests and five app-model tests; 144 C# checks on macOS; 152 core checks and 17 WPF checks on native Windows. Regression cases cover invalid hidden values in both workload directions, errors naming the visible field, and the 23-window/120-second boundary with a 230-second suggestion. The local macOS app was rebuilt and its signature passed strict verification. No findings were rejected.

The third Claude Opus 5.5 review requested four changes. All were accepted: an explicit Dispatch import for the shared Swift worker; full-sequence verification outside startup timing; publication of results only after complete rounds; and a cached, validated Windows registry whose errors do not prevent runtime discovery. The import matches the existing Windows baseline's portability requirement; native Windows Swift compilation remains unverified because that toolchain is not installed on Bob. No findings were rejected.

Round-three validation passed:

- Full Swift suite: 29 core and five app tests, including first- and second-round cancellation and startup arguments. The local app was rebuilt and passed strict signature verification.
- All 592 tuned-worker boundary checks on macOS, including the recompiled Swift variants (`qa3-boundaries-macos.json`). All eight variants also passed a two-round startup run at limit 1,024; recorded timed commands end in `full=0` and each result contains exactly two samples (`qa3-startup-macos.json`). These are correctness runs, not new performance comparisons.
- C# tests: 164 checks on macOS; 177 checks including integration on native Windows. These exercise registry fixtures, complete-round cancellation/history and startup timing arguments.
- Native Windows UI: 17 checks with the normal bundle, then 19 each in disposable copies with malformed and missing registry files. Both damaged-bundle runs confirmed visible errors, 35 baseline code entries and working startup/refresh discovery. Normal worker resources were untouched.

Cancelled comparisons now keep accumulated samples from the last complete round, excluding implementations that failed. An interrupted first round produces no ranked entries. Startup mode still checks each timed sample's signature; small tuned workloads receive one additional, untimed complete-sequence check before their results are accepted.
