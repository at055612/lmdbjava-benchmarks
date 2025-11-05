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

# Usage: ./run-lmdb.sh [smoketest|benchmark [ram_percent]]
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

# LMDB tags to test (can be tags or commit hashes)
# Strategy: Comprehensive coverage with multiple releases per year to identify performance changes
LMDB_TAGS=(
  "LMDB_0.9.17"  # 2015-11-30
  "LMDB_0.9.18"  # 2016-02-05
  "LMDB_0.9.19"  # 2016-12-28
  "LMDB_0.9.20"  # 2017-02-01
  "LMDB_0.9.21"  # 2017-06-01
  "LMDB_0.9.22"  # 2018-03-22
  "LMDB_0.9.23"  # 2018-12-19
  "LMDB_0.9.24"  # 2019-07-19
  "LMDB_0.9.27"  # 2020-10-26
  "LMDB_0.9.28"  # 2021-03-06
  "LMDB_0.9.29"  # 2021-03-16
  "LMDB_0.9.30"  # 2022-07-21
  "LMDB_0.9.31"  # 2023-07-10
  "LMDB_0.9.33"  # 2024-05-21
)

case $MODE in
  smoketest)
    # Fixed small dataset for verification (fast, no warmup)
    ITER_OPTS="-wi 0 -i 1 -f 1"
    R_OPTS="-r 3s"
    NUM_ENTRIES=1000
    echo "Running in SMOKETEST mode (1K entries, fast verification)"
    ;;

  benchmark)
    # Production benchmark with full warmup and iterations
    ITER_OPTS="-wi 1 -i 3 -f 1"
    R_OPTS="-r 120s"

    # Calculate max RAM in bytes (RAM_PERCENT of total)
    MAX_RAM_GB=$((TOTAL_RAM_GB * RAM_PERCENT / 100))
    MAX_RAM_BYTES=$((MAX_RAM_GB * 1024 * 1024 * 1024))

    echo "Max RAM usage: ${MAX_RAM_GB} GB (${RAM_PERCENT}% of ${TOTAL_RAM_GB} GB)"

    # Maximum entry count cap
    MAX_ENTRIES=1000000

    # Calculate entries based on Run 4 config (100 byte values, 4 byte key = 104 byte entries)
    NUM_ENTRIES=$((MAX_RAM_BYTES / 104))
    [ $NUM_ENTRIES -gt $MAX_ENTRIES ] && NUM_ENTRIES=$MAX_ENTRIES

    echo "Calculated entry count: ${NUM_ENTRIES}"
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
    exit 1
    ;;
esac

# Create output directory outside target/ (survives mvn clean)
FINAL_OUTPUT_DIR="lmdb/results"
mkdir -p "$FINAL_OUTPUT_DIR"

# Create temporary directory for results
TEMP_OUTPUT_DIR=$(mktemp -d)
echo "Using temporary directory: ${TEMP_OUTPUT_DIR}"

# JVM flags for Java 9+ module system compatibility
JVM_OPTS="--add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.lang.reflect=ALL-UNNAMED --add-opens java.base/java.nio=ALL-UNNAMED --add-exports java.base/jdk.internal.misc=ALL-UNNAMED --add-exports java.base/sun.nio.ch=ALL-UNNAMED --add-exports jdk.compiler/com.sun.tools.javac.file=ALL-UNNAMED --enable-native-access=ALL-UNNAMED"

# Ensure master is built and installed locally
echo ""
BRANCH_DIR="target/lmdbjava-src-master"
CACHED_BUILD=false

# Check if master is already built (by checking for cached metadata and JAR)
if [ -f "target/lmdbjava-git-commit-full.txt" ] && [ -f "target/benchmarks.jar" ]; then
  CACHED_COMMIT=$(cat target/lmdbjava-git-commit-full.txt)
  CACHED_COMMIT_SHORT=$(cat target/lmdbjava-git-commit-short.txt)
  BRANCH_VERSION=$(grep -m 1 "<lmdbjava.version>" pom.xml | sed 's/.*<lmdbjava.version>\(.*\)<\/lmdbjava.version>.*/\1/')

  echo "✓ LmdbJava master already built (cached): ${BRANCH_VERSION} @ ${CACHED_COMMIT_SHORT}"

  GIT_REVISION_FULL=$CACHED_COMMIT
  GIT_REVISION=$CACHED_COMMIT_SHORT

  # Ensure metadata files exist for report generation (may not exist if using old cache)
  [ -f "target/lmdbjava-git-branch.txt" ] || echo "master" > target/lmdbjava-git-branch.txt

  CACHED_BUILD=true
