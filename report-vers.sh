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

# Set data directory (input from run-vers.sh) and output directory
DATA_DIR="target/benchmark-vers"
WORK_DIR="target/benchmark"

# Check prerequisites
echo "Checking for required files..."

# Count available version/branch JSON files (new naming: out-version-*.json, out-branch-*.json)
JSON_COUNT=$(find "$DATA_DIR" -name "out-version-*.json" -o -name "out-branch-*.json" 2>/dev/null | wc -l)

if [ $JSON_COUNT -lt 2 ]; then
  echo "ERROR: Need at least 2 version benchmark result files in $DATA_DIR"
  echo "Please run ./run-vers.sh first to generate version benchmark results"
  exit 1
fi

echo "Found ${JSON_COUNT} version benchmark results"

check_tool() {
  if ! command -v "$1" &> /dev/null; then
    echo "ERROR: $1 is required but not installed"
    return 1
  fi
  return 0
}

echo "Checking for required tools..."
MISSING_TOOLS=0

for TOOL in jq gnuplot awk sed grep sort cut head; do
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
get_cpu_info() {
  grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^[ \t]*//'
}

get_cpu_count() {
  grep -c "^processor" /proc/cpuinfo
}

get_total_ram_gib() {
  awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo
}

get_kernel() {
  uname -r
}

get_java_version() {
  java -version 2>&1 | head -1 | cut -d'"' -f2
}

CPU_MODEL=$(get_cpu_info)
CPU_COUNT=$(get_cpu_count)
RAM_GIB=$(get_total_ram_gib)
KERNEL=$(get_kernel)
JAVA_VERSION=$(get_java_version)

# Get benchmark date from first available file
FIRST_FILE=$(find "$DATA_DIR" -name "out-*.json" -o -name "out-branch-*.json" 2>/dev/null | head -1)
BENCH_DATE=$(stat -c %y "$FIRST_FILE" | cut -d' ' -f1)

# Detect benchmark mode
WARMUP_ITERATIONS=$(jq -r '.[0].warmupIterations' "$FIRST_FILE")
if [ "$WARMUP_ITERATIONS" = "0" ]; then
  BENCH_MODE="smoketest"
else
  BENCH_MODE="benchmark"
fi

# Create output directory and copy benchmark data files
mkdir -p "$WORK_DIR"
cp "$DATA_DIR"/out-*.json "$WORK_DIR/" 2>/dev/null || true

# Change to working directory
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
echo "  Java: $JAVA_VERSION"
echo ""

# Build version list in chronological order
VERSIONS=()
for f in out-version-*.json out-branch-*.json; do
  [ -f "$f" ] || continue
  # Extract version/branch from filename (strip out-version- or out-branch- prefix and .json suffix)
  VERSION=$(echo "$f" | sed 's/out-version-\(.*\)\.json/\1/' | sed 's/out-branch-\(.*\)\.json/branch-\1/')
  VERSIONS+=("$VERSION")
done

# Assign colors to branches
declare -A BRANCH_COLORS
AVAILABLE_COLORS=("#0066CC" "#CC6600" "#009966" "#9933CC" "#CC0066" "#0099CC")
COLOR_INDEX=0

for v in "${VERSIONS[@]}"; do
  if [[ "$v" == branch-* ]]; then
    BRANCH_NAME=$(echo "$v" | sed 's/branch-\([^#]*\)#.*/\1/')
    if [ -z "${BRANCH_COLORS[$BRANCH_NAME]:-}" ]; then
      BRANCH_COLORS[$BRANCH_NAME]="${AVAILABLE_COLORS[$COLOR_INDEX]}"
      ((COLOR_INDEX++))
    fi
  fi
done

echo "Found ${#VERSIONS[@]} versions:"
for v in "${VERSIONS[@]}"; do
  echo "  - $v"
done
echo ""

# Start generating README.md
cat > README.md <<EOF
## LmdbJava Performance Regression Testing

EOF

# Add smoketest warning if applicable
if [ "$BENCH_MODE" = "smoketest" ]; then
  cat >> README.md <<'EOF'
