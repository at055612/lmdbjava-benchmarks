#!/bin/bash
#
# Copyright © 2016-2025 The LmdbJava Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

set -euo pipefail

# Pure HTML report generator for LmdbJava library comparison benchmarks

# Source common functions
source "$(dirname "$0")/report-common.sh"

# Set data directory (input from run-libs.sh) and output directory
DATA_DIR="target/benchmark-libs"
WORK_DIR="target/benchmark"

# Check prerequisites
echo "Checking for required files..."
for i in {1..6}; do
  if [ ! -f "$DATA_DIR/out-libs-${i}.json" ] || [ ! -f "$DATA_DIR/out-libs-${i}.txt" ]; then
    echo "ERROR: Missing $DATA_DIR/out-libs-${i}.json or $DATA_DIR/out-libs-${i}.txt"
    echo "Please run ./run-libs.sh first to generate benchmark results"
    exit 1
  fi
done

check_tool() {
  if ! command -v "$1" &> /dev/null; then
    echo "ERROR: $1 is required but not installed"
    return 1
  fi
  return 0
}

echo "Checking for required tools..."
MISSING_TOOLS=0

for TOOL in jq gnuplot awk sed grep sort cut head java; do
  if ! check_tool "$TOOL"; then
    MISSING_TOOLS=1
  fi
done

if [ $MISSING_TOOLS -eq 1 ]; then
  echo ""
  echo "Please install the missing tools and try again"
  exit 1
fi

echo "All prerequisites met. Generating report..."
echo ""

# Extract system information
CPU_MODEL=$(get_cpu_info)
CPU_COUNT=$(get_cpu_count)
RAM_GIB=$(get_total_ram_gib)
KERNEL=$(get_kernel)
JAVA_TAG=$(get_java_version)

check_tmpfs() {
  if df -T /tmp | grep -q tmpfs; then
    echo "tmpfs"
  else
    df -T /tmp | tail -1 | awk '{print $2}'
  fi
}

TMP_FS=$(check_tmpfs)

# Extract library versions from pom.xml (must be done before cd)
get_version() {
  local prop=$1
  grep "<${prop}>" pom.xml | head -1 | sed "s/.*<${prop}>\(.*\)<\/${prop}>.*/\1/"
}

JMH_VERSION=$(get_version "jmh.version")
LMDBJAVA_VERSION=$(get_version "lmdbjava.version")
LMDBJNI_VERSION=$(get_version "lmdbjni.version")
LWJGL_VERSION=$(get_version "lwjgl.version")
LEVELDB_VERSION=$(get_version "leveldbjni.version")
ROCKSDB_VERSION=$(get_version "rocksdbjni.version")
MAPDB_VERSION=$(get_version "mapdb.version")
MVSTORE_VERSION=$(get_version "h2-mvstore.version")
XODUS_VERSION=$(get_version "xodus.version")
CHRONICLE_VERSION=$(get_version "chronicle-map.version")

# Get benchmark date and mode
BENCH_DATE=$(stat -c %y "$DATA_DIR/out-libs-1.json" | cut -d' ' -f1)
BENCH_MODE=$(get_benchmark_mode "$DATA_DIR/out-libs-1.json")

# Create output directory and copy benchmark data files
mkdir -p "$WORK_DIR"
cp "$DATA_DIR"/out-libs-*.json "$WORK_DIR/"
cp "$DATA_DIR"/out-libs-*.txt "$WORK_DIR/"

# Change to working directory to generate all files there
cd "$WORK_DIR"

echo "Benchmark Mode: $BENCH_MODE"
if [ "$BENCH_MODE" = "smoketest" ]; then
  echo "  WARNING: Smoketest results are for verification only, not performance comparison"
fi
echo ""

echo "System Information:"
echo "  CPU: $CPU_MODEL (${CPU_COUNT} cores)"
echo "  RAM: ${RAM_GIB} GiB"
echo "  Kernel: Linux $KERNEL"
echo "  Java: $JAVA_TAG"
echo "  /tmp filesystem: $TMP_FS"
echo ""

echo "Library Versions:"
echo "  JMH: $JMH_VERSION"
echo "  LmdbJava: $LMDBJAVA_VERSION"
echo "  LMDBJNI: $LMDBJNI_VERSION"
echo "  LWJGL: $LWJGL_VERSION"
echo "  LevelDB: $LEVELDB_VERSION"
echo "  RocksDB: $ROCKSDB_VERSION"
echo "  MapDB: $MAPDB_VERSION"
echo "  MVStore: $MVSTORE_VERSION"
echo "  Xodus: $XODUS_VERSION"
echo "  Chronicle Map: $CHRONICLE_VERSION"
echo ""

# Start generating HTML report
emit_html_header "LmdbJava Library Comparison Benchmarks" > index.html
echo "  <h1>LmdbJava Library Comparison Benchmarks</h1>" >> index.html

cat >> index.html <<EOHTML

  <p>This report provides a performance evaluation of embedded key-value stores
  available to Java applications. The benchmark tests various workload sizes with
  RAM-based auto-scaling (capped at 1 million entries), testing different value
  sizes, access patterns, and implementation-specific configurations.</p>

EOHTML

emit_smoketest_warning "$BENCH_MODE" >> index.html

cat >> index.html <<EOHTML

  <h2>Methodology</h2>

  <p>The benchmark was executed on ${BENCH_DATE} using
  <a href="https://github.com/lmdbjava/benchmarks">LmdbJava Benchmarks</a> with the
  following configuration:</p>

  <h3>Libraries Tested</h3>

  <table>
    <thead>
      <tr><th>Library</th><th>Version</th><th>Abbreviation</th></tr>
    </thead>
    <tbody>
      <tr><td><a href="https://github.com/lmdbjava/lmdbjava">LmdbJava</a> (ByteBuffer)</td><td>${LMDBJAVA_VERSION}</td><td>LMDB BB</td></tr>
      <tr><td><a href="https://github.com/lmdbjava/lmdbjava">LmdbJava</a> (Agrona DirectBuffer)</td><td>${LMDBJAVA_VERSION}</td><td>LMDB DB</td></tr>
      <tr><td><a href="https://github.com/deephacks/lmdbjni">LMDBJNI</a></td><td>${LMDBJNI_VERSION}</td><td>LMDB JNI</td></tr>
      <tr><td><a href="https://github.com/LWJGL/lwjgl3/">LWJGL</a></td><td>${LWJGL_VERSION}</td><td>LMDB JGL</td></tr>
      <tr><td><a href="https://github.com/fusesource/leveldbjni">LevelDB</a></td><td>${LEVELDB_VERSION}</td><td>LevelDB</td></tr>
      <tr><td><a href="http://rocksdb.org/">RocksDB</a></td><td>${ROCKSDB_VERSION}</td><td>RocksDB</td></tr>
      <tr><td><a href="http://www.mapdb.org/">MapDB</a></td><td>${MAPDB_VERSION}</td><td>MapDB</td></tr>
      <tr><td><a href="http://h2database.com/html/mvstore.html">MVStore</a></td><td>${MVSTORE_VERSION}</td><td>MVStore</td></tr>
      <tr><td><a href="https://github.com/JetBrains/xodus">Xodus</a></td><td>${XODUS_VERSION}</td><td>Xodus</td></tr>
      <tr><td><a href="https://github.com/OpenHFT/Chronicle-Map">Chronicle Map</a></td><td>${CHRONICLE_VERSION}</td><td>Chronicle</td></tr>
    </tbody>
  </table>

EOHTML

emit_system_environment "$CPU_MODEL" "$CPU_COUNT" "$RAM_GIB" "$KERNEL" "$JAVA_TAG" >> index.html