else
  echo "Building LmdbJava master..."
  rm -rf "${BRANCH_DIR}"

  if ! git clone --depth 1 --branch master https://github.com/lmdbjava/lmdbjava.git "${BRANCH_DIR}" 2>&1 | grep -E "(Cloning|branch)"; then
    echo "✗ Failed to clone master branch"
    exit 1
  fi

  cd "${BRANCH_DIR}"
  BRANCH_VERSION=$(grep -m 1 "<version>" pom.xml | sed 's/.*<version>\(.*\)<\/version>.*/\1/')
  GIT_REVISION=$(git rev-parse --short HEAD)
  GIT_REVISION_FULL=$(git rev-parse HEAD)
  echo "Master version: ${BRANCH_VERSION}"
  echo "Git revision: ${GIT_REVISION}"

  # Save git info for report generation (before directory cleanup)
  echo "master" > ../lmdbjava-git-branch.txt
  echo "${GIT_REVISION}" > ../lmdbjava-git-commit-short.txt
  echo "${GIT_REVISION_FULL}" > ../lmdbjava-git-commit-full.txt

  if ! mvn clean install -DskipTests -Dfmt.skip -q; then
    cd - > /dev/null
    echo "✗ Master build failed"
    exit 1
  fi
  cd - > /dev/null

  # Backup original pom.xml
  cp pom.xml pom.xml.backup

  # Update benchmark pom.xml to use master version
  sed -i "s|<lmdbjava.version>.*</lmdbjava.version>|<lmdbjava.version>${BRANCH_VERSION}</lmdbjava.version>|g" pom.xml

  # Build benchmark with master
  echo "Building benchmarks with master..."
  if ! mvn clean package -DskipTests -q; then
    cp pom.xml.backup pom.xml
    rm pom.xml.backup
    echo "✗ Benchmark build failed"
    exit 1
  fi
fi

# Save LMDB metadata (latest tag is the last element in the array)
LATEST_TAG="${LMDB_TAGS[-1]}"
echo "${LATEST_TAG}" > target/lmdb-latest-tag.txt

echo ""
echo "Checking LMDB libraries..."

# Function to compile LMDB from source if needed
compile_lmdb_tag() {
  local tag=$1
  local base_dir=$(pwd)
  local lmdb_dir="${base_dir}/lmdb/${tag}"
  local repo_dir="${base_dir}/lmdb/.openldap-repo"

  # Check if already compiled (cached)
  if [ -f "${lmdb_dir}/liblmdb.so" ]; then
    echo "  ✓ LMDB ${tag} already compiled (cached)"
    return 0
  fi

  echo "  Compiling LMDB ${tag} from source..."

  # Clone repository if needed (using absolute path)
  if [ ! -d "${repo_dir}" ]; then
    echo "    Cloning OpenLDAP repository..."
    if ! git clone --no-checkout https://git.openldap.org/openldap/openldap.git "${repo_dir}" > /dev/null 2>&1; then
      echo "✗ Failed to clone OpenLDAP repository"
      return 1
    fi
  fi

  cd "${repo_dir}"

  # Fetch and checkout the tag/commit
  if ! git fetch --depth 1 origin tag "${tag}" 2>/dev/null; then
    if ! git fetch --depth 1 origin "${tag}" 2>/dev/null; then
      echo "✗ Failed to fetch ${tag}"
      cd "${base_dir}"
      return 1
    fi
  fi

  if ! git checkout -f "${tag}" > /dev/null 2>&1; then
    echo "✗ Failed to checkout ${tag}"
    cd "${base_dir}"
    return 1
  fi

  # Compile LMDB (override OPT to remove debug symbols for smaller binaries)
  cd libraries/liblmdb
  make clean > /dev/null 2>&1 || true

  if ! make -j$(nproc) OPT="-O2" liblmdb.so > /dev/null 2>&1; then
    echo "✗ Compilation failed for ${tag}"
    cd "${base_dir}"
    return 1
  fi

  # Copy library to output directory
  mkdir -p "${lmdb_dir}"
  cp liblmdb.so "${lmdb_dir}/"

  cd "${base_dir}"

  echo "  ✓ Compiled ${tag}"
  return 0
}

