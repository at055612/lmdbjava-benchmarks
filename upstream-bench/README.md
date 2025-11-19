# Upstream LMDB Benchmark

This directory contains the upstream C benchmark provided by the LMDB maintainer in response to [ITS#10406](https://bugs.openldap.org/show_bug.cgi?id=10406) - our report of write performance regression.

## Purpose

This benchmark serves as an authoritative baseline for validating LMDB performance across versions:
- Uses native C code (eliminates JNI overhead)
- Provided directly by LMDB maintainer
- Matches our Java benchmark scenario (sequential append with integer keys)
- Enables comparison between Java and C performance characteristics

## Files

- `mtest-append-original.c` - Upstream benchmark code from ITS#10406 (unmodified)
- `mtest-append.c` - Modified benchmark for testing different scenarios
- `run-upstream-bench.sh` - Test harness to run across multiple LMDB versions
- `target/` - Build artifacts and results (gitignored)
  - `target/mtest-append` - Compiled benchmark binary
  - `target/results/` - Benchmark results for each LMDB version

## Benchmark Characteristics

- **Operation**: Sequential writes using `MDB_APPEND` flag
- **Key Type**: Integer keys (`MDB_INTEGERKEY`)
- **Entry Count**: 1,000,000
- **Value Size**: 100 bytes (zeroed)
- **Commit Frequency**: Every 1,000 entries (1,000 transactions total)
- **Flags**: `MDB_NOSYNC` (for consistency with Java benchmarks)
- **Iterations**: 3 runs per version

## Usage

```bash
./run-upstream-bench.sh
```

Results are saved to `target/results/upstream-LMDB_<version>.txt`

The script automatically:
1. Checks out each LMDB version from the OpenLDAP repository
2. Compiles the LMDB library
3. Compiles and runs the benchmark
4. Generates a summary comparison table

## Performance Expectations

Each benchmark iteration completes in ~0.075 seconds on modern hardware.
Total runtime for all 14 versions (3 iterations each): ~1 minute.

## Comparison with Java Benchmarks

This C benchmark can be compared with LmdbJava benchmarks at https://lmdb-benchmark.lmdbjava.org/

Key differences:
- C benchmark uses raw LMDB API (no JNI overhead)
- C benchmark commits every 1,000 entries vs Java's single-transaction approach
- Results help isolate whether regressions are in LMDB itself or JNI layer

## License

Licensed under the OpenLDAP Public License (see mtest-append-original.c for copyright details).
