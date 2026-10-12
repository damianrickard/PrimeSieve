#!/usr/bin/env python3
"""Build each available protocol-3 worker once; check full sequences at boundaries.
No performance threshold is a correctness test. Run with --require-all on a fully
provisioned host. Uses the host's real architecture and standard installed tools.
"""
import argparse
import json
import math
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / 'Sources/PrimeSieveCore/Resources/Workers'
WINDOWS = platform.system() == 'Windows'
ARCH = 'arm64' if platform.machine().lower() in ('arm64', 'aarch64') else 'x86_64'


def primes_to(limit):
    # Trial division is independent from the worker algorithms and layouts.
    primes = []
    for candidate in range(2, limit + 1):
        if all(candidate % p for p in primes if p <= math.isqrt(candidate)):
            primes.append(candidate)
    return primes


def run(command, directory):
    result = subprocess.run(command, cwd=directory, text=True, capture_output=True, timeout=120)
    if result.returncode:
        raise RuntimeError(f'{command[0]} failed: {result.stderr[-3000:]} {result.stdout[-1000:]}')
    return result.stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--require-all', action='store_true')
    parser.add_argument('--output')
    args = parser.parse_args()
    registry = json.loads((SOURCES / 'implementations.json').read_text())
    tools = {key: shutil.which(name) for key, name in dict(python='python3', swift='swiftc', fortran='gfortran', assembly='clang', r='Rscript').items()}
    tools['python'] = tools['python'] or shutil.which('python')
    evidence = dict(platform=platform.platform(), architecture=ARCH, checks=0, variants=[], skipped=[])
    limits = [2, 3, 4, 7, 8, 9, 10, 15, 16, 17, 24, 25, 26, 31, 32, 33, 48, 49, 50, 63, 64, 65, 120, 121, 122, 127, 128, 129, 1023, 1024, 1025, 32767, 32768, 32769]
    for language in dict.fromkeys(x['languageID'] for x in registry):
        if not tools[language] or (language == 'r' and not tools['assembly']):
            evidence['skipped'].append(language)
            continue
        with tempfile.TemporaryDirectory(prefix='PrimeSieve-variant-check-') as tmp:
            directory = Path(tmp)
            entries = [e for e in registry if e['languageID'] == language]
            source = entries[0]['source']
            shutil.copy(SOURCES / source, directory / source)
            binary = str(directory / ('worker.exe' if WINDOWS else 'worker'))
            if language in ('swift', 'fortran'):
                run([tools[language], '-O' if language == 'swift' else '-O3', source, '-o', binary], directory)
                command = [binary]
            elif language == 'assembly':
                assembly = f'tuned_{ARCH}.s'
                assembly_source = ROOT / 'Windows/Workers' / assembly if WINDOWS else SOURCES / assembly
                shutil.copy(assembly_source, directory / assembly)
                run([tools[language], '-O3', source, assembly, '-o', binary], directory)
                command = [binary]
            elif language == 'r':
                clock = ROOT / 'Windows/Workers/clock.c' if WINDOWS else SOURCES / 'clock.c'
                shutil.copy(clock, directory / 'clock.c')
                run([tools['assembly'], '-O2', '-shared' if WINDOWS else '-dynamiclib', 'clock.c', '-o', 'clock.dll' if WINDOWS else 'clock.dylib'], directory)
                command = [tools[language], source]
            else:
                command = [tools[language], '-B', source]
            for entry in entries:
                for limit in limits:
                    expected = primes_to(limit)
                    output = run(command + [str(len(expected)), str(limit), '1', '2', 'calculation', '0.01', 'limit', entry['variant'], '1'], directory)
                    records = [json.loads(line) for line in output.splitlines() if line.startswith('{')]
                    assert len(records) == 2, (entry['id'], limit, output)
                    for record in records:
                        assert record['primes'] == expected, (entry['id'], limit, record)
                        assert record['count'] == len(expected) and record['last_prime'] == expected[-1]
                        assert record['checksum'] == sum(expected) % 1_000_000_007
                        evidence['checks'] += 1
                for count in [1, 2, 5, 100]:
                    limit = 1000
                    expected = primes_to(limit)[:count]
                    records = [json.loads(line) for line in run(command + [str(count), str(limit), '0', '1', 'calculation', '0.01', 'count', entry['variant'], '1'], directory).splitlines() if line.startswith('{')]
                    assert records[0]['primes'] == expected, (entry['id'], count)
                    evidence['checks'] += 1
                expected = primes_to(1024)
                windows = [json.loads(line) for line in run(command + [str(len(expected)), '1024', '2', '2', 'throughput', '0.02', 'limit', entry['variant'], '1'], directory).splitlines() if line.startswith('{')]
                assert len(windows) == 2, (entry['id'], 'missing windows')
                for record in windows:
                    assert record['elapsed_ns'] >= 20_000_000 and record['passes'] > 0
                    assert record['primes'] == expected
                    evidence['checks'] += 1
                evidence['variants'].append(entry['id'])
                print('PASS', entry['id'], flush=True)
    if args.require_all and evidence['skipped']:
        raise RuntimeError('Missing toolchains: ' + ', '.join(evidence['skipped']))
    if args.output:
        Path(args.output).write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps(evidence, indent=2))


if __name__ == '__main__':
    main()