> **⚠️ SMOKETEST RESULTS**
>
> This report was generated from a **smoketest run** and should NOT be used for
> performance comparisons or production decisions. Smoketest results have:
> - No warmup iterations
> - Single iteration
> - Minimal entry counts
> - Short runtime
>
> For valid performance results, run \`./run-vers.sh benchmark\` instead.

EOF
fi

# Color mapping for benchmarks (matching report-libs.sh)
declare -A COLORS
COLORS[readCrc]="#e41a1c"
COLORS[readKey]="#984ea3"
COLORS[readRev]="#ffff33"
COLORS[readSeq]="#377eb8"
COLORS[readXxh32]="#4daf4a"
COLORS[write]="#ff7f00"

# Extract data for each benchmark operation across all versions
for BENCH in readCrc readKey readRev readSeq readXxh32 write; do
  echo "Processing benchmark: ${BENCH}..."

  # Extract scores for this benchmark across all versions
  > "vers-${BENCH}.dat"

  for VERSION in "${VERSIONS[@]}"; do
    # Determine the actual filename based on whether it's a version or branch
    if [[ "$VERSION" == branch-* ]]; then
      # For branches, the VERSION already includes git revision (e.g., branch-master#43ac84f)
      # The file is named out-branch-master#43ac84f.json, so we just use it directly
      FILE="out-${VERSION}.json"
    else
      FILE="out-version-${VERSION}.json"
    fi

    [ -f "$FILE" ] || continue

    # Extract score for this benchmark (LmdbJavaAgrona only)
    SCORE=$(jq -r ".[] | select(.benchmark | contains(\"LmdbJavaAgrona.${BENCH}\")) |
      select(.params.intKey == \"true\") |
      select(.params.sequential == \"true\") |
      .primaryMetric.score" "$FILE" 2>/dev/null || echo "")

    if [ -n "$SCORE" ]; then
      # Format version label for display (truncate branch to 6 chars)
      if [[ "$VERSION" == branch-* ]]; then
        BRANCH_PART=$(echo "$VERSION" | sed 's/branch-\([^#]*\)#.*/\1/' | cut -c1-6)
        GIT_PART=$(echo "$VERSION" | sed 's/.*#\(.*\)/\1/')
        VERSION_LABEL="${BRANCH_PART}#${GIT_PART}"
      else
        VERSION_LABEL="$VERSION"
      fi
      echo "\"${VERSION_LABEL}\" ${SCORE}" >> "vers-${BENCH}.dat"
    fi
  done

  echo "  Generated data for ${BENCH}"
done

# Create multiplot gnuplot script
cat > vers-multiplot.gnuplot <<'GNUPLOT'
set terminal svg size 1000,700
set output 'version-comparison.svg'
set style fill solid 0.25 border
set boxwidth 0.5
set grid y

set multiplot layout 2,3 title "LmdbJava Performance Regression Testing\nMilliseconds per Operation (Smaller is Better)"

set ylabel "ms / operation"
set xlabel ""
set xtics nomirror rotate by -270

set title "Read by Key"
set style fill solid 0.25 border
plot 'vers-readKey.dat' using 2:xtic(1) with boxes lc rgb "#984ea3" notitle

set title "Write Entry"
set style fill solid 0.25 border
plot 'vers-write.dat' using 2:xtic(1) with boxes lc rgb "#ff7f00" notitle

set title "Calculate xxHash32"
set style fill solid 0.25 border
plot 'vers-readXxh32.dat' using 2:xtic(1) with boxes lc rgb "#4daf4a" notitle

set title "Iterate Sequentially"
set style fill solid 0.25 border
plot 'vers-readSeq.dat' using 2:xtic(1) with boxes lc rgb "#377eb8" notitle

set title "Iterate Reverse"
set style fill solid 0.25 border
plot 'vers-readRev.dat' using 2:xtic(1) with boxes lc rgb "#ffff33" notitle

set title "Calculate CRC32"
set style fill solid 0.25 border
plot 'vers-readCrc.dat' using 2:xtic(1) with boxes lc rgb "#e41a1c" notitle

unset multiplot
GNUPLOT

gnuplot vers-multiplot.gnuplot
rm -f vers-multiplot.gnuplot vers-*.dat

echo "  Generated version-comparison.svg"

# Append chart first
cat >> README.md <<'EOF'

![img](version-comparison.svg)

## Performance Analysis

The following tables show each benchmark ranked by performance, with percentage difference from the fastest version.

EOF

# Generate performance tables for each benchmark
declare -A BENCH_NAMES
BENCH_NAMES[readKey]="Read by Key"
BENCH_NAMES[write]="Write Entry"
BENCH_NAMES[readXxh32]="Calculate xxHash32"
BENCH_NAMES[readSeq]="Iterate Sequentially"
BENCH_NAMES[readRev]="Iterate Reverse"
BENCH_NAMES[readCrc]="Calculate CRC32"

for BENCH in readKey write readXxh32 readSeq readRev readCrc; do
  echo "### ${BENCH_NAMES[$BENCH]}" >> README.md
  echo "" >> README.md
  echo "| Rank | Version | ms/op | vs Fastest |" >> README.md
  echo "|------|---------|-------|------------|" >> README.md

  # Collect all scores for this benchmark
  declare -a SCORES
  for VERSION in "${VERSIONS[@]}"; do
    if [[ "$VERSION" == branch-* ]]; then
      FILE="out-${VERSION}.json"
    else
      FILE="out-version-${VERSION}.json"
    fi

    [ -f "$FILE" ] || continue

    SCORE=$(jq -r ".[] | select(.benchmark | contains(\"LmdbJavaAgrona.${BENCH}\")) |
      select(.params.intKey == \"true\") |
      select(.params.sequential == \"true\") |
      .primaryMetric.score" "$FILE" 2>/dev/null || echo "")

    if [ -n "$SCORE" ]; then
      SCORES+=("$SCORE:$VERSION")
    fi
  done

  # Sort by score (ascending, fastest first)
  IFS=$'\n' SORTED=($(sort -t: -k1 -n <<<"${SCORES[*]}"))
  unset IFS

  # Find fastest score for percentage calculation
  FASTEST_SCORE=$(echo "${SORTED[0]}" | cut -d: -f1)

  # Output ranked table
  RANK=1
  for ENTRY in "${SORTED[@]}"; do
    SCORE=$(echo "$ENTRY" | cut -d: -f1)
    VERSION=$(echo "$ENTRY" | cut -d: -f2)

    # Format version display
    if [[ "$VERSION" == branch-* ]]; then
      BRANCH_PART=$(echo "$VERSION" | sed 's/branch-\([^#]*\)#.*/\1/' | cut -c1-6)
      GIT_PART=$(echo "$VERSION" | sed 's/.*#\(.*\)/\1/')
      VERSION_DISPLAY="${BRANCH_PART}#${GIT_PART}"
    else
      VERSION_DISPLAY="$VERSION"
    fi

    # Calculate percentage difference
    if [ "$RANK" -eq 1 ]; then
      DIFF="baseline"
    else
      PERCENT=$(awk -v score="$SCORE" -v fastest="$FASTEST_SCORE" 'BEGIN {printf "%.1f", ((score - fastest) / fastest * 100)}')

      # Color the percentage if this is a branch version
      if [[ "$VERSION" == branch-* ]]; then
        BRANCH_NAME=$(echo "$VERSION" | sed 's/branch-\([^#]*\)#.*/\1/')
        COLOR="${BRANCH_COLORS[$BRANCH_NAME]}"
        DIFF="<span style=\"color: ${COLOR};\">+${PERCENT}%</span>"
      else
        DIFF="+${PERCENT}%"
      fi
    fi

    # Format score to 3 decimal places
    SCORE_FMT=$(printf "%.3f" "$SCORE")

    echo "| $RANK | \`$VERSION_DISPLAY\` | $SCORE_FMT | $DIFF |" >> README.md
    ((RANK++))
  done

  echo "" >> README.md

  # Clear array for next benchmark
  unset SCORES
done

cat >> README.md <<'EOF'

## Tested Versions

EOF

# List tested versions with links
for v in "${VERSIONS[@]}"; do
  if [[ "$v" == branch-* ]]; then
    # Branch version - link to GitHub tree
    BRANCH_NAME=$(echo "$v" | sed 's/branch-\([^#]*\)#.*/\1/')
    GIT_REV=$(echo "$v" | sed 's/.*#\(.*\)/\1/')
    echo "- [\`$v\`](https://github.com/lmdbjava/lmdbjava/tree/${GIT_REV})" >> README.md
  else
    # Maven version - link to Maven Central
    echo "- [\`$v\`](https://repo1.maven.org/maven2/org/lmdbjava/lmdbjava/${v}/)" >> README.md
  fi
done

cat >> README.md <<'EOF'

## Test Configuration

EOF

cat >> README.md <<EOF
The benchmark was executed on ${BENCH_DATE} using
[LmdbJava Benchmarks](https://github.com/lmdbjava/benchmarks) with the
LmdbJava Agrona implementation and the following configuration:

### Test Environment

| Component | Details |
| :-------- | :------ |
| CPU | ${CPU_MODEL} (${CPU_COUNT} cores) |
| RAM | ${RAM_GIB} GiB |
| OS | Linux ${KERNEL} (x86_64) |
| Java | ${JAVA_VERSION} |

### Benchmark Configuration

- **Implementation**: LmdbJava Agrona only
- **Test Profile**: Run 4 sequential integer configuration (100-byte values)
- **Key Type**: Sequential 32-bit integers
- **Value Size**: 100 bytes
- **Access Pattern**: Sequential
- **Benchmarks**: All 6 operations (readCrc, readKey, readRev, readSeq, readXxh32, write)

EOF

echo "Generating HTML viewer..."

# Create HTML viewer with GitHub markdown CSS and markdown-it
cat > index.html <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>LmdbJava Version Regression Report</title>
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/github-markdown-css/5.5.1/github-markdown.min.css">
  <style>
    body {
      box-sizing: border-box;
      min-width: 200px;
      max-width: 980px;
      margin: 0 auto;
      padding: 45px;
      background: #f5f5f5;
    }
    .markdown-body {
      box-sizing: border-box;
      background: white;
      padding: 40px;
      box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    }
  </style>
</head>
<body>
  <div class="markdown-body" id="content">Loading report...</div>
  <script type="module">
    import markdownit from 'https://cdn.jsdelivr.net/npm/markdown-it@14/+esm';
    const md = markdownit();

    // Check if we're running from file://
    if (window.location.protocol === 'file:') {
      document.getElementById('content').innerHTML = `
        <div style="padding: 40px; background: #fff3cd; border: 2px solid #856404; border-radius: 8px;">
          <h2 style="color: #856404; margin-top: 0;">⚠️ Cannot Load Report</h2>
          <p>The report cannot be loaded when opening <code>index.html</code> directly as a file.</p>
          <p><strong>To view this report, run a local web server:</strong></p>
          <pre style="background: #f8f9fa; padding: 15px; border-radius: 5px; overflow-x: auto;">cd target/benchmark
