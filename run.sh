#!/bin/bash
set -euo pipefail

# Usage: ./run.sh [smoketest|benchmark [ram_percent]]
# smoketest: Fixed 1K entries for quick verification
# benchmark: Auto-scale entries based on RAM (default 25%, capped at 1M entries)

MODE="${1:-benchmark}"
RAM_PERCENT="${2:-25}"

# Detect total RAM in GB
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))
elif [[ "$OSTYPE" == "darwin"* ]]; then
  TOTAL_RAM_BYTES=$(sysctl -n hw.memsize)
  TOTAL_RAM_GB=$((TOTAL_RAM_BYTES / 1024 / 1024 / 1024))
else
  echo "Unsupported OS. Defaulting to 8 GB RAM assumption."
  TOTAL_RAM_GB=8
fi

echo "Detected RAM: ${TOTAL_RAM_GB} GB"

case $MODE in
  smoketest)
    # Fixed small dataset for verification
    ITER_OPTS="-wi 0 -i 1 -f 1"
    R_OPTS="-r 3s"

    # Fixed 1K entries for all runs
    NUM_RUN1=1000
    NUM_RUN2=1000
    NUM_RUN3=1000
    NUM_RUN4=1000
    NUM_RUN5=1000
    NUM_RUN6=1000

    echo "Running in SMOKETEST mode (1K entries, fast verification)"
    ;;

  benchmark)
    # Production benchmark with RAM-based scaling
    ITER_OPTS="-wi 3 -i 3 -f 3"
    R_OPTS=""

    # Calculate max RAM in bytes (RAM_PERCENT of total)
    MAX_RAM_GB=$((TOTAL_RAM_GB * RAM_PERCENT / 100))
    MAX_RAM_BYTES=$((MAX_RAM_GB * 1024 * 1024 * 1024))

    echo "Max RAM usage: ${MAX_RAM_GB} GB (${RAM_PERCENT}% of ${TOTAL_RAM_GB} GB)"

    # Maximum entry count cap
    MAX_ENTRIES=1000000

    # Calculate entries for each run based on entry sizes (4 byte key + value size)
    # Cap at MAX_ENTRIES to prevent excessive runs on large machines

    # Run 1: LMDB config test with 100 byte values (4 + 100 = 104 byte entries)
    NUM_RUN1=$((MAX_RAM_BYTES / 104))
    [ $NUM_RUN1 -gt $MAX_ENTRIES ] && NUM_RUN1=$MAX_ENTRIES

    # Run 2: Value size testing - scale based on largest entry (4 + 16369 = 16373 bytes)
    NUM_RUN2=$((MAX_RAM_BYTES / 16373))
    [ $NUM_RUN2 -gt $MAX_ENTRIES ] && NUM_RUN2=$MAX_ENTRIES

    # Run 3: Batch size test with 8176 byte values (4 + 8176 = 8180 byte entries)
    NUM_RUN3=$((MAX_RAM_BYTES / 8180))
    [ $NUM_RUN3 -gt $MAX_ENTRIES ] && NUM_RUN3=$MAX_ENTRIES

    # Run 4: All DBs with 100 byte values (4 + 100 = 104 byte entries)
    NUM_RUN4=$((MAX_RAM_BYTES / 104))
    [ $NUM_RUN4 -gt $MAX_ENTRIES ] && NUM_RUN4=$MAX_ENTRIES

    # Run 5: Large values 2026 bytes (4 + 2026 = 2030 byte entries)
    NUM_RUN5=$((MAX_RAM_BYTES / 2030))
    [ $NUM_RUN5 -gt $MAX_ENTRIES ] && NUM_RUN5=$MAX_ENTRIES

    # Run 6: Very large values - use largest entry (4 + 16368 = 16372 bytes) for safety
    NUM_RUN6=$((MAX_RAM_BYTES / 16372))
    [ $NUM_RUN6 -gt $MAX_ENTRIES ] && NUM_RUN6=$MAX_ENTRIES

    echo "Calculated entry counts:"
    echo "  Run 1 (LMDB config, 100B values): ${NUM_RUN1}"
    echo "  Run 2 (value sizing, up to 16KB values): ${NUM_RUN2}"
    echo "  Run 3 (batch test, 8KB values): ${NUM_RUN3}"
    echo "  Run 4 (all DBs, 100B values): ${NUM_RUN4}"
    echo "  Run 5 (large vals, 2KB values): ${NUM_RUN5}"
    echo "  Run 6 (huge vals, 4-16KB values): ${NUM_RUN6}"
    ;;

  *)
    echo "Usage: $0 [smoketest|benchmark [ram_percent]]"
    echo "  smoketest: Fixed 1K entries for quick verification"
    echo "  benchmark [percent]: Auto-scale entries based on system RAM (default 25%, max 1M entries)"
    echo ""
    echo "Examples:"
    echo "  $0 smoketest          # Fast verification with 1K entries"
    echo "  $0 benchmark          # Use 25% of system RAM (max 1M entries)"
    echo "  $0 benchmark 50       # Use 50% of system RAM (max 1M entries)"
    echo "  $0 benchmark 100      # Use 100% of system RAM (max 1M entries)"
    exit 1
    ;;
esac

# Single-shot benchmarks settings
SS_OPTS="-bm ss -wi 0 -i 1 -f 1"

