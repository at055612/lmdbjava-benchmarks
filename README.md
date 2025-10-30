[![Maven Build](https://github.com/lmdbjava/benchmarks/workflows/Maven%20Build/badge.svg)](https://github.com/lmdbjava/benchmarks/actions)
[![License](https://img.shields.io/hexpm/l/plug.svg?maxAge=2592000)](http://www.apache.org/licenses/LICENSE-2.0.txt)

# LmdbJava Benchmarks

**Just want the latest results?
[View them here!](https://github.com/lmdbjava/benchmarks/blob/master/results/20160710/README.md)**

This is a [JMH](http://openjdk.java.net/projects/code-tools/jmh/) benchmark
of open source, embedded, memory-mapped, key-value stores available from Java:

* [LmdbJava](https://github.com/lmdbjava/lmdbjava) (with fast `ByteBuffer`, safe
  `ByteBuffer` and an [Agrona](https://github.com/real-logic/Agrona) buffer)
* [LMDBJNI](https://github.com/deephacks/lmdbjni)
* [Lightweight Java Game Library](https://github.com/LWJGL/lwjgl3/) (LMDB API)
* [LevelDBJNI](https://github.com/fusesource/leveldbjni)
* [RocksDB](http://rocksdb.org/)
* [MVStore](http://h2database.com/html/mvstore.html) (pure Java)
* [MapDB](http://www.mapdb.org/) (pure Java)
* [Xodus](https://github.com/JetBrains/xodus) (pure Java)
* [Chroncile Map](https://github.com/OpenHFT/Chronicle-Map) (pure Java) (**)

(**) does not support ordered keys, so iteration benchmarks not performed

The benchmark itself is adapted from LMDB's
[db_bench_mdb.cc](http://lmdb.tech/bench/microbench/db_bench_mdb.cc), which in
turn is adapted from
[LevelDB's benchmark](https://github.com/google/leveldb/blob/master/db/db_bench.cc).

The benchmark includes:

* Writing data
* Reading all data via each key
* Reading all data via a reverse iterator
* Reading all data via a forward iterator
* Reading all data via a forward iterator and computing a CRC32 (via JDK API)
* Reading all data via a forward iterator and computing a XXH32 hash

Byte arrays (`byte[]`) are always used for the keys and values, avoiding any
serialization library overhead. For those libraries that support compression,
it is disabled in the benchmark. In general any special library features that
decrease latency (eg batch modes, disable auto-commit, disable journals,
hint at expected data sizes etc) were used. While we have tried to be fair and
consistent, some libraries offer non-obvious tuning settings or usage patterns
that might further reduce their latency. We do not claim we have exhausted
every tuning option every library exposes, but pull requests are most welcome.

## Build

Clone this repository and build:

```bash
mvn clean package
```

## Usage

This benchmark uses POSIX calls to accurately determine consumed disk space and
only depends on Linux-specific native library wrappers where a range of such
wrappers exists. Operation on non-Linux operating systems is unsupported.

### Running Benchmarks

#### Library Comparison Benchmarks

Use the `run-libs.sh` script to compare different key-value store libraries:

```bash
# Quick smoke test (1K entries, fast verification)
./run-libs.sh smoketest

# Full benchmark using 25% of system RAM (default)
./run-libs.sh benchmark

# Full benchmark using 50% of system RAM
./run-libs.sh benchmark 50

# Full benchmark using 100% of system RAM
./run-libs.sh benchmark 100
```

The benchmark auto-scales based on available RAM and caps at 1 million entries.
Results are written to `target/benchmark/out-libs-1.json` through `target/benchmark/out-libs-6.json`
along with human-readable logs in `target/benchmark/out-libs-1.txt` through `target/benchmark/out-libs-6.txt`.

#### Version Regression Testing

Use the `run-vers.sh` script to test LmdbJava performance across versions:

```bash
# Quick smoke test (1K entries, fast verification)
./run-vers.sh smoketest

# Full benchmark using 25% of system RAM (default)
./run-vers.sh benchmark
```

This tests selected LmdbJava versions from Maven Central plus current development branches to identify performance regressions.

### Generating Reports

After running library comparison benchmarks, generate a comprehensive report:

```bash
./report-libs.sh
```

After running version regression tests, generate a version comparison report:

```bash
./report-vers.sh
```

Reports generate:
- `target/benchmark/README.md` - Full markdown report with charts
- `target/benchmark/index.html` - HTML viewer with embedded charts (open in browser)
- Various SVG charts and supporting files

## Version Management

Update all dependency and plugin versions:

```bash
mvn versions:update-properties
```

## Support

Issues are disabled for this repository. Please report any issues or questions
on the [LmdbJava issue tracker](https://github.com/lmdbjava/lmdbjava/issues).

## Contributing

Contributions are welcome! Please see the LmdbJava project's
[Contributing Guidelines](https://github.com/lmdbjava/lmdbjava/blob/master/CONTRIBUTING.md).

## License

This project is licensed under the
[Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0.html).