python3 -m http.server 8000</pre>
          <p>Then open <a href="http://localhost:8000">http://localhost:8000</a> in your browser</p>
          <p style="margin-top: 30px;"><strong>Alternatively:</strong> View <code>README.md</code> directly in any markdown viewer</p>
        </div>
      `;
    } else {
      fetch('README.md?hash=CACHE_BUST_HASH')
        .then(response => {
          if (!response.ok) throw new Error('Failed to load README.md');
          return response.text();
        })
        .then(text => {
          document.getElementById('content').innerHTML = md.render(text);
        })
        .catch(error => {
          document.getElementById('content').innerHTML = `
            <div style="padding: 40px; background: #fff3cd; border: 2px solid #856404; border-radius: 8px;">
              <h2 style="color: #856404; margin-top: 0;">⚠️ Error Loading Report</h2>
              <p>Failed to load README.md: ${error.message}</p>
              <p><strong>Alternatively:</strong> View <code>README.md</code> directly in any markdown viewer</p>
            </div>
          `;
        });
    }
  </script>
</body>
</html>
HTML

# Calculate SHA256 hash of README.md and inject into index.html
README_HASH=$(sha256sum README.md | cut -d' ' -f1)
sed -i "s/CACHE_BUST_HASH/${README_HASH}/" index.html

echo "  Generated index.html"
echo "  README.md hash: ${README_HASH}"

echo ""
echo "Report generation complete!"
echo ""
echo "Generated files:"
echo "  - README.md (version regression analysis)"
echo "  - index.html (HTML viewer with embedded chart)"
echo "  - version-comparison.svg (performance chart)"
echo ""
echo "To view the HTML report:"
echo "  cd $WORK_DIR"
echo "  python3 -m http.server 8000"
echo "  Then open http://localhost:8000 in your browser"
echo ""

# Return to original directory
cd - > /dev/null
