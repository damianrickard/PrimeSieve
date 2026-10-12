# Validation evidence

Validated on Damian's Apple Silicon Mac on October 11, 2026.

This summary is published with the source. The named raw logs and benchmark exports are retained locally and excluded from Git because they contain machine names and local paths. To reproduce the checks, follow the build and test instructions in the project README and set `PRIMESIEVE_REQUIRE_ALL=1` to require all 35 languages.

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