cat >> index.html <<EOHTML

  <h3>Benchmark Configuration</h3>
  <ul>
    <li><strong>JMH:</strong> ${JMH_VERSION}</li>
    <li><strong>Temp Directory:</strong> /tmp (${TMP_FS})</li>
  </ul>

  <p>All benchmarks were executed by <a href="http://openjdk.java.net/projects/code-tools/jmh/">JMH</a>
  with default operating system and JVM configuration. The <code>/tmp</code> directory was
  used as the work directory during each benchmark.</p>

  <h2>Benchmark Operations</h2>

  <p>The following operations are measured:</p>

  <ul>
    <li>🟣 <code>readKey</code>: Fetch each entry by presenting its key</li>
    <li>🟠 <code>write</code>: Bulk insert entries into the store</li>
    <li>🟢 <code>readXxh64</code>: Iterate over entries computing XXH64 hash of keys and values</li>
    <li>🔵 <code>readSeq</code>: Iterate over key-ordered entries in forward order</li>
    <li>🟡 <code>readRev</code>: Iterate over key-ordered entries in reverse order</li>
    <li>🔴 <code>readCrc</code>: Iterate over entries computing CRC32 of keys and values</li>
  </ul>

  <h2>Terminology</h2>

  <ul>
    <li><strong>Int</strong>: 32-bit signed integer key (4 bytes)</li>
    <li><strong>Str</strong>: 16-byte zero-padded string key (no length prefix or null terminator)</li>
    <li><strong>Seq</strong>: Sequential data access (ordered integers)</li>
    <li><strong>Rnd</strong>: Random data access (integers from Mersenne Twister)</li>
  </ul>

  <p>All storage sizes reflect actual bytes consumed on disk (via POSIX stat), not
  apparent size. Chronicle Map only supports <code>readKey</code> and <code>write</code> benchmarks
  as it does not provide ordered key iteration.</p>

EOHTML

echo "Processing Run 1: LMDB Configuration Options..."

# Extract Run 1 data for forceSafe comparison (pure jq, no awk)
# Get LMDB ByteBuffer read benchmarks with different forceSafe settings
jq -r '.[] | select(.benchmark | contains("LmdbJavaByteBuffer")) |
  select(.benchmark | contains("read")) |
  select(.params.writeMap == "true") |
  (.benchmark | split(".")[-1]) as $bench |
  (if .params.forceSafe == "true" then "safe" else "unsafe" end) as $label |
  "\($bench)-\($label) \(.primaryMetric.score)"' out-libs-1.json | sort > 1-forceSafe-reads.dat

# Add color codes to the forceSafe data based on benchmark type
awk '{
  bench = $1;
  value = $2;
  if (bench ~ /^readCrc-/) color = "0xe41a1c";
  else if (bench ~ /^readKey-/) color = "0x984ea3";
  else if (bench ~ /^readRev-/) color = "0xffff33";
  else if (bench ~ /^readSeq-/) color = "0x377eb8";
  else if (bench ~ /^readXxh64-/) color = "0x4daf4a";
  else color = "0x000000";
  print bench, value, color;
}' 1-forceSafe-reads.dat > 1-forceSafe-colored.dat

# Create gnuplot script for forceSafe with individual colors per bar
cat > 1-forceSafe.gnuplot <<'GNUPLOT'
set terminal svg size 800,600
set output '1-forceSafe-reads.svg'
set title "LmdbJava ByteBuffer Safe vs Unsafe Overhead"
set xlabel ""
set ylabel "ms / operation"
set style fill solid 0.25 border
set boxwidth 0.5
set xtics nomirror rotate by -270
set grid y
plot '1-forceSafe-colored.dat' using 0:2:3:xtic(1) with boxes lc rgbcolor variable notitle
GNUPLOT

gnuplot 1-forceSafe.gnuplot
rm -f 1-forceSafe.gnuplot 1-forceSafe-colored.dat

echo "  Generated 1-forceSafe-reads.svg"

# Extract sync comparison data (write benchmarks only)
# Only use LMDB implementations, compare sync vs nosync with writeMap=true
jq -r '.[] | select(.benchmark | contains(".write")) |
  select(.benchmark | contains("Lmdb")) |
  select(.params.writeMap == "true") |
  select(.params.sync) |
  (.benchmark | split(".")[3] |
    if . == "LmdbJavaAgrona" then "LMDB DB"
    elif . == "LmdbJavaByteBuffer" then "LMDB BB"
    elif . == "LmdbJni" then "LMDB JNI"
    elif . == "LmdbLwjgl" then "LMDB JGL"
    else . end) as $impl |
  (if .params.sync == "true" then "sync" else "nosync" end) as $sync |
  "\($impl) (\($sync)) \(.primaryMetric.score)"' out-libs-1.json | sort > 1-sync-writes.dat

cat > 1-sync.gnuplot <<'GNUPLOT'
set terminal svg size 800,600
set output '1-sync-writes.svg'
set title "LMDB Sync Impact on Writes"
set xlabel ""
set ylabel "ms / operation"
set style fill solid 0.25 border
set boxwidth 0.5
set xtics nomirror rotate by -270
set grid y
plot '1-sync-writes.dat' using 4:xticlabels(sprintf("%s %s %s", stringcolumn(1), stringcolumn(2), stringcolumn(3))) with boxes lc rgb "#ff7f00" notitle
GNUPLOT

gnuplot 1-sync.gnuplot
rm 1-sync.gnuplot

echo "  Generated 1-sync-writes.svg"

# Extract writeMap comparison data
# Only use LMDB implementations, compare writeMap on/off with sync=false
jq -r '.[] | select(.benchmark | contains(".write")) |
  select(.benchmark | contains("Lmdb")) |
  select(.params.sync == "false") |
  select(.params.writeMap) |
  (.benchmark | split(".")[3] |
    if . == "LmdbJavaAgrona" then "LMDB DB"
    elif . == "LmdbJavaByteBuffer" then "LMDB BB"
    elif . == "LmdbJni" then "LMDB JNI"
    elif . == "LmdbLwjgl" then "LMDB JGL"
    else . end) as $impl |
  (if .params.writeMap == "true" then "wm" else "!wm" end) as $wmap |
  "\($impl) (\($wmap)) \(.primaryMetric.score)"' out-libs-1.json | sort > 1-writeMap-writes.dat

cat > 1-writeMap.gnuplot <<'GNUPLOT'
set terminal svg size 800,600
set output '1-writeMap-writes.svg'
set title "LMDB Write Map Impact"
set xlabel ""
set ylabel "ms / operation"
set style fill solid 0.25 border
set boxwidth 0.5
set xtics nomirror rotate by -270
set grid y
plot '1-writeMap-writes.dat' using 4:xticlabels(sprintf("%s %s %s", stringcolumn(1), stringcolumn(2), stringcolumn(3))) with boxes lc rgb "#ff7f00" notitle
GNUPLOT

gnuplot 1-writeMap.gnuplot
rm 1-writeMap.gnuplot

echo "  Generated 1-writeMap-writes.svg"

# Append Run 1 section to HTML
cat >> index.html <<'EOHTML'

  <h2>Run 1: LMDB Configuration Options</h2>

  <p>This run tests various LMDB implementation options using 100-byte values to
  determine optimal settings for subsequent benchmarks. All tests use sequential
  integer keys.</p>

  <h3>Force Safe</h3>

  <figure>
    <img src="1-forceSafe-reads.svg" alt="LmdbJava ByteBuffer Safe vs Unsafe Overhead" style="max-width: 100%; height: auto;">
  </figure>

  <p>LmdbJava supports multiple buffer types including Java's <code>ByteBuffer</code> in both
  safe and unsafe modes. The unsafe mode (default) uses <code>sun.misc.Unsafe</code> for
  direct memory access. The graph shows consistent overhead when forcing safe
  mode, confirming that unsafe mode provides better performance and should be
  used for production workloads.</p>

  <h3>Sync</h3>

  <figure>
    <img src="1-sync-writes.svg" alt="LMDB Sync Impact on Writes" style="max-width: 100%; height: auto;">
  </figure>

  <p>This graph shows the impact of LMDB's <code>MDB_NOSYNC</code> flag on write performance.
  As expected, requiring fsync on every transaction commit is significantly slower
  than allowing the OS to manage sync operations. For maximum write performance,
  sync is disabled in subsequent benchmarks.</p>

  <h3>Write Map</h3>

  <figure>
    <img src="1-writeMap-writes.svg" alt="LMDB Write Map Impact" style="max-width: 100%; height: auto;">
  </figure>

  <p>LMDB's <code>MDB_WRITEMAP</code> flag enables a writable memory map, improving write
  performance by allowing direct writes to the mapped region. The graph confirms
  that enabling write map improves write latency across all LMDB implementations.
  This setting is enabled for all subsequent benchmarks.</p>

EOHTML

echo "Processing Run 2: Page Boundary Alignment..."

