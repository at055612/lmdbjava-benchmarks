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

# Pure HTML report generator for LMDB library comparison

# Source common functions
source "$(dirname "$0")/report-common.sh"

DATA_DIR="lmdb/results"
WORK_DIR="target/benchmark"

# Get latest LMDB tag
if [ -f "target/lmdb-latest-tag.txt" ]; then
  LATEST_TAG=$(cat target/lmdb-latest-tag.txt)
else
  LATEST_TAG="LMDB_0.9.33"
fi

# Check prerequisites
JSON_COUNT=$(find "$DATA_DIR" -name "out-lmdb-*.json" 2>/dev/null | wc -l)
if [ $JSON_COUNT -lt 2 ]; then
  echo "ERROR: Need at least 2 LMDB benchmark result files in $DATA_DIR"
  exit 1
fi

echo "Found ${JSON_COUNT} LMDB tag benchmark results"

# Get system info
CPU_MODEL=$(get_cpu_info)
CPU_COUNT=$(get_cpu_count)
RAM_GIB=$(get_total_ram_gib)
KERNEL=$(get_kernel)
JAVA_TAG=$(get_java_version)

FIRST_FILE=$(find "$DATA_DIR" -name "out-lmdb-*.json" 2>/dev/null | head -1)
BENCH_DATE=$(stat -c %y "$FIRST_FILE" | cut -d' ' -f1)
BENCH_MODE=$(get_benchmark_mode "$FIRST_FILE")

mkdir -p "$WORK_DIR"
cp "$DATA_DIR"/out-lmdb-*.json "$WORK_DIR/" 2>/dev/null || true

# Get git metadata before cd (files are in DATA_DIR alongside JSON results)
LMDBJAVA_BRANCH=$(get_lmdbjava_branch "$DATA_DIR")
LMDBJAVA_COMMIT_SHORT=$(get_lmdbjava_commit_short "$DATA_DIR")
LMDBJAVA_COMMIT=$(get_lmdbjava_commit_full "$DATA_DIR")

cd "$WORK_DIR"

# Build LMDB version list
TAGS=()
for f in out-lmdb-*.json; do
  [ -f "$f" ] || continue
  TAG=$(echo "$f" | sed 's/out-lmdb-\(.*\)\.json/\1/')
  TAGS+=("$TAG")
done
IFS=$'\n' TAGS=($(sort -V <<<"${TAGS[*]}"))
unset IFS

echo "Processing benchmarks and generating chart..."

