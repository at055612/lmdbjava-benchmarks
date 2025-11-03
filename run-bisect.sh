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

# Research script for investigating LmdbJava performance regressions
# Uses bisection to find the commit that introduced a performance regression

# Bisection configuration
START_COMMIT="be2a15b348668ca5c97ab58a4ac9b396d21256da"  # Known good commit
END_COMMIT="dc24f4b6010e3cbcd498a3d227ddde9e5983a265"    # Known bad commit
BENCHMARK_NAME="LmdbJavaAgrona.write"                    # Full benchmark qualifier
MAX_BISECTIONS=10                                        # Maximum bisection iterations

# Fixed test configuration
NUM_ENTRIES=1000000
LMDB_LIBRARY="/usr/lib/liblmdb.so"

# JMH configuration (edit as needed for specific research goals)
JMH_FORKS=1
JMH_ITERATIONS=1
JMH_WARMUP=1
JMH_RUNTIME=30

# Directories
BISECT_DIR="bisect"
LMDBJAVA_CLONE="$BISECT_DIR/lmdbjava"
LMDBJAVA_JARS="$BISECT_DIR/lmdbjava-jars"
BENCHMARK_JARS="$BISECT_DIR/benchmark-jars"
RESULTS_DIR="$BISECT_DIR/results"

# Create directory structure
mkdir -p "$LMDBJAVA_JARS" "$BENCHMARK_JARS" "$RESULTS_DIR"

# JVM flags for Java 9+ module system compatibility
JVM_OPTS="--add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.lang.reflect=ALL-UNNAMED --add-opens java.base/java.nio=ALL-UNNAMED --add-exports java.base/jdk.internal.misc=ALL-UNNAMED --add-exports java.base/sun.nio.ch=ALL-UNNAMED --add-exports jdk.compiler/com.sun.tools.javac.file=ALL-UNNAMED --enable-native-access=ALL-UNNAMED"

# Verify LMDB library exists
if [ ! -f "$LMDB_LIBRARY" ]; then
  echo "ERROR: LMDB library not found at $LMDB_LIBRARY"
  echo "Please update LMDB_LIBRARY variable in this script"
  exit 1
fi

echo "=========================================="
echo "LmdbJava Performance Research"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  Entries: ${NUM_ENTRIES}"
echo "  LMDB Library: ${LMDB_LIBRARY}"
echo "  JMH: -f ${JMH_FORKS} -wi ${JMH_WARMUP} -i ${JMH_ITERATIONS} -r ${JMH_RUNTIME}s"
echo ""

# Clone LmdbJava repository if needed
if [ ! -d "$LMDBJAVA_CLONE" ]; then
  echo "Cloning LmdbJava repository..."
  git clone --quiet https://github.com/lmdbjava/lmdbjava.git "$LMDBJAVA_CLONE"
  echo "✓ Repository cloned"
  echo ""
fi

# Generate commit log sorted by timestamp (UTC, readable format)
echo "Generating commit log..."
cd "$LMDBJAVA_CLONE"
git log --format="%aI %H %s" --all | while IFS=' ' read -r timestamp hash rest; do
  # Convert ISO 8601 to "YYYY-MM-DD HH:MM:SS" UTC
  utc_date=$(date -u -d "$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$timestamp")
  echo "$utc_date $hash $rest"
done | sort > "../commit-log.txt"
cd - > /dev/null
echo "✓ Commit log saved to $BISECT_DIR/commit-log.txt"
echo ""

# Write metadata
METADATA_FILE="$BISECT_DIR/metadata.txt"
{
  echo "Research Metadata"
  echo "================="
  echo ""
  echo "Generated: $(date)"
  echo "LMDB Library: ${LMDB_LIBRARY}"
  echo "LMDB Version: $(strings "$LMDB_LIBRARY" | grep -E "^LMDB [0-9]" | head -1 || echo "Unknown")"
  echo "Java Version: $(java -version 2>&1 | head -1)"
  echo "System: $(uname -a)"
  echo ""
  echo "Test Configuration:"
  echo "  Entries: ${NUM_ENTRIES}"
  echo "  JMH Forks: ${JMH_FORKS}"
  echo "  JMH Warmup Iterations: ${JMH_WARMUP}"
  echo "  JMH Iterations: ${JMH_ITERATIONS}"
  echo "  JMH Runtime: ${JMH_RUNTIME}s"
  echo "  Benchmark: ${BENCHMARK_NAME}"
  echo "  Parameters: intKey=true, sequential=true, valSize=100"
  echo ""
  echo "Bisection Range:"
  echo "  Start: ${START_COMMIT}"
  echo "  End: ${END_COMMIT}"
  echo "  Max Bisections: ${MAX_BISECTIONS}"
} > "$METADATA_FILE"
echo "✓ Metadata saved to $METADATA_FILE"
echo ""