# Run 2: Extract storage bytes from TXT file for random access
grep 'sequential-false' out-libs-2.txt | grep 'after-close' | sed -r 's/Bytes\tafter-close\t([0-9]+)\torg.lmdbjava.bench.([a-z|A-Z]+).*-valSize-([0-9]+).*/\3|\2|\1/g' | \
  sed 's/LmdbJavaAgrona/LMDB_DB/g' | \
  sed 's/LevelDb/LevelDB/g' | \
  sed 's/RocksDb/RocksDB/g' | \
  sort -t'|' -k2,2 -k1,1n | \
  awk -F'|' '{gsub(/_/, " ", $2); print $3, "\"" $2, $1 "\""}' > 2-size.dat

cat > 2-size.gnuplot <<'GNUPLOT'
set terminal svg size 1200,600
set output '2-size.svg'
set title "Native Library Disk Use 1M Random Integer Keys X Approx 2-16 KB Values"
set xlabel ""
set ylabel "Bytes"
set style fill solid 0.25 border
set boxwidth 0.5
set xtics nomirror rotate by -270
set grid y
plot '2-size.dat' using 1:xtic(2) with boxes notitle
GNUPLOT

gnuplot 2-size.gnuplot
rm 2-size.gnuplot

echo "  Generated 2-size.svg"

# Append Run 2 section to HTML
cat >> index.html <<'EOHTML'

  <h2>Run 2: Determine ~2/4/8/16 KB Byte Values</h2>

  <p>Some of the later runs require larger value sizes in order to explore behaviour
  at higher memory workloads. This run was therefore focused on finding reasonable
  byte values around 2, 4, 8 and 16 KB. Only the native implementations were
  benchmarked.</p>

  <p>This benchmark wrote randomly-ordered integer keys, with value sizes as indicated
  on the horizontal axis.</p>

  <figure>
    <img src="2-size.svg" alt="Native Library Disk Use" style="max-width: 100%; height: auto;">
  </figure>

  <p>As shown, LevelDB and RocksDB achieve consistent performance across value sizes.
  LMDB shows degradation if entry sizes are not well-aligned with its page size.
  Exceeding the entry size by a single byte requires an additional page. For
  example, moving from 2,026 byte values (2,030 byte entry including the 4 byte
  integer key) to 2,027 byte values causes increased storage requirements. If
  storage space is an issue, entry sizes should reflect LMDB page sizing
  requirements. Optimal entry sizes are (in bytes) 2,030, 4,084, 8,180, 12,276 and
  so on in 4,096 byte increments.</p>

  <p>Given there is no disadvantage to LevelDB or RocksDB by using entry sizes that
  align well with LMDB page sizes, these will be used in later runs. Ensuring
  overall storage requirements are similar also enables a more reasonable comparison
  of each implementation's performance (as distinct from storage) trade-offs.</p>

EOHTML

echo "Processing Run 3: LSM Batch Size Optimization..."

# Run 3: Extract write performance for different batch sizes
jq -r '.[] | select(.benchmark | contains(".write")) |
  (.benchmark | split(".")[3] |
    if . == "LevelDb" then "LevelDB"
    elif . == "RocksDb" then "RocksDB"
    else . end) as $impl |
  (.params.batchSize | tonumber / 1000000 | tostring) as $batch |
  "\($impl) \($batch)M \(.primaryMetric.score)"' out-libs-3.json | \
  sort -k1,1 -k2,2n > 3-batchSize-writes.dat

cat > 3-batchSize.gnuplot <<'GNUPLOT'
set terminal svg size 800,600
set output '3-batchSize-writes.svg'
set title "Native LSM Write Speed by Batch Size (Sequential Integer Keys X 8,176 Byte Values)"
set xlabel "Batch Size"
set ylabel "ms / operation"
set style fill solid 0.25 border
set boxwidth 0.5
set xtics nomirror rotate by -270
set grid y
plot '3-batchSize-writes.dat' using 3:xticlabels(sprintf("%s %s", stringcolumn(1), stringcolumn(2))) with boxes lc rgb "#ff7f00" notitle
GNUPLOT

gnuplot 3-batchSize.gnuplot
rm 3-batchSize.gnuplot

echo "  Generated 3-batchSize-writes.svg"

# Append Run 3 section to HTML
cat >> index.html <<'EOHTML'

  <h2>Run 3: LevelDB and RocksDB Batch Sizes</h2>

  <p>LevelDB and RocksDB are both LSM-based stores and benefit from inserting data in
  batches. Both implementations handled large value sizes with a variety of very
  large batch sizes. The graph below illustrates the batch size impact when writing
  sequential integer keys X 8,176 byte values.</p>

  <figure>
    <img src="3-batchSize-writes.svg" alt="Native LSM Write Speed by Batch Size" style="max-width: 100%; height: auto;">
  </figure>

  <p>Testing found that RocksDB failed with insufficient file handles when using
  large batch sizes. This was overcome with system configuration adjustments. It
  is therefore important to consider the impact of LSM-based implementations on
  servers with file handle constraints. Such constraints may be related to memory,
  competing uses or security policies.</p>

  <p>One limitation of this report is it only measures the time taken for the client
  thread to complete a given read or write workload. The LSM-based implementations
  also use a separate compaction thread to rewrite the data. This thread overhead
  is therefore not measured by the benchmark and not reported here. Given the
  compaction thread remains very busy during sustained write operations, the
  LSM-based implementations reduce the availability of a second core for end user
  application workloads. This may be of concern on CPU-constrained servers.</p>

  <p>Finally, LSM-based implementations typically offer considerable tuning options.
  Users are expected to tune the store based on their workload type, storage type
  and file system configuration. Such extensive tuning was not conducted in this
  benchmark because the workload was very comfortably memory-bound and an effort
  had already been made to determine reasonable batch sizes. A production LSM
  deployment will need to tune these parameters carefully. A key feature of the
  non-LSM implementations is they do not require such tuning.</p>

EOHTML

echo "Processing Run 4: All Libraries with 100 Byte Values..."

# Get the actual number of entries from Run 4
NUM_ENTRIES=$(jq -r '.[0].params.num' out-libs-4.json)
FLAT_ARRAY_SIZE=$((NUM_ENTRIES * 104))

# Extract storage size for intKey-true, sequential-false (random access)
echo "${FLAT_ARRAY_SIZE} \"(Flat Array)\"" > 4-size-sorted.dat
grep 'intKey-true-num-'${NUM_ENTRIES}'-sequential-false' out-libs-4.txt | grep 'after-close' | \
  sed -r 's/Bytes\tafter-close\t([0-9]+)\torg.lmdbjava.bench.([a-z|A-Z]+).*/\1|\2/g' | \
  sed 's/LmdbJavaAgrona/LMDB_DB/g' | \
  sed 's/LmdbJavaByteBuffer/LMDB_BB/g' | \
  sed 's/LmdbJni/LMDB_JNI/g' | \
  sed 's/LmdbLwjgl/LMDB_JGL/g' | \
  sed 's/LevelDb/LevelDB/g' | \
  sed 's/RocksDb/RocksDB/g' | \
  sed 's/MapDb/MapDB/g' | \
  sed 's/MvStore/MVStore/g' | \
  awk -F'|' '!seen[$2]++ {
    gsub(/_/, " ", $2);
    print $1, "\"" $2 "\"";
  }' | \
  sort -n >> 4-size-sorted.dat

# Generate storage table
cat > 4-size.html <<EOF
  <table>
    <thead>
      <tr><th>Implementation</th><th>Bytes</th><th>Overhead %</th></tr>
    </thead>
    <tbody>
EOF