# Extract data and generate chart
for BENCH in readCrc readKey readRev readSeq readXxh64 write; do
  > "lmdb-${BENCH}.dat"
  for TAG in "${TAGS[@]}"; do
    FILE="out-lmdb-${TAG}.json"
    [ -f "$FILE" ] || continue
    SCORE=$(jq -r ".[] | select(.benchmark | contains(\"LmdbJavaAgrona.${BENCH}\")) |
      select(.params.intKey == \"true\") | select(.params.sequential == \"true\") |
      .primaryMetric.score" "$FILE" 2>/dev/null || echo "")
    if [ -n "$SCORE" ]; then
      echo "\"${TAG}\" ${SCORE}" >> "lmdb-${BENCH}.dat"
    fi
  done
done

cat > lmdb-multiplot.gnuplot <<'GNUPLOT'
set terminal svg size 1000,700 noenhanced
set output 'lmdb-comparison.svg'
set style fill solid 0.25 border
set boxwidth 0.5
set grid y
set multiplot layout 2,3 title "LMDB Library Performance Analysis\nMilliseconds per Operation (Smaller is Better)"
set ylabel "ms / operation"
set xlabel ""
set xtics nomirror rotate by -270
set title "Read by Key"
plot 'lmdb-readKey.dat' using 2:xtic(1) with boxes lc rgb "#984ea3" notitle
set title "Write Entry"
plot 'lmdb-write.dat' using 2:xtic(1) with boxes lc rgb "#ff7f00" notitle
set title "Calculate xxHash64"
plot 'lmdb-readXxh64.dat' using 2:xtic(1) with boxes lc rgb "#4daf4a" notitle
set title "Iterate Sequentially"
plot 'lmdb-readSeq.dat' using 2:xtic(1) with boxes lc rgb "#377eb8" notitle
set title "Iterate Reverse"
plot 'lmdb-readRev.dat' using 2:xtic(1) with boxes lc rgb "#ffff33" notitle
set title "Calculate CRC32"
plot 'lmdb-readCrc.dat' using 2:xtic(1) with boxes lc rgb "#e41a1c" notitle
unset multiplot
GNUPLOT

gnuplot lmdb-multiplot.gnuplot
rm -f lmdb-multiplot.gnuplot lmdb-*.dat

echo "Generating HTML report..."

# Generate pure HTML report
emit_html_header "LMDB Library Performance Analysis" > index.html
echo "  <h1>LMDB Library Performance Analysis</h1>" >> index.html
emit_smoketest_warning "$BENCH_MODE" >> index.html

cat >> index.html <<EOHTML

  <figure>
    <img src="lmdb-comparison.svg" alt="LMDB Library Performance Analysis" style="max-width: 100%; height: auto;">
  </figure>

  <h2>Performance Analysis</h2>
  <p>The following tables show each benchmark ranked by performance, with percentage difference from the fastest LMDB library build.
  The <strong>latest tag</strong> (${LATEST_TAG}) is highlighted in bold.</p>

EOHTML

# Generate performance tables
declare -A BENCH_NAMES
BENCH_NAMES[readKey]="Read by Key"
BENCH_NAMES[write]="Write Entry"
BENCH_NAMES[readXxh64]="Calculate xxHash64"
BENCH_NAMES[readSeq]="Iterate Sequentially"
BENCH_NAMES[readRev]="Iterate Reverse"
BENCH_NAMES[readCrc]="Calculate CRC32"

for BENCH in readKey write readXxh64 readSeq readRev readCrc; do
  echo "  <h3>${BENCH_NAMES[$BENCH]}</h3>" >> index.html
  echo "  <table>" >> index.html
  echo "    <thead><tr><th>Rank</th><th>LMDB Tag</th><th>ms/op</th><th>vs Fastest</th></tr></thead>" >> index.html
  echo "    <tbody>" >> index.html
  
  declare -a SCORES
  for TAG in "${TAGS[@]}"; do
    FILE="out-lmdb-${TAG}.json"
    [ -f "$FILE" ] || continue
    SCORE=$(jq -r ".[] | select(.benchmark | contains(\"LmdbJavaAgrona.${BENCH}\")) |
      select(.params.intKey == \"true\") | select(.params.sequential == \"true\") |
      .primaryMetric.score" "$FILE" 2>/dev/null || echo "")
    if [ -n "$SCORE" ]; then
      SCORES+=("$SCORE:$TAG")
    fi
  done
  
  IFS=$'\n' SORTED=($(sort -t: -k1 -n <<<"${SCORES[*]}"))
  unset IFS
  FASTEST_SCORE=$(echo "${SORTED[0]}" | cut -d: -f1)
  
  RANK=1
  for ENTRY in "${SORTED[@]}"; do
    SCORE=$(echo "$ENTRY" | cut -d: -f1)
    TAG=$(echo "$ENTRY" | cut -d: -f2)
    
    if [ "$RANK" -eq 1 ]; then
      if [ "$TAG" = "$LATEST_TAG" ]; then
        DIFF="<strong>baseline</strong>"
      else
        DIFF="baseline"
      fi
    else
      PERCENT=$(awk -v score="$SCORE" -v fastest="$FASTEST_SCORE" 'BEGIN {printf "%.1f", ((score - fastest) / fastest * 100)}')
      if [ "$TAG" = "$LATEST_TAG" ]; then
        DIFF="<strong>+${PERCENT}%</strong>"
      else
        DIFF="+${PERCENT}%"
      fi
    fi
    
    SCORE_FMT=$(printf "%.3f" "$SCORE")
    echo "      <tr><td>$RANK</td><td><code>$TAG</code></td><td>$SCORE_FMT</td><td>$DIFF</td></tr>" >> index.html
    ((RANK++))
  done
  
  echo "    </tbody>" >> index.html
  echo "  </table>" >> index.html
  unset SCORES
done

cat >> index.html <<EOHTML

  <h2>Test Configuration</h2>
  <p>The benchmark was executed on ${BENCH_DATE} using
  <a href="https://github.com/lmdbjava/benchmarks">LmdbJava Benchmarks</a>.</p>
  
  <p>Each test run uses <code>-Dlmdbjava.native.lib</code> to ensure use of a specific LMDB library built from
  the identified LMDB tag. This isolates LmdbJava wrapper code during each benchmark, ensuring the
  only variation is the actual LMDB library.</p>
  
  <p>All tests use the LmdbJava Agrona implementation with the following configuration:</p>

EOHTML

emit_system_environment "$CPU_MODEL" "$CPU_COUNT" "$RAM_GIB" "$KERNEL" \
  "$JAVA_TAG" "$LMDBJAVA_BRANCH" "$LMDBJAVA_COMMIT_SHORT" "$LMDBJAVA_COMMIT" >> index.html

cat >> index.html <<'EOHTML'

  <h3>Benchmark Configuration</h3>
  <ul>
    <li><strong>Implementation:</strong> LmdbJava Agrona only</li>
    <li><strong>Test Profile:</strong> Run 4 sequential integer configuration (100-byte values)</li>
    <li><strong>Key Type:</strong> Sequential 32-bit integers</li>
    <li><strong>Value Size:</strong> 100 bytes</li>
    <li><strong>Access Pattern:</strong> Sequential</li>
    <li><strong>Benchmarks:</strong> All 6 operations (readCrc, readKey, readRev, readSeq, readXxh64, write)</li>
  </ul>
EOHTML

emit_html_footer >> index.html

echo ""
echo "Report generation complete!"
echo "Generated: $WORK_DIR/index.html and $WORK_DIR/lmdb-comparison.svg"
echo ""
echo "Open $WORK_DIR/index.html in your browser to view the report."

cd - > /dev/null