# Clean and create output directory
OUTPUT_DIR="target/benchmark"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# JVM flags for Java 9+ module system compatibility
JVM_OPTS="--add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.lang.reflect=ALL-UNNAMED --add-opens java.base/java.nio=ALL-UNNAMED --add-exports java.base/jdk.internal.misc=ALL-UNNAMED --add-exports java.base/sun.nio.ch=ALL-UNNAMED --add-exports jdk.compiler/com.sun.tools.javac.file=ALL-UNNAMED --enable-native-access=ALL-UNNAMED"

echo ""

# Run 1: LMDB configuration options (sync, forceSafe, metaSync, writeMap) with 100B values
# RAM-scaled to test configuration impact across different LMDB implementations
echo "Run 1: LMDB implementations with configuration options (${NUM_RUN1} entries)..."
java $JVM_OPTS -jar target/benchmarks.jar -rf json $ITER_OPTS $R_OPTS -to 10m -tu ms -p num=${NUM_RUN1} -p sync=true,false -p forceSafe=true,false -p metaSync=true,false -p writeMap=true,false -rff "$OUTPUT_DIR"/out-1.json LmdbJavaAgrona LmdbJavaByteBuffer LmdbJni LmdbLwjgl | tee "$OUTPUT_DIR"/out-1.txt

# Run 2: Page boundary alignment testing with values from 2KB to 16KB
# RAM-scaled to test performance at different page sizes (2026/2027, 4080/4081, 8176/8177, 16368/16369)
echo "Run 2: Value size testing (${NUM_RUN2} entries)..."
java $JVM_OPTS -jar target/benchmarks.jar -rf json $SS_OPTS $R_OPTS -to 10m -tu ms -p num=${NUM_RUN2} -p sequential=true,false -p valSize=2026,2027,4080,4081,8176,8177,16368,16369 -e readCrc -e readRev -e readSeq -e readXxh32 -e write -rff "$OUTPUT_DIR"/out-2.json LevelDb LmdbJavaAgrona RocksDb | tee "$OUTPUT_DIR"/out-2.txt

# Run 3: LSM batch size optimization for LevelDB and RocksDB with 8KB values
# RAM-scaled to evaluate 1M vs 10M batch sizes on write performance
echo "Run 3: Batch size evaluation (${NUM_RUN3} entries)..."
java $JVM_OPTS -jar target/benchmarks.jar -rf json $SS_OPTS $R_OPTS -to 60m -tu ms -p num=${NUM_RUN3} -p valSize=8176 -p batchSize=1000000,10000000 -e readCrc -e readKey -e readRev -e readSeq -e readXxh32 -rff "$OUTPUT_DIR"/out-3.json LevelDb RocksDb | tee "$OUTPUT_DIR"/out-3.txt

# Run 4: Comprehensive test of all libraries with 100B values
# RAM-scaled to test int vs string keys and sequential vs random access patterns
echo "Run 4: All libraries with key and access pattern variants (${NUM_RUN4} entries)..."
java $JVM_OPTS -jar target/benchmarks.jar -rf json $ITER_OPTS $R_OPTS -to 60m -tu ms -p num=${NUM_RUN4} -p intKey=true,false -p sequential=true,false -rff "$OUTPUT_DIR"/out-4.json | tee "$OUTPUT_DIR"/out-4.txt

# Run 5: Large value (2KB) testing with broad library coverage
# RAM-scaled, excludes hash benchmarks to reduce execution time
echo "Run 5: Large value testing (${NUM_RUN5} entries, 2KB values)..."
java $JVM_OPTS -jar target/benchmarks.jar -rf json $SS_OPTS $R_OPTS -to 120m -tu ms -p num=${NUM_RUN5} -p sequential=true,false -p batchSize=1000000 -p valSize=2026 -e readCrc -e readRev -e readXxh32 -rff "$OUTPUT_DIR"/out-5.json Chronicle LevelDb LmdbJavaAgrona LmdbJavaByteBuffer LmdbJni LmdbLwjgl RocksDb MapDb Xodus | tee "$OUTPUT_DIR"/out-5.txt

# Run 6: Very large value (4-16KB) testing with fastest libraries only
# RAM-scaled, excludes pure Java and slower LMDB implementations due to memory constraints
echo "Run 6: Very large value testing (${NUM_RUN6} entries, 4-16KB values)..."
java $JVM_OPTS -jar target/benchmarks.jar -rf json $SS_OPTS $R_OPTS -to 360m -tu ms -p num=${NUM_RUN6} -p sequential=false -p batchSize=1000000 -p valSize=4080,8176,16368 -e readCrc -e readRev -e readXxh32 -rff "$OUTPUT_DIR"/out-6.json Chronicle LevelDb LmdbJavaAgrona RocksDb | tee "$OUTPUT_DIR"/out-6.txt

echo ""
echo "Benchmark suite completed in $MODE mode"
if [ "$MODE" = "benchmark" ]; then
  echo "RAM usage limit: ${RAM_PERCENT}% of ${TOTAL_RAM_GB} GB (${MAX_RAM_GB} GB max)"
fi
echo "Results available in $OUTPUT_DIR/out-1.json through $OUTPUT_DIR/out-6.json"
echo "Human-readable logs in $OUTPUT_DIR/out-1.txt through $OUTPUT_DIR/out-6.txt"
echo ""
echo "To generate a report from these results, run: ./report.sh"