# Compile any missing LMDB libraries
for TAG in "${LMDB_TAGS[@]}"; do
  if ! compile_lmdb_tag "${TAG}"; then
    echo "✗ Failed to compile LMDB ${TAG}"
    exit 1
  fi
done

echo ""
echo "Testing ${#LMDB_TAGS[@]} LMDB tags against LmdbJava master#${GIT_REVISION}..."
echo ""

# Function to run benchmark for specific LMDB tag
run_benchmark() {
  local output_file=$1
  local tag_label=$2
  local lmdb_lib_path=$3

  echo "  Running benchmark: ${tag_label}..."
  echo "  Using LMDB library: ${lmdb_lib_path}"

  # Run with forced LMDB library
  java $JVM_OPTS -Dlmdbjava.native.lib="${lmdb_lib_path}" \
    -jar target/benchmarks.jar -rf json $ITER_OPTS $R_OPTS -to 60m -tu ms \
    -p num=${NUM_ENTRIES} -p intKey=true -p sequential=true \
    -rff "${output_file}" \
    LmdbJavaAgrona || true

  if [ -f "${output_file}" ]; then
    echo "  ✓ Completed: ${tag_label}"
  else
    echo "  ✗ Failed: ${tag_label}"
    echo "  Output file expected at: ${output_file}"
    exit 1
  fi
}

# Test each LMDB tag
for TAG in "${LMDB_TAGS[@]}"; do
  LMDB_LIB="$(pwd)/lmdb/${TAG}/liblmdb.so"

  if [ ! -f "${LMDB_LIB}" ]; then
    echo "✗ LMDB tag ${TAG} not found at ${LMDB_LIB}"
    echo "  This should have been compiled earlier - something went wrong"
    exit 1
  fi

  # Check if result already exists in final directory
  FINAL_FILE="${FINAL_OUTPUT_DIR}/out-lmdb-${TAG}.json"
  if [ -s "${FINAL_FILE}" ]; then
    echo "  ✓ Skipping lmdb-${TAG} (already completed)"
  else
    run_benchmark "${TEMP_OUTPUT_DIR}/out-lmdb-${TAG}.json" "lmdb-${TAG}" "${LMDB_LIB}"
  fi
  echo ""
done

# Restore original pom.xml (only if backup exists, i.e., if we modified it)
if [ -f pom.xml.backup ]; then
  cp pom.xml.backup pom.xml
  rm pom.xml.backup
fi

# Copy results from temp directory to final location
echo ""
echo "Copying results to ${FINAL_OUTPUT_DIR}..."
mkdir -p "${FINAL_OUTPUT_DIR}"
cp "${TEMP_OUTPUT_DIR}"/out-lmdb-*.json "${FINAL_OUTPUT_DIR}/" 2>/dev/null || true

# Cleanup temp directory
rm -rf "${TEMP_OUTPUT_DIR}"

# Cleanup master clone
rm -rf "${BRANCH_DIR}"

echo ""
echo "LMDB version testing completed in $MODE mode"
if [ "$MODE" = "benchmark" ]; then
  echo "RAM usage limit: ${RAM_PERCENT}% of ${TOTAL_RAM_GB} GB (max ${NUM_ENTRIES} entries)"
fi

# Count successful results
EXPECTED_COUNT=${#LMDB_TAGS[@]}
ACTUAL_COUNT=$(find "${FINAL_OUTPUT_DIR}" -name "out-lmdb-*.json" 2>/dev/null | wc -l)

echo ""
echo "Results: ${ACTUAL_COUNT} of ${EXPECTED_COUNT} LMDB tags tested successfully"
if [ $ACTUAL_COUNT -lt $EXPECTED_COUNT ]; then
  echo "  WARNING: Some tests failed. Expected ${EXPECTED_COUNT} results, got ${ACTUAL_COUNT}"
  exit 1
fi

echo ""
echo "Results available in:"
for TAG in "${LMDB_TAGS[@]}"; do
  [ -f "${FINAL_OUTPUT_DIR}/out-lmdb-${TAG}.json" ] && echo "  - ${FINAL_OUTPUT_DIR}/out-lmdb-${TAG}.json"
done
echo ""
echo "To generate a report from these results, run: ./report-lmdb.sh"