awk -v base=$(head -n 1 4-size-sorted.dat | cut -d " " -f 1) '
{
  size = $1;
  impl = substr($0, index($0, $2));
  gsub(/"/, "", impl);
  overhead = (size - base) / base * 100;

  # Format size with commas
  size_str = sprintf("%d", size);
  len = length(size_str);
  formatted_size = "";
  for (i = 1; i <= len; i++) {
    formatted_size = formatted_size substr(size_str, i, 1);
    if ((len - i) % 3 == 0 && i != len) formatted_size = formatted_size ",";
  }

  printf "      <tr><td>%s</td><td>%s</td><td>%.2f</td></tr>\n", impl, formatted_size, overhead;
}' 4-size-sorted.dat >> 4-size.html

cat >> 4-size.html <<'EOF'
    </tbody>
  </table>
EOF

cat > 4-size.gnuplot <<'GNUPLOT'
set terminal svg size 800,600
set output '4-size.svg'
set title "Library Disk Use Random Integer Keys X 100 Byte Values"
set xlabel ""
set ylabel "Bytes (log)"
set logscale y
set style fill solid 0.25 border
set boxwidth 0.5
set xtics nomirror rotate by -270
set grid y
plot '4-size-sorted.dat' using 1:xtic(2) with boxes notitle
GNUPLOT

gnuplot 4-size.gnuplot
rm 4-size.gnuplot

echo "  Generated 4-size.svg and 4-size.html"

# Extract Run 4 performance data for intKey-seq (integer keys, sequential access)
jq -r '.[] | select(.params.intKey == "true") |
  select(.params.sequential == "true") |
  select(.params.num == "'${NUM_ENTRIES}'") |
  (.benchmark | split(".")[-1]) as $bench |
  (.benchmark | split(".")[3] |
    if . == "LmdbJavaAgrona" then "LMDB DB"
    elif . == "LmdbJavaByteBuffer" then "LMDB BB"
    elif . == "LmdbJni" then "LMDB JNI"
    elif . == "LmdbLwjgl" then "LMDB JGL"
    elif . == "LevelDb" then "LevelDB"
    elif . == "RocksDb" then "RocksDB"
    elif . == "MapDb" then "MapDB"
    elif . == "MvStore" then "MVStore"
    else . end) as $impl |
  "true \"\($bench).\($impl)\" true \(.primaryMetric.score)"' out-libs-4.json > 4-intKey-seq-all.dat

# Split by benchmark type and remove benchmark prefix from labels
for BENCH in readCrc readKey readRev readSeq readXxh64 write; do
  grep "\"${BENCH}\." 4-intKey-seq-all.dat | sed "s/\"${BENCH}\./\"/g" > 4-intKey-seq-${BENCH}.dat
done

# Create multiplot gnuplot script
cat > 4-intKey-seq.gnuplot <<'GNUPLOT'
set terminal svg size 1000,700
set output '4-intKey-seq.svg'
set logscale y
set style fill solid 0.25 border
set boxwidth 0.5
set grid y

set multiplot layout 2,3 title "Sequential Integer Keys X 100 Byte Values"

set ylabel "ms / operation (log)"
set xlabel ""
set xtics nomirror rotate by -270
set title "Read by Key"
set style fill solid 0.25 border
plot '4-intKey-seq-readKey.dat' using 4:xtic(2) with boxes lc rgb "#984ea3" notitle

set title "Write Entry"
set style fill solid 0.25 border
plot '4-intKey-seq-write.dat' using 4:xtic(2) with boxes lc rgb "#ff7f00" notitle

set title "Calculate xxHash64"
set style fill solid 0.25 border
plot '4-intKey-seq-readXxh64.dat' using 4:xtic(2) with boxes lc rgb "#4daf4a" notitle

set title "Iterate Sequentially"
set style fill solid 0.25 border
plot '4-intKey-seq-readSeq.dat' using 4:xtic(2) with boxes lc rgb "#377eb8" notitle

set title "Iterate Reverse"
set style fill solid 0.25 border
plot '4-intKey-seq-readRev.dat' using 4:xtic(2) with boxes lc rgb "#ffff33" notitle

set title "Calculate CRC32"
set style fill solid 0.25 border
plot '4-intKey-seq-readCrc.dat' using 4:xtic(2) with boxes lc rgb "#e41a1c" notitle

unset multiplot
GNUPLOT

gnuplot 4-intKey-seq.gnuplot
rm -f 4-intKey-seq.gnuplot
rm -f 4-intKey-seq-*.dat 4-intKey-seq-all.dat

echo "  Generated 4-intKey-seq.svg"

# Extract Run 4 performance data for strKey-seq (string keys, sequential access)
jq -r '.[] | select(.params.intKey == "false") |
  select(.params.sequential == "true") |
  select(.params.num == "'${NUM_ENTRIES}'") |
  (.benchmark | split(".")[-1]) as $bench |
  (.benchmark | split(".")[3] |
    if . == "LmdbJavaAgrona" then "LMDB DB"
    elif . == "LmdbJavaByteBuffer" then "LMDB BB"
    elif . == "LmdbJni" then "LMDB JNI"
    elif . == "LmdbLwjgl" then "LMDB JGL"
    elif . == "LevelDb" then "LevelDB"
    elif . == "RocksDb" then "RocksDB"
    elif . == "MapDb" then "MapDB"
    elif . == "MvStore" then "MVStore"
    else . end) as $impl |
  "false \"\($bench).\($impl)\" true \(.primaryMetric.score)"' out-libs-4.json > 4-strKey-seq-all.dat

# Split by benchmark type and remove benchmark prefix from labels
for BENCH in readCrc readKey readRev readSeq readXxh64 write; do
  grep "\"${BENCH}\." 4-strKey-seq-all.dat | sed "s/\"${BENCH}\./\"/g" > 4-strKey-seq-${BENCH}.dat
done

# Create multiplot gnuplot script
cat > 4-strKey-seq.gnuplot <<'GNUPLOT'
set terminal svg size 1000,700
set output '4-strKey-seq.svg'
set logscale y
set style fill solid 0.25 border
set boxwidth 0.5
set grid y

set multiplot layout 2,3 title "Sequential String Keys X 100 Byte Values"

set ylabel "ms / operation (log)"
set xlabel ""
set xtics nomirror rotate by -270
set title "Read by Key"
set style fill solid 0.25 border
plot '4-strKey-seq-readKey.dat' using 4:xtic(2) with boxes lc rgb "#984ea3" notitle

set title "Write Entry"
set style fill solid 0.25 border
plot '4-strKey-seq-write.dat' using 4:xtic(2) with boxes lc rgb "#ff7f00" notitle

set title "Calculate xxHash64"
set style fill solid 0.25 border
plot '4-strKey-seq-readXxh64.dat' using 4:xtic(2) with boxes lc rgb "#4daf4a" notitle

set title "Iterate Sequentially"
set style fill solid 0.25 border
plot '4-strKey-seq-readSeq.dat' using 4:xtic(2) with boxes lc rgb "#377eb8" notitle

set title "Iterate Reverse"
set style fill solid 0.25 border
plot '4-strKey-seq-readRev.dat' using 4:xtic(2) with boxes lc rgb "#ffff33" notitle

set title "Calculate CRC32"
set style fill solid 0.25 border
plot '4-strKey-seq-readCrc.dat' using 4:xtic(2) with boxes lc rgb "#e41a1c" notitle

unset multiplot
GNUPLOT

gnuplot 4-strKey-seq.gnuplot
rm -f 4-strKey-seq.gnuplot
rm -f 4-strKey-seq-*.dat 4-strKey-seq-all.dat

echo "  Generated 4-strKey-seq.svg"

# Extract Run 4 performance data for intKey-rnd (integer keys, random access)
jq -r '.[] | select(.params.intKey == "true") |
  select(.params.sequential == "false") |
  select(.params.num == "'${NUM_ENTRIES}'") |
  (.benchmark | split(".")[-1]) as $bench |
  (.benchmark | split(".")[3] |
    if . == "LmdbJavaAgrona" then "LMDB DB"
    elif . == "LmdbJavaByteBuffer" then "LMDB BB"
    elif . == "LmdbJni" then "LMDB JNI"
    elif . == "LmdbLwjgl" then "LMDB JGL"
    elif . == "LevelDb" then "LevelDB"
    elif . == "RocksDb" then "RocksDB"
    elif . == "MapDb" then "MapDB"
    elif . == "MvStore" then "MVStore"
    else . end) as $impl |
  "true \"\($bench).\($impl)\" false \(.primaryMetric.score)"' out-libs-4.json > 4-intKey-rnd-all.dat

# Split by benchmark type and remove benchmark prefix from labels
for BENCH in readCrc readKey readRev readSeq readXxh64 write; do
  grep "\"${BENCH}\." 4-intKey-rnd-all.dat | sed "s/\"${BENCH}\./\"/g" > 4-intKey-rnd-${BENCH}.dat
done

# Create multiplot gnuplot script
cat > 4-intKey-rnd.gnuplot <<'GNUPLOT'
set terminal svg size 1000,700
set output '4-intKey-rnd.svg'
set logscale y
set style fill solid 0.25 border
set boxwidth 0.5
set grid y

set multiplot layout 2,3 title "Random Integer Keys X 100 Byte Values"

set ylabel "ms / operation (log)"
set xlabel ""
set xtics nomirror rotate by -270
set title "Read by Key"
set style fill solid 0.25 border
plot '4-intKey-rnd-readKey.dat' using 4:xtic(2) with boxes lc rgb "#984ea3" notitle

set title "Write Entry"
set style fill solid 0.25 border
plot '4-intKey-rnd-write.dat' using 4:xtic(2) with boxes lc rgb "#ff7f00" notitle

set title "Calculate xxHash64"
set style fill solid 0.25 border
plot '4-intKey-rnd-readXxh64.dat' using 4:xtic(2) with boxes lc rgb "#4daf4a" notitle

set title "Iterate Sequentially"
set style fill solid 0.25 border
plot '4-intKey-rnd-readSeq.dat' using 4:xtic(2) with boxes lc rgb "#377eb8" notitle

set title "Iterate Reverse"
set style fill solid 0.25 border
plot '4-intKey-rnd-readRev.dat' using 4:xtic(2) with boxes lc rgb "#ffff33" notitle

set title "Calculate CRC32"
set style fill solid 0.25 border
plot '4-intKey-rnd-readCrc.dat' using 4:xtic(2) with boxes lc rgb "#e41a1c" notitle

unset multiplot
GNUPLOT

gnuplot 4-intKey-rnd.gnuplot
rm -f 4-intKey-rnd.gnuplot
rm -f 4-intKey-rnd-*.dat 4-intKey-rnd-all.dat

echo "  Generated 4-intKey-rnd.svg"

# Extract Run 4 performance data for strKey-rnd (string keys, random access)
jq -r '.[] | select(.params.intKey == "false") |
  select(.params.sequential == "false") |
  select(.params.num == "'${NUM_ENTRIES}'") |
  (.benchmark | split(".")[-1]) as $bench |
  (.benchmark | split(".")[3] |
    if . == "LmdbJavaAgrona" then "LMDB DB"
    elif . == "LmdbJavaByteBuffer" then "LMDB BB"
    elif . == "LmdbJni" then "LMDB JNI"
    elif . == "LmdbLwjgl" then "LMDB JGL"
    elif . == "LevelDb" then "LevelDB"
    elif . == "RocksDb" then "RocksDB"
    elif . == "MapDb" then "MapDB"
    elif . == "MvStore" then "MVStore"
    else . end) as $impl |
  "false \"\($bench).\($impl)\" false \(.primaryMetric.score)"' out-libs-4.json > 4-strKey-rnd-all.dat

# Split by benchmark type and remove benchmark prefix from labels
for BENCH in readCrc readKey readRev readSeq readXxh64 write; do
  grep "\"${BENCH}\." 4-strKey-rnd-all.dat | sed "s/\"${BENCH}\./\"/g" > 4-strKey-rnd-${BENCH}.dat
done

# Create multiplot gnuplot script
cat > 4-strKey-rnd.gnuplot <<'GNUPLOT'
set terminal svg size 1000,700
set output '4-strKey-rnd.svg'
set logscale y
set style fill solid 0.25 border
set boxwidth 0.5
set grid y

set multiplot layout 2,3 title "Random String Keys X 100 Byte Values"

set ylabel "ms / operation (log)"
set xlabel ""
set xtics nomirror rotate by -270
set title "Read by Key"
set style fill solid 0.25 border
plot '4-strKey-rnd-readKey.dat' using 4:xtic(2) with boxes lc rgb "#984ea3" notitle

set title "Write Entry"
set style fill solid 0.25 border
plot '4-strKey-rnd-write.dat' using 4:xtic(2) with boxes lc rgb "#ff7f00" notitle

set title "Calculate xxHash64"
set style fill solid 0.25 border
plot '4-strKey-rnd-readXxh64.dat' using 4:xtic(2) with boxes lc rgb "#4daf4a" notitle

set title "Iterate Sequentially"
set style fill solid 0.25 border
plot '4-strKey-rnd-readSeq.dat' using 4:xtic(2) with boxes lc rgb "#377eb8" notitle

set title "Iterate Reverse"
set style fill solid 0.25 border
plot '4-strKey-rnd-readRev.dat' using 4:xtic(2) with boxes lc rgb "#ffff33" notitle

set title "Calculate CRC32"
set style fill solid 0.25 border
plot '4-strKey-rnd-readCrc.dat' using 4:xtic(2) with boxes lc rgb "#e41a1c" notitle

unset multiplot
GNUPLOT

gnuplot 4-strKey-rnd.gnuplot
rm -f 4-strKey-rnd.gnuplot
rm -f 4-strKey-rnd-*.dat 4-strKey-rnd-all.dat

echo "  Generated 4-strKey-rnd.svg"

# Append Run 4 section to HTML
cat >> index.html <<'EOHTML'

  <h2>Run 4: All Libraries with Key and Access Pattern Variants</h2>

  <p>This is a comprehensive test of all libraries with 100 byte values, testing
  integer vs string keys and sequential vs random access patterns. The vertical
  (y) axis of each graph uses a log scale.</p>

  <h3>Storage Use</h3>

  <figure>
    <img src="4-size.svg" alt="Library Disk Use" style="max-width: 100%; height: auto;">
  </figure>

EOHTML

cat 4-size.html >> index.html

cat >> index.html <<'EOHTML'

  <p>We begin by reviewing the storage space required by each implementation's
  memory-mapped files. We can see that MVStore, Xodus, Chronicle and LevelDB are
  very efficient, requiring less than 20% overhead to store the data. LMDB
  requires around 89% more bytes than the size of a flat array, due to its B+
  tree layout and copy-on-write page allocation approach. These collectively
  provide higher read performance and LMDB MVCC ACID transactional support. As we
  will see later, this overhead reduces as the value sizes are increased.</p>

  <h3>Sequential Access (Integers)</h3>

  <figure>
    <img src="4-intKey-seq.svg" alt="Sequential Integer Keys" style="max-width: 100%; height: auto;">
  </figure>

  <p>We start with the most mechanically sympathetic workload. If you have integer
  keys and can insert them in sequential order, the above graphs illustrate the
  type of latencies achievable across the various implementations. LMDB is clearly
  the fastest option, even (surprisingly) including writes.</p>

  <h3>Sequential Access (String)</h3>

  <figure>
    <img src="4-strKey-seq.svg" alt="Sequential String Keys" style="max-width: 100%; height: auto;">
  </figure>

  <p>Here we simply run the same benchmark as before, but with string keys instead
  of integer keys. Our string keys are the same integers as our last benchmark,
  but this time they are recorded as a zero-padded string. LMDB continues to
  perform better than any alternative, including for writes. This confirms the
  previous result seen with sequentially-inserted integer keys.</p>

  <h3>Random Access (Integers)</h3>

  <figure>
    <img src="4-intKey-rnd.svg" alt="Random Integer Keys" style="max-width: 100%; height: auto;">
  </figure>

  <p>Next up we farewell mechanical sympathy and apply some random workloads. Here
  we write the keys out in random order, and we read them back (the <code>readKey</code>
  benchmark) in that same random order. The remaining operations are all cursors
  over sequentially-ordered keys. The graphs show LMDB is consistently faster for
  all operations, even including writes.</p>

  <h3>Random Access (Strings)</h3>

  <figure>
    <img src="4-strKey-rnd.svg" alt="Random String Keys" style="max-width: 100%; height: auto;">
  </figure>

  <p>This benchmark is the same as the previous, except with our zero-padded string
  keys. There are no surprises; we see similar results as previously reported.</p>

EOHTML

echo "Processing Run 5: Large Value Testing..."

# Get the actual number of entries from Run 5
NUM_ENTRIES_5=$(jq -r '.[0].params.num' out-libs-5.json)
FLAT_ARRAY_SIZE_5=$((NUM_ENTRIES_5 * 2030))

# Extract storage size for Run 5 (intKey-true, sequential-false, valSize=2026)
echo "${FLAT_ARRAY_SIZE_5} \"(Flat Array)\"" > 5-size-sorted.dat
grep 'intKey-true-num-'${NUM_ENTRIES_5}'-sequential-false.*valSize-2026' out-libs-5.txt | grep 'after-close' | \
  sed -r 's/Bytes\tafter-close\t([0-9]+)\torg.lmdbjava.bench.([a-z|A-Z]+).*/\1|\2/g' | \
  sed 's/LmdbJavaAgrona/LMDB_DB/g' | \
  sed 's/LmdbJavaByteBuffer/LMDB_BB/g' | \
  sed 's/LmdbJni/LMDB_JNI/g' | \
  sed 's/LmdbLwjgl/LMDB_JGL/g' | \
  sed 's/LevelDb/LevelDB/g' | \
  sed 's/RocksDb/RocksDB/g' | \
  sed 's/MapDb/MapDB/g' | \
  awk -F'|' '!seen[$2]++ {
    gsub(/_/, " ", $2);
    print $1, "\"" $2 "\"";
  }' | \
  sort -n >> 5-size-sorted.dat