# Function to get short commit hash
get_short_hash() {
  local commit=$1
  cd "$LMDBJAVA_CLONE"
  git rev-parse --short "$commit"
  cd - > /dev/null
}

# Function to build LmdbJava for a specific commit
build_lmdbjava() {
  local commit=$1
  local short_hash=$(get_short_hash "$commit")
  local jar_file="$LMDBJAVA_JARS/lmdbjava-${short_hash}.jar"

  if [ -f "$jar_file" ]; then
    echo "  ✓ LmdbJava JAR already built: ${short_hash}"
    return 0
  fi

  echo "  Building LmdbJava ${short_hash}..."

  cd "$LMDBJAVA_CLONE"

  # Stash any local changes before checkout
  git stash --quiet --include-untracked 2>/dev/null || true
  git checkout --quiet "$commit"

  # Build with fmt.skip to avoid fmt-maven-plugin Java version incompatibilities
  if ! mvn clean package -DskipTests -Dfmt.skip -q; then
    echo "  ✗ LmdbJava build failed for commit ${commit}"
    echo "  This commit may not be compatible with current Java/Maven versions"
    cd - > /dev/null
    exit 1
  fi

  # Find the built JAR (absolute path needed for cp)
  LMDBJAVA_JAR=$(find "$(pwd)/target" -name "lmdbjava-*.jar" -not -name "*-sources.jar" -not -name "*-javadoc.jar" | head -1)

  if [ -z "$LMDBJAVA_JAR" ] || [ ! -f "$LMDBJAVA_JAR" ]; then
    echo "  ✗ LmdbJava JAR not found after build"
    echo "  Expected pattern: target/lmdbjava-*.jar"
    ls -la target/*.jar 2>/dev/null || echo "  No JARs found in target/"
    cd - > /dev/null
    exit 1
  fi

  # Go back before copying so we use correct relative path
  cd - > /dev/null
  cp "$LMDBJAVA_JAR" "$jar_file"

  echo "  ✓ LmdbJava built: ${short_hash}"
}

# Function to build benchmark JAR for a specific LmdbJava version
build_benchmark() {
  local commit=$1
  local short_hash=$(get_short_hash "$commit")
  local lmdbjava_jar="$LMDBJAVA_JARS/lmdbjava-${short_hash}.jar"
  local benchmark_jar="$BENCHMARK_JARS/benchmarks-${short_hash}.jar"

  if [ -f "$benchmark_jar" ]; then
    echo "  ✓ Benchmark JAR already built: ${short_hash}"
    return 0
  fi

  echo "  Building benchmark JAR for ${short_hash}..."

  # Install LmdbJava JAR to local Maven repo
  mvn install:install-file -q \
    -Dfile="$lmdbjava_jar" \
    -DgroupId=org.lmdbjava \
    -DartifactId=lmdbjava \
    -Dversion="${short_hash}" \
    -Dpackaging=jar

  # Update pom.xml to use this version
  cp pom.xml pom.xml.backup
  sed -i "s|<lmdbjava.version>.*</lmdbjava.version>|<lmdbjava.version>${short_hash}</lmdbjava.version>|g" pom.xml

  # Build benchmarks
  if ! mvn clean package -DskipTests -q; then
    echo "  ✗ Benchmark build failed for ${short_hash}"
    cp pom.xml.backup pom.xml
    exit 1
  fi

  cp target/benchmarks.jar "$benchmark_jar"
  cp pom.xml.backup pom.xml

  echo "  ✓ Benchmark built: ${short_hash}"
}

# Function to run benchmark for a specific commit
run_benchmark() {
  local commit=$1
  local short_hash=$(get_short_hash "$commit")
  local benchmark_jar="$BENCHMARK_JARS/benchmarks-${short_hash}.jar"
  local output_json="$RESULTS_DIR/out-${short_hash}.json"
  local output_txt="$RESULTS_DIR/out-${short_hash}.txt"

  # Check if benchmark already completed
  if [ -s "$output_json" ]; then
    echo "  ✓ Benchmark already completed: ${short_hash}"
    return 0
  fi

  echo "  Running benchmark: ${short_hash}..."

  # Run benchmark with forced LMDB library (same approach as run-vers.sh)
  java -jar "$benchmark_jar" \
    -rf json \
    -f $JMH_FORKS \
    -wi $JMH_WARMUP \
    -i $JMH_ITERATIONS \
    -r ${JMH_RUNTIME}s \
    -to 60m \
    -tu ms \
    -p num=$NUM_ENTRIES \
    -p intKey=true \
    -p sequential=true \
    -jvmArgs "$JVM_OPTS -Dlmdbjava.native.lib=${LMDB_LIBRARY}" \
    -rff "$output_json" \
    "$BENCHMARK_NAME" > "$output_txt" 2>&1 || true

  if [ -s "$output_json" ]; then
    echo "  ✓ Benchmark completed: ${short_hash}"
  else
    echo "  ✗ Benchmark failed: ${short_hash}"
    exit 1
  fi
}

# Function to get benchmark score from JSON result
get_score() {
  local commit=$1
  local short_hash=$(get_short_hash "$commit")
  local json_file="$RESULTS_DIR/out-${short_hash}.json"

  if [ ! -s "$json_file" ]; then
    echo "0"
    return
  fi

  python3 -c "import json; d=json.load(open('$json_file')); print(d[0]['primaryMetric']['score']) if d else print(0)" 2>/dev/null || echo "0"
}

# Function to get commits between two commits (exclusive of endpoints)
get_commits_between() {
  local start=$1
  local end=$2

  cd "$LMDBJAVA_CLONE"
  # Get commits between start and end, excluding endpoints, in chronological order
  git rev-list --ancestry-path "${start}..${end}" --reverse
  cd - > /dev/null
}

# Resolve START_COMMIT and END_COMMIT to full hashes
cd "$LMDBJAVA_CLONE"
START_COMMIT=$(git rev-parse "$START_COMMIT")
END_COMMIT=$(git rev-parse "$END_COMMIT")
cd - > /dev/null

echo "=========================================="
echo "Bisection Start"
echo "=========================================="
echo "Start commit: $(get_short_hash "$START_COMMIT")"
echo "End commit:   $(get_short_hash "$END_COMMIT")"
echo "Benchmark:    $BENCHMARK_NAME"
echo "Max bisections: $MAX_BISECTIONS"
echo ""

# Test START and END commits
echo "Testing endpoint commits..."
echo ""

echo "==========================================  "
echo "Testing START: $(get_short_hash "$START_COMMIT")"
echo "=========================================="
build_lmdbjava "$START_COMMIT"
build_benchmark "$START_COMMIT"
run_benchmark "$START_COMMIT"
START_SCORE=$(get_score "$START_COMMIT")
echo "Score: ${START_SCORE} ms/op"
echo ""

echo "=========================================="
echo "Testing END: $(get_short_hash "$END_COMMIT")"
echo "=========================================="
build_lmdbjava "$END_COMMIT"
build_benchmark "$END_COMMIT"
run_benchmark "$END_COMMIT"
END_SCORE=$(get_score "$END_COMMIT")
echo "Score: ${END_SCORE} ms/op"
echo ""

# Verify END is slower than START (regression scenario)
if (( $(awk -v a="$END_SCORE" -v b="$START_SCORE" 'BEGIN {print (a <= b)}') )); then
  echo "ERROR: END commit ($END_SCORE ms/op) is not slower than START commit ($START_SCORE ms/op)"
  echo "This indicates a performance improvement, not a regression."
  echo "Please swap START_COMMIT and END_COMMIT or verify your commit range."
  exit 1
fi

echo "Confirmed regression: ${START_SCORE} ms/op → ${END_SCORE} ms/op ($(awk -v e="$END_SCORE" -v s="$START_SCORE" 'BEGIN {printf "%.1f", (e-s)/s*100}')% slower)"
echo ""

# Get all commits between start and end
ALL_COMMITS=($(get_commits_between "$START_COMMIT" "$END_COMMIT"))
TOTAL_COMMITS=${#ALL_COMMITS[@]}

echo "Found $TOTAL_COMMITS commits between endpoints"
echo ""

if [ $TOTAL_COMMITS -eq 0 ]; then
  echo "No commits between START and END (adjacent commits)."
  echo "The regression was introduced in commit: $(get_short_hash "$END_COMMIT")"
  exit 0
fi

# Bisection loop
LOWER_COMMIT="$START_COMMIT"
UPPER_COMMIT="$END_COMMIT"
LOWER_SCORE="$START_SCORE"
UPPER_SCORE="$END_SCORE"
BISECTION_COUNT=0

while [ $BISECTION_COUNT -lt $MAX_BISECTIONS ]; do
  # Get commits between current range
  RANGE_COMMITS=($(get_commits_between "$LOWER_COMMIT" "$UPPER_COMMIT"))
  RANGE_SIZE=${#RANGE_COMMITS[@]}

  echo "=========================================="
  echo "Bisection $((BISECTION_COUNT + 1))/$MAX_BISECTIONS"
  echo "=========================================="
  echo "Current range: $(get_short_hash "$LOWER_COMMIT") ($LOWER_SCORE ms/op) ... $(get_short_hash "$UPPER_COMMIT") ($UPPER_SCORE ms/op)"
  echo "Commits in range: $RANGE_SIZE"

  if [ $RANGE_SIZE -eq 0 ]; then
    echo "Adjacent commits reached."
    break
  fi

  # Pick middle commit (50% bisection)
  MIDDLE_INDEX=$((RANGE_SIZE / 2))
  MIDDLE_COMMIT="${RANGE_COMMITS[$MIDDLE_INDEX]}"

  echo "Testing middle commit: $(get_short_hash "$MIDDLE_COMMIT") (index $MIDDLE_INDEX of $RANGE_SIZE)"
  echo ""

  # Check if benchmark was already completed (cached)
  SHORT_HASH=$(get_short_hash "$MIDDLE_COMMIT")
  JSON_FILE="$RESULTS_DIR/out-${SHORT_HASH}.json"
  WAS_CACHED=false
  if [ -s "$JSON_FILE" ]; then
    WAS_CACHED=true
    echo "  ✓ Benchmark already completed (cached): ${SHORT_HASH}"
  else
    build_lmdbjava "$MIDDLE_COMMIT"
    build_benchmark "$MIDDLE_COMMIT"
    run_benchmark "$MIDDLE_COMMIT"
  fi

  MIDDLE_SCORE=$(get_score "$MIDDLE_COMMIT")

  echo "Score: ${MIDDLE_SCORE} ms/op"
  echo ""

  # Decide which half to bisect
  # Distance from middle to lower and upper
  DIST_TO_LOWER=$(awk -v a="$MIDDLE_SCORE" -v b="$LOWER_SCORE" 'BEGIN {x=a-b; if(x<0) x=-x; print x}')
  DIST_TO_UPPER=$(awk -v a="$MIDDLE_SCORE" -v b="$UPPER_SCORE" 'BEGIN {x=a-b; if(x<0) x=-x; print x}')

  echo "Distance to lower: $DIST_TO_LOWER ms, Distance to upper: $DIST_TO_UPPER ms"

  if (( $(awk -v a="$DIST_TO_LOWER" -v b="$DIST_TO_UPPER" 'BEGIN {print (a < b)}') )); then
    # Closer to lower (good) → regression is towards upper
    echo "→ Closer to LOWER (good), bisecting upper half"
    LOWER_COMMIT="$MIDDLE_COMMIT"
    LOWER_SCORE="$MIDDLE_SCORE"
  elif (( $(awk -v a="$DIST_TO_LOWER" -v b="$DIST_TO_UPPER" 'BEGIN {print (a > b)}') )); then
    # Closer to upper (bad) → regression is towards lower
    echo "→ Closer to UPPER (bad), bisecting lower half"
    UPPER_COMMIT="$MIDDLE_COMMIT"
    UPPER_SCORE="$MIDDLE_SCORE"
  else
    # Equidistant - pick lower half by default (tie-breaking)
    echo "→ Equidistant, bisecting lower half (tie-break)"
    UPPER_COMMIT="$MIDDLE_COMMIT"
    UPPER_SCORE="$MIDDLE_SCORE"
  fi

  echo ""

  # Increment bisection count (counts iterations, not just new benchmarks)
  BISECTION_COUNT=$((BISECTION_COUNT + 1))
done

echo "=========================================="
echo "Bisection Complete"
echo "=========================================="
echo ""

if [ $BISECTION_COUNT -eq $MAX_BISECTIONS ]; then
  echo "Stopped: Reached maximum bisections ($MAX_BISECTIONS)"
else
  echo "Stopped: Adjacent commits reached"
fi

echo ""
echo "Final range: $(get_short_hash "$LOWER_COMMIT") ... $(get_short_hash "$UPPER_COMMIT")"
echo "Likely culprit: commits between these two"
echo ""

# Generate summary report
echo "=========================================="
echo "Summary Report"
echo "=========================================="
echo ""

# Collect all tested commits with scores
declare -A COMMIT_SCORES
for json_file in "$RESULTS_DIR"/out-*.json; do
  if [ -s "$json_file" ]; then
    short_hash=$(basename "$json_file" .json | sed 's/out-//')
    score=$(python3 -c "import json; d=json.load(open('$json_file')); print(f\"{d[0]['primaryMetric']['score']:.2f}\") if d else print('N/A')" 2>/dev/null)

    # Find full hash for this short hash
    cd "$LMDBJAVA_CLONE"
    full_hash=$(git rev-parse "$short_hash" 2>/dev/null || echo "$short_hash")
    cd - > /dev/null

    COMMIT_SCORES["$full_hash"]="$score"
  fi
done

# Print commits in chronological order with scores
# Total width: 120 chars
# Layout: 2(marker+space) + 7(hash) + 2 + 19(date) + 2 + 8(score) + 2 + 9(change) + 2 + remaining(message)
# Message width: 120 - 2 - 7 - 2 - 19 - 2 - 8 - 2 - 9 - 2 = 67 chars
echo "  Commit   Date                    Score    Change     Message"
echo "========================================================================================================================"

cd "$LMDBJAVA_CLONE"
PREV_SCORE=""
REGRESSION_HASH=""
MAX_CHANGE=0

# First pass: find the commit with largest regression
for hash in $(echo "$START_COMMIT"; git log --format="%H" --reverse "${START_COMMIT}..${END_COMMIT}" 2>/dev/null); do
  if [ "$hash" = "$START_COMMIT" ] || [ "$hash" = "$END_COMMIT" ] || [ -n "${COMMIT_SCORES[$hash]:-}" ]; then
    score="${COMMIT_SCORES[$hash]:-N/A}"
    if [ -n "$PREV_SCORE" ] && [ "$score" != "N/A" ] && [ "$PREV_SCORE" != "N/A" ]; then
      diff=$(awk -v a="$score" -v b="$PREV_SCORE" 'BEGIN {print a-b}')
      pct=$(awk -v a="$diff" -v b="$PREV_SCORE" 'BEGIN {print a/b*100}')
      if (( $(awk -v a="$pct" -v b="$MAX_CHANGE" 'BEGIN {print (a > b)}') )); then
        MAX_CHANGE=$pct
        REGRESSION_HASH=$hash
      fi
    fi
    [ "$score" != "N/A" ] && PREV_SCORE="$score"
  fi
done

# Second pass: print the report
PREV_SCORE=""
for hash in $(echo "$START_COMMIT"; git log --format="%H" --reverse "${START_COMMIT}..${END_COMMIT}" 2>/dev/null); do
  if [ "$hash" = "$START_COMMIT" ] || [ "$hash" = "$END_COMMIT" ] || [ -n "${COMMIT_SCORES[$hash]:-}" ]; then
    short=$(git rev-parse --short "$hash")
    date=$(git log -1 --format="%aI" "$hash" | xargs -I{} date -u -d {} "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
    msg=$(git log -1 --format="%s" "$hash")
    score="${COMMIT_SCORES[$hash]:-N/A}"

    # Remove "Regression:" prefix if present
    msg="${msg#Regression: }"

    # Truncate message to fit 120 total width (67 chars for message)
    if [ ${#msg} -gt 67 ]; then
      msg="${msg:0:64}..."
    fi

    marker=" "
    [ "$hash" = "$REGRESSION_HASH" ] && marker="*"

    change=""
    if [ -n "$PREV_SCORE" ] && [ "$score" != "N/A" ] && [ "$PREV_SCORE" != "N/A" ]; then
      diff=$(awk -v a="$score" -v b="$PREV_SCORE" 'BEGIN {print a-b}')
      pct=$(awk -v a="$diff" -v b="$PREV_SCORE" 'BEGIN {printf "%.2f", a/b*100}')
      if (( $(awk -v a="$diff" 'BEGIN {print (a >= 0)}') )); then
        change="+${pct}%"
      else
        change="${pct}%"
      fi
    fi

    if [ "$score" != "N/A" ]; then
      printf " %s %-7s  %s  %8s  %9s  %s\n" "$marker" "$short" "$date" "$score" "$change" "$msg"
      PREV_SCORE="$score"
    else
      printf " %s %-7s  %s  %8s  %9s  %s\n" "$marker" "$short" "$date" "N/A" "" "$msg"
    fi
  fi
done
cd - > /dev/null

echo ""
echo "Results saved to: $BISECT_DIR/results/"
echo "Metadata: $BISECT_DIR/metadata.txt"
echo "Commit log: $BISECT_DIR/commit-log.txt"
echo ""
