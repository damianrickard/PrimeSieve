# Windows validation — October 11, 2026

Validation ran directly on **bob**, Windows x64 (OS build 10.0.26300), using .NET SDK 10.0.303. This is a development build, not a signed Windows release.

- Release builds and the self-contained `win-x64` publish completed without warnings or errors.
- **105 regression/integration assertions passed** after the four QA fixes: independent prime reference values, input limits, malformed/incorrect worker output, statistics, all 35 source excerpts, source-manifest hashing, history round-trips and corruption handling, CSV formula escaping, explicit runtime overrides, timeouts, cancellation, batch quoting, Windows descendant termination, and saving partial comparisons after cancellation. The corresponding cross-platform suite passed 92 assertions on macOS.
- New checks cover malformed/null/unreadable settings, invalid path entries, JDK home validation, executable-shim and directory-junction JVM fixtures, argument round-trips including Unicode, 25 immediate Windows process exits, and child cleanup after its parent exits. The JVM fixtures exercise discovery only; they do not claim Java/Scala/Groovy compilation coverage.
- Process execution, runtime discovery and a full startup benchmark completed while their caller's simulated UI dispatch queue was blocked. Benchmark work and timing now run on background threads. Windows workers are created atomically inside a kill-on-close job with a restricted inherited-handle list.
- **C#, F#, Python 3.13.13 and JavaScript/Node 24.16.0** passed worker verification at 1, 2, 5 and 1,000 primes, with two measured iterations and one warm-up.
- Those four runtimes passed a 10,000-prime, three-iteration CLI startup comparison and both calculation and startup comparisons through the updated, self-contained WPF application.
- The interactive UI check exercised JSON/CSV export, history reopening, invalid input rejection, runtime setup and the code explorer. Rendered results, code, setup and minimum-window-size PNGs were inspected. Desktop-only binding and minimum-size layout defects found during this check were corrected before final packaging.
- The updated UI check used isolated settings/history with a deliberately malformed `runtimes.json`: all four installed runtimes remained usable, both comparisons completed, the settings warning appeared, and the malformed original stayed unchanged. Test history was confined to the evidence folder.
- The portable app includes its .NET desktop runtime. Language compilers/interpreters remain external dependencies.

## UI follow-up validation

The two subsequent Claude UI findings were corrected and tested on bob. **17 new WPF regression assertions passed**, alongside a fresh **105-assertion Windows regression/integration pass** (122 total). Closing during startup or refresh discovery now cancels a real slow probe, waits for process cleanup, and closes within five seconds in both tests, including repeated close requests. The tests open the actual modal Details dialog from saved history containing an unknown language ID, verify that measurements remain readable and code navigation is disabled, and verify that known-language navigation still works. Viewing these records leaves the saved history unchanged. WPF regression tests use isolated temporary state; they do not modify normal application history.

The other **31 language toolchains were not installed on bob**, so their Windows recipes and source adaptations have not been validated end to end. The x64 Windows assembly source and clock bridges are implemented but unexecuted in this validation. ARM64 Windows execution, macOS-history importing, installer behavior and Windows code signing are outside this validation.

Reproduction commands and the opt-in interactive UI check are in [README.md](README.md). Machine-specific JSON, CSV, PNG and package outputs are intentionally ignored under `Windows/artifacts`; the validation summary and reproducible checks are versionable source files.