# Generate storage table
cat > 5-size.html <<EOF
  <table>
    <thead>
      <tr><th>Implementation</th><th>Bytes</th><th>Overhead %</th></tr>
    </thead>
    <tbody>
EOF

awk -v base=$(head -n 1 5-size-sorted.dat | cut -d " " -f 1) '
{
  size = $1;
  impl = substr($0, index($0, $2));
  gsub(/"/, "", impl);
  overhead = (size - base) / base * 100;

  # Format size with commas
  size_str = sprintf("%d", size);
  len = length(size_str);
  formatted_size = "";
  for (i = 1; i <= len; i++) {
    formatted_size = formatted_size substr(size_str, i, 1);
    if ((len - i) % 3 == 0 && i != len) formatted_size = formatted_size ",";
  }

  printf "      <tr><td>%s</td><td>%s</td><td>%.2f</td></tr>\n", impl, formatted_size, overhead;
}' 5-size-sorted.dat >> 5-size.html

cat >> 5-size.html <<'EOF'
    </tbody>
  </table>
EOF

cat > 5-size.gnuplot <<'GNUPLOT'
set terminal svg size 800,600
set output '5-size.svg'
set title "Library Disk Use Random Integer Keys X 2,026 Byte Values"
set xlabel ""
set ylabel "Bytes (log)"
set logscale y
set style fill solid 0.25 border
set boxwidth 0.5
set xtics nomirror rotate by -270
set grid y
plot '5-size-sorted.dat' using 1:xtic(2) with boxes notitle
GNUPLOT

gnuplot 5-size.gnuplot
rm -f 5-size.gnuplot

echo "  Generated 5-size.svg and 5-size.html"

# Extract Run 5 performance data for intKey-seq (integer keys, sequential access)
# Note: Run 5 only has readKey, readSeq, and write (no readCrc, readRev, readXxh64)
jq -r '.[] | select(.params.intKey == "true") |
  select(.params.sequential == "true") |
  select(.params.num == "'${NUM_ENTRIES_5}'") |
  select(.params.valSize == "2026") |
  (.benchmark | split(".")[-1]) as $bench |
  (.benchmark | split(".")[3] |
    if . == "LmdbJavaAgrona" then "LMDB DB"
    elif . == "LmdbJavaByteBuffer" then "LMDB BB"
    elif . == "LmdbJni" then "LMDB JNI"
    elif . == "LmdbLwjgl" then "LMDB JGL"
    elif . == "LevelDb" then "LevelDB"
    elif . == "RocksDb" then "RocksDB"
    elif . == "MapDb" then "MapDB"
    else . end) as $impl |
  "true \"\($bench).\($impl)\" true \(.primaryMetric.score)"' out-libs-5.json > 5-intKey-seq-all.dat

# Split by benchmark type and remove benchmark prefix from labels
for BENCH in readKey readSeq write; do
  grep "\"${BENCH}\." 5-intKey-seq-all.dat | sed "s/\"${BENCH}\./\"/g" > 5-intKey-seq-${BENCH}.dat
done

# Create multiplot gnuplot script (only 3 benchmarks in Run 5)
cat > 5-intKey-seq.gnuplot <<'GNUPLOT'
set terminal svg size 1000,400
set output '5-intKey-seq.svg'
set logscale y
set style fill solid 0.25 border
set boxwidth 0.5
set grid y

set multiplot layout 1,3 title "Sequential Integer Keys X 2,026 Byte Values"

set ylabel "ms / operation (log)"
set xlabel ""
set xtics nomirror rotate by -270
set title "Read by Key"
set style fill solid 0.25 border
plot '5-intKey-seq-readKey.dat' using 4:xtic(2) with boxes lc rgb "#984ea3" notitle

set title "Write Entry"
set style fill solid 0.25 border
plot '5-intKey-seq-write.dat' using 4:xtic(2) with boxes lc rgb "#ff7f00" notitle

set title "Iterate Sequentially"
set style fill solid 0.25 border
plot '5-intKey-seq-readSeq.dat' using 4:xtic(2) with boxes lc rgb "#377eb8" notitle

unset multiplot
GNUPLOT

gnuplot 5-intKey-seq.gnuplot
rm -f 5-intKey-seq.gnuplot
rm -f 5-intKey-seq-*.dat 5-intKey-seq-all.dat

echo "  Generated 5-intKey-seq.svg"

# Extract Run 5 performance data for intKey-rnd (integer keys, random access)
jq -r '.[] | select(.params.intKey == "true") |
  select(.params.sequential == "false") |
  select(.params.num == "'${NUM_ENTRIES_5}'") |
  select(.params.valSize == "2026") |
  (.benchmark | split(".")[-1]) as $bench |
  (.benchmark | split(".")[3] |
    if . == "LmdbJavaAgrona" then "LMDB DB"
    elif . == "LmdbJavaByteBuffer" then "LMDB BB"
    elif . == "LmdbJni" then "LMDB JNI"
    elif . == "LmdbLwjgl" then "LMDB JGL"
    elif . == "LevelDb" then "LevelDB"
    elif . == "RocksDb" then "RocksDB"
    elif . == "MapDb" then "MapDB"
    else . end) as $impl |
  "true \"\($bench).\($impl)\" false \(.primaryMetric.score)"' out-libs-5.json > 5-intKey-rnd-all.dat

# Split by benchmark type and remove benchmark prefix from labels
for BENCH in readKey readSeq write; do
  grep "\"${BENCH}\." 5-intKey-rnd-all.dat | sed "s/\"${BENCH}\./\"/g" > 5-intKey-rnd-${BENCH}.dat
done

# Create multiplot gnuplot script
cat > 5-intKey-rnd.gnuplot <<'GNUPLOT'
set terminal svg size 1000,400
set output '5-intKey-rnd.svg'
set logscale y
set style fill solid 0.25 border
set boxwidth 0.5
set grid y

set multiplot layout 1,3 title "Random Integer Keys X 2,026 Byte Values"

set ylabel "ms / operation (log)"
set xlabel ""
set xtics nomirror rotate by -270
set title "Read by Key"
set style fill solid 0.25 border
plot '5-intKey-rnd-readKey.dat' using 4:xtic(2) with boxes lc rgb "#984ea3" notitle

set title "Write Entry"
set style fill solid 0.25 border
plot '5-intKey-rnd-write.dat' using 4:xtic(2) with boxes lc rgb "#ff7f00" notitle

set title "Iterate Sequentially"
set style fill solid 0.25 border
plot '5-intKey-rnd-readSeq.dat' using 4:xtic(2) with boxes lc rgb "#377eb8" notitle

unset multiplot
GNUPLOT

gnuplot 5-intKey-rnd.gnuplot
rm -f 5-intKey-rnd.gnuplot
rm -f 5-intKey-rnd-*.dat 5-intKey-rnd-all.dat

echo "  Generated 5-intKey-rnd.svg"

# Append Run 5 section to HTML
cat >> index.html <<'EOHTML'

  <h2>Run 5: Large Value Testing</h2>

  <p>This run tests larger value sizes (2,026 bytes) to explore behavior at higher
  memory workloads. Based on Run 4 showing that integer and string keys perform
  effectively the same, this run only includes integer keys. Similarly, to reduce
  execution time, the <code>readRev</code>, <code>readCrc</code> and <code>readXxh64</code> benchmarks are
  excluded (we retain <code>readSeq</code> and <code>readKey</code> to illustrate cursor and direct
  lookup performance).</p>

  <h3>Storage Use</h3>

  <figure>
    <img src="5-size.svg" alt="Library Disk Use 2,026 Byte Values" style="max-width: 100%; height: auto;">
  </figure>

EOHTML

cat 5-size.html >> index.html

cat >> index.html <<'EOHTML'

  <p>All implementations offer much better storage efficiency now that the value
  sizes have increased (from 100 bytes in Run 4 to 2,026 bytes in Run 5).</p>

  <h3>Sequential Access</h3>

  <figure>
    <img src="5-intKey-seq.svg" alt="Sequential 2,026 Byte Values" style="max-width: 100%; height: auto;">
  </figure>

  <p>Starting with the most optimistic scenario of sequential keys, we see LMDB
  out-perform the alternatives for both read and write workloads. Chronicle Map's
  write performance is good, but it should be remembered that it is not
  an index suitable for ordered key iteration.</p>

  <h3>Random Access</h3>

  <figure>
    <img src="5-intKey-rnd.svg" alt="Random 2,026 Byte Values" style="max-width: 100%; height: auto;">
  </figure>

  <p>LMDB easily remains the fastest with random reads. However, random writes
  involving these larger values are a different story, with the two native LSM
  implementations completing the write workloads much faster than LMDB.</p>

EOHTML

echo "Processing Run 6: Very Large Value Testing..."

# Get the actual number of entries from Run 6
NUM_ENTRIES_6=$(jq -r '.[0].params.num' out-libs-6.json)

# Process each value size (4080, 8176, 16368)
for VALSIZE in 4080 8176 16368; do
  ENTRY_SIZE=$((VALSIZE + 4))
  FLAT_ARRAY_SIZE=$((NUM_ENTRIES_6 * ENTRY_SIZE))

  # Extract storage size for this value size
  echo "${FLAT_ARRAY_SIZE} \"(Flat Array)\"" > 6-size-${VALSIZE}-sorted.dat
  grep "intKey-true-num-${NUM_ENTRIES_6}-sequential-false.*valSize-${VALSIZE}" out-libs-6.txt | grep 'after-close' | \
    sed -r 's/Bytes\tafter-close\t([0-9]+)\torg.lmdbjava.bench.([a-z|A-Z]+).*/\1|\2/g' | \
    sed 's/LmdbJavaAgrona/LMDB_DB/g' | \
    sed 's/LevelDb/LevelDB/g' | \
    sed 's/RocksDb/RocksDB/g' | \
    awk -F'|' '!seen[$2]++ {
      gsub(/_/, " ", $2);
      print $1, "\"" $2 "\"";
    }' | \
    sort -n >> 6-size-${VALSIZE}-sorted.dat

  # Generate storage table
  cat > 6-size-${VALSIZE}.html <<EOF
  <table>
    <thead>
      <tr><th>Implementation</th><th>Bytes</th><th>Overhead %</th></tr>
    </thead>
    <tbody>
EOF

  awk -v base=$(head -n 1 6-size-${VALSIZE}-sorted.dat | cut -d " " -f 1) '
  {
    size = $1;
    impl = substr($0, index($0, $2));
    gsub(/"/, "", impl);
    overhead = (size - base) / base * 100;

    # Format size with commas
    size_str = sprintf("%d", size);
    len = length(size_str);
    formatted_size = "";
    for (i = 1; i <= len; i++) {
      formatted_size = formatted_size substr(size_str, i, 1);
      if ((len - i) % 3 == 0 && i != len) formatted_size = formatted_size ",";
    }

    printf "      <tr><td>%s</td><td>%s</td><td>%.2f</td></tr>\n", impl, formatted_size, overhead;
  }' 6-size-${VALSIZE}-sorted.dat >> 6-size-${VALSIZE}.html

  cat >> 6-size-${VALSIZE}.html <<'EOF'
    </tbody>
  </table>
EOF

  # Generate storage chart
  cat > 6-size-${VALSIZE}.gnuplot <<GNUPLOT
set terminal svg size 800,600
set output '6-size-${VALSIZE}.svg'
set title "Library Disk Use Random Integer Keys X ${VALSIZE} Byte Values"
set xlabel ""
set ylabel "Bytes (log)"
set logscale y
set style fill solid 0.25 border
set boxwidth 0.5
set xtics nomirror rotate by -270
set grid y
plot '6-size-${VALSIZE}-sorted.dat' using 1:xtic(2) with boxes notitle
GNUPLOT

  gnuplot 6-size-${VALSIZE}.gnuplot
  rm -f 6-size-${VALSIZE}.gnuplot

  echo "  Generated 6-size-${VALSIZE}.svg and 6-size-${VALSIZE}.html"

  # Extract performance data for this value size (random access only)
  jq -r '.[] | select(.params.intKey == "true") |
    select(.params.sequential == "false") |
    select(.params.num == "'${NUM_ENTRIES_6}'") |
    select(.params.valSize == "'${VALSIZE}'") |
    (.benchmark | split(".")[-1]) as $bench |
    (.benchmark | split(".")[3] |
      if . == "LmdbJavaAgrona" then "LMDB DB"
      elif . == "LevelDb" then "LevelDB"
      elif . == "RocksDb" then "RocksDB"
      else . end) as $impl |
    "true \"\($bench).\($impl)\" false \(.primaryMetric.score)"' out-libs-6.json > 6-intKey-rnd-${VALSIZE}-all.dat

  # Split by benchmark type and remove benchmark prefix from labels
  for BENCH in readKey readSeq write; do
    grep "\"${BENCH}\." 6-intKey-rnd-${VALSIZE}-all.dat | sed "s/\"${BENCH}\./\"/g" > 6-intKey-rnd-${VALSIZE}-${BENCH}.dat
  done

  # Create performance chart
  cat > 6-intKey-rnd-${VALSIZE}.gnuplot <<GNUPLOT
set terminal svg size 1000,400
set output '6-intKey-rnd-${VALSIZE}.svg'
set logscale y
set style fill solid 0.25 border
set boxwidth 0.5
set grid y

set multiplot layout 1,3 title "Random Integer Keys X ${VALSIZE} Byte Values"

set ylabel "ms / operation (log)"
set xlabel ""
set xtics nomirror rotate by -270
set title "Read by Key"
set style fill solid 0.25 border
plot '6-intKey-rnd-${VALSIZE}-readKey.dat' using 4:xtic(2) with boxes lc rgb "#984ea3" notitle

set title "Write Entry"
set style fill solid 0.25 border
plot '6-intKey-rnd-${VALSIZE}-write.dat' using 4:xtic(2) with boxes lc rgb "#ff7f00" notitle

set title "Iterate Sequentially"
set style fill solid 0.25 border
plot '6-intKey-rnd-${VALSIZE}-readSeq.dat' using 4:xtic(2) with boxes lc rgb "#377eb8" notitle

unset multiplot
GNUPLOT

  gnuplot 6-intKey-rnd-${VALSIZE}.gnuplot
  rm -f 6-intKey-rnd-${VALSIZE}.gnuplot
  rm -f 6-intKey-rnd-${VALSIZE}-*.dat

  echo "  Generated 6-intKey-rnd-${VALSIZE}.svg"
done

# Append Run 6 section to HTML
cat >> index.html <<'EOHTML'

  <h2>Run 6: Very Large Value Testing</h2>

  <p>This run explores much larger workloads with 4-16KB value sizes. Given the
  performance of the pure Java sorting implementations (particularly for writes),
  they are not included in Run 6. The unsorted Chronicle Map continues to be
  included. Only random access patterns are tested as they represent the
  worst-case scenario.</p>

  <h3>Random Access of 4,080 Byte Values</h3>

  <h4>Storage</h4>

  <figure>
    <img src="6-size-4080.svg" alt="Library Disk Use 4,080 Byte Values" style="max-width: 100%; height: auto;">
  </figure>

EOHTML

cat 6-size-4080.html >> index.html

cat >> index.html <<'EOHTML'

  <p>With 4,080 byte values, storage efficiency is now excellent.</p>

  <h4>Performance</h4>

  <figure>
    <img src="6-intKey-rnd-4080.svg" alt="Random 4,080 Byte Values" style="max-width: 100%; height: auto;">
  </figure>

  <p>We can see the larger value sizes are starting to equal out the write speeds.
  Chronicle Map continues to write the fastest, but it should be remembered that
  it is not an index suitable for ordered key iteration. LMDB offers the fastest
  read performance.</p>

  <h3>Random Access of 8,176 Byte Values</h3>

  <h4>Storage</h4>

  <figure>
    <img src="6-size-8176.svg" alt="Library Disk Use 8,176 Byte Values" style="max-width: 100%; height: auto;">
  </figure>

EOHTML

cat 6-size-8176.html >> index.html

cat >> index.html <<'EOHTML'

  <p>The trend toward better storage efficiency with larger values has continued.</p>

  <h4>Performance</h4>

  <figure>
    <img src="6-intKey-rnd-8176.svg" alt="Random 8,176 Byte Values" style="max-width: 100%; height: auto;">
  </figure>

  <p>Now that much larger values are in use, we start to see the LSM implementations
  slowed down by write amplification. LMDB offers the fastest reads.</p>

  <h3>Random Access of 16,368 Byte Values</h3>

  <h4>Storage</h4>

  <figure>
    <img src="6-size-16368.svg" alt="Library Disk Use 16,368 Byte Values" style="max-width: 100%; height: auto;">
  </figure>

EOHTML

cat 6-size-16368.html >> index.html

cat >> index.html <<'EOHTML'

  <p>All implementations offer very good storage space efficiency compared with a
  flat array.</p>

  <h4>Performance</h4>

  <figure>
    <img src="6-intKey-rnd-16368.svg" alt="Random 16,368 Byte Values" style="max-width: 100%; height: auto;">
  </figure>

  <p>The write amplification issue seen with the earlier 8,176 byte benchmark
  continues, with the LSM implementations further slowing down.</p>

EOHTML

echo "Processing summary chart for conclusion..."

# Create summary chart based on 4-intKey-seq data without log scale
cat > summary.gnuplot <<'GNUPLOT'
set terminal svg size 1000,700
set output 'summary.svg'
set boxwidth 0.5
set grid y

set multiplot layout 2,3 title "Performance Summary: Sequential Integer Keys with 100 Byte Values\nMilliseconds per Operation (Smaller is Better)"

set ylabel ""
set xlabel ""
set xtics nomirror rotate by -270
set title "Read by Key"
set style fill solid 0.25 border
plot '4-intKey-seq-readKey.dat' using 4:xtic(2) with boxes lc rgb "#984ea3" notitle

set title "Write Entry"
set style fill solid 0.25 border
plot '4-intKey-seq-write.dat' using 4:xtic(2) with boxes lc rgb "#ff7f00" notitle

set title "Calculate xxHash64"
set style fill solid 0.25 border
plot '4-intKey-seq-readXxh64.dat' using 4:xtic(2) with boxes lc rgb "#4daf4a" notitle

set title "Iterate Sequentially"
set style fill solid 0.25 border
plot '4-intKey-seq-readSeq.dat' using 4:xtic(2) with boxes lc rgb "#377eb8" notitle

set title "Iterate Reverse"
set style fill solid 0.25 border
plot '4-intKey-seq-readRev.dat' using 4:xtic(2) with boxes lc rgb "#ffff33" notitle

set title "Calculate CRC32"
set style fill solid 0.25 border
plot '4-intKey-seq-readCrc.dat' using 4:xtic(2) with boxes lc rgb "#e41a1c" notitle

unset multiplot
GNUPLOT

# Need to regenerate the data files since they were cleaned up
jq -r '.[] | select(.params.intKey == "true") |
  select(.params.sequential == "true") |
  select(.params.num == "'${NUM_ENTRIES}'") |
  (.benchmark | split(".")[-1]) as $bench |
  (.benchmark | split(".")[3] |
    if . == "LmdbJavaAgrona" then "LMDB DB"
    elif . == "LmdbJavaByteBuffer" then "LMDB BB"
    elif . == "LmdbJni" then "LMDB JNI"
    elif . == "LmdbLwjgl" then "LMDB JGL"
    elif . == "LevelDb" then "LevelDB"
    elif . == "RocksDb" then "RocksDB"
    elif . == "MapDb" then "MapDB"
    elif . == "MvStore" then "MVStore"
    else . end) as $impl |
  "true \"\($bench).\($impl)\" true \(.primaryMetric.score)"' out-libs-4.json > summary-all.dat

for BENCH in readCrc readKey readRev readSeq readXxh64 write; do
  grep "\"${BENCH}\." summary-all.dat | sed "s/\"${BENCH}\./\"/g" > 4-intKey-seq-${BENCH}.dat
done

gnuplot summary.gnuplot
rm -f summary.gnuplot
rm -f summary-all.dat
rm -f 4-intKey-seq-*.dat

echo "  Generated summary.svg"

cat >> index.html <<'EOHTML'

  <h2>Conclusion</h2>

  <figure>
    <img src="summary.svg" alt="Performance Summary" style="max-width: 100%; height: auto;">
  </figure>

  <p>After testing various workloads across different value sizes, we have seen a
  number of important differences between the implementations.</p>

  <p>Before discussing the ordered key implementations, it is noted that Chronicle
  Map offers a good option for unordered keys. It's consistently fast for both
  reads and writes, plus storage space efficient. Chronicle Map also offers a
  different scope than the other embedded key-value stores in this report. For
  example, it lacks transactions but does offer replication.</p>

  <p>Ordered key implementations were the focus of this report. Those use cases which
  can employ ordered keys will always achieve much better read performance by
  iterating over a cursor. We saw this regardless of entry size, original write
  ordering, or even implementation. It is worth devising a key structure that
  enables ordered iteration whenever possible.</p>

  <p>Pure Java sorting implementations (MapDB, MVStore, Xodus) generally showed
  weaker performance compared with the native implementations (Chronicle Map,
  LMDB, RocksDB and LevelDB). GC tuning may improve these results.</p>

  <p>LMDB was always the fastest implementation for every read workload. This
  is unsurprising given its B+ Tree and copy-on-write design. LMDB's excellent
  read performance is sustained regardless of entry size or access pattern.</p>

  <p>Write workloads show more variation in the results. Small value sizes (100
  bytes) were written more quickly by LMDB than any other sorted key
  implementation. As value sizes increased toward 2 KB, this situation reversed
  and LMDB became much slower than RocksDB and LevelDB. However, once value sizes
  reached the 4 KB region, the differences between LMDB, LevelDB and RocksDB
  diminished significantly. At 8 KB and beyond, LMDB was materially faster for
  writes. This finding is readily explained by the write amplification necessary
  in LSM-based implementations.</p>

  <p>All implementations became more storage space efficient as the value sizes
  increased. LMDB was relatively inefficient at small value sizes (89% overhead
  with 100 byte values) but the overhead became minimal (under 2%) by the time
  values reached 4 KB. Modern Java compression libraries such as
  <a href="https://github.com/lz4/lz4-java">LZ4-Java</a> (for general-purpose cases)
  and <a href="https://github.com/lemire/JavaFastPFOR">JavaFastPFOR</a> (for integers) may
  also provide enhanced storage efficiency by packing related data into chunked,
  compressed values. This may also improve performance in the case of IO
  bottlenecks, as the CPU can decompress while waiting on further IO.</p>

  <p>In terms of broader efficiency, LMDB operates in the same thread as its caller
  and therefore the performance reported above is a total indication of LMDB cost.
  On the other hand, RocksDB and LevelDB use a second thread for write compaction.
  This second thread may compete with application workloads on busy servers. We
  also see a similar efficiency concern around operating system file handle
  consumption. While LMDB only requires two open files, RocksDB and LevelDB both
  require tens to hundreds of thousands of open files to operate.</p>

  <p>The qualitative dimensions of each implementation should also be considered. For
  example, consider recovery time from dirty shutdown (process/OS/server crash),
  ACID transaction guarantees, inter-process usage flexibility, runtime monitoring
  requirements, hot backup support and ongoing configuration effort. In these
  situations LMDB delivers a very strong solution. For more information, see the
  <a href="https://github.com/lmdbjava/lmdbjava">LmdbJava</a> features list.</p>

EOHTML

emit_html_footer >> index.html

echo ""
echo "Report generation complete!"
echo "Generated: $WORK_DIR/index.html"
echo ""
echo "Open $WORK_DIR/index.html in your browser to view the report."

cd - > /dev/null
