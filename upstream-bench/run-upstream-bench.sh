#!/bin/bash
#
# Run upstream LMDB benchmark (from ITS#10406) across multiple LMDB versions
# This benchmark was provided by Howard Chu to validate write performance regression reports
#

set -euo pipefail

# LMDB versions to test (matching our Java benchmark versions)
LMDB_TAGS=(
  "LMDB_0.9.17"
  "LMDB_0.9.18"
  "LMDB_0.9.19"
  "LMDB_0.9.20"
  "LMDB_0.9.21"
  "LMDB_0.9.22"
  "LMDB_0.9.23"
  "LMDB_0.9.24"
  "LMDB_0.9.27"
  "LMDB_0.9.28"
  "LMDB_0.9.29"
  "LMDB_0.9.30"
  "LMDB_0.9.31"
  "LMDB_0.9.33"
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LMDB_REPO_DIR="${PROJECT_ROOT}/lmdb/.openldap-repo"
RESULTS_DIR="${SCRIPT_DIR}/target/results"
BUILD_DIR="${SCRIPT_DIR}/target"
ITERATIONS=3

mkdir -p "${RESULTS_DIR}"
mkdir -p "${BUILD_DIR}"

echo "========================================"
echo "Upstream LMDB Benchmark Suite"
echo "Source: ITS#10406"
echo "========================================"
echo ""
echo "Testing ${#LMDB_TAGS[@]} LMDB versions with ${ITERATIONS} iterations each"
echo "Results will be saved to: ${RESULTS_DIR}"
echo ""

# Check LMDB repository exists
if [ ! -d "${LMDB_REPO_DIR}" ]; then
  echo "ERROR: LMDB repository not found at ${LMDB_REPO_DIR}"
  echo "Please ensure the LMDB repository is cloned"
  exit 1
fi

# Function to compile and run benchmark for a specific LMDB version
run_bench_for_version() {
  local tag=$1
  local result_file="${RESULTS_DIR}/upstream-${tag}.txt"

  echo "========================================"
  echo "Testing ${tag}"
  echo "========================================"

  # Check if already completed
  if [ -f "${result_file}" ] && grep -q "Added 1000000 values" "${result_file}"; then
    echo "✓ Already completed (results exist)"
    echo ""
    return 0
  fi

  cd "${LMDB_REPO_DIR}"

  # Checkout the tag
  echo "Checking out ${tag}..."
  if ! git checkout -f "${tag}" > /dev/null 2>&1; then
    echo "✗ Failed to checkout ${tag}"
    echo ""
    return 1
  fi

  # Compile LMDB library
  echo "Compiling LMDB ${tag}..."
  cd libraries/liblmdb
  if ! make clean > /dev/null 2>&1 || ! make -j$(nproc) liblmdb.a > /dev/null 2>&1; then
    echo "✗ Failed to compile ${tag}"
    cd "${SCRIPT_DIR}"
    echo ""
    return 1
  fi

  LMDB_LIB_PATH="$(pwd)"
  cd "${SCRIPT_DIR}"

  # Compile benchmark binary to target directory
  echo "Compiling benchmark for ${tag}..."
  if ! gcc -O2 -o "${BUILD_DIR}/mtest-append" mtest-append.c -I"${LMDB_LIB_PATH}" -L"${LMDB_LIB_PATH}" -llmdb -lpthread > /dev/null 2>&1; then
    echo "✗ Failed to compile benchmark for ${tag}"
    echo ""
    return 1
  fi

  # Run benchmark multiple times from /tmp for consistency with Java benchmarks
  echo "Running benchmark (${ITERATIONS} iterations)..."
  > "${result_file}"

  # Copy binary to /tmp to ensure testdb is created in tmpfs
  cp "${BUILD_DIR}/mtest-append" /tmp/
  cd /tmp

  for i in $(seq 1 ${ITERATIONS}); do
    echo "  Iteration $i/${ITERATIONS}..."

    # Clean and create database directory
    rm -rf testdb
    mkdir -p testdb

    # Run benchmark
    ./mtest-append >> "${result_file}" 2>&1

    # Clean up for next iteration
    rm -rf testdb
  done

  # Clean up binary and return to script directory
  rm -f /tmp/mtest-append
  cd "${SCRIPT_DIR}"

  echo "✓ Completed ${tag}"
  echo ""

  return 0
}

# Run benchmarks for all versions
for TAG in "${LMDB_TAGS[@]}"; do
  run_bench_for_version "${TAG}"
done

# Generate summary
echo "========================================"
echo "Summary"
echo "========================================"
echo ""

python3 << 'EOFPYTHON'
import re
import glob
import os

results = []

for filepath in sorted(glob.glob("target/results/upstream-LMDB_*.txt")):
    tag = os.path.basename(filepath).replace("upstream-", "").replace(".txt", "")

    with open(filepath) as f:
        content = f.read()

    # Extract all timing results
    times = re.findall(r'Added \d+ values in (\d+)\.(\d+)sec', content)

    if times:
        # Calculate average time in seconds
        total_secs = sum(int(sec) + int(usec)/1000000.0 for sec, usec in times)
        avg_secs = total_secs / len(times)
        results.append((tag, avg_secs, len(times)))

if results:
    print(f"{'Tag':<20} {'Avg Time (s)':<15} {'Iterations':<12}")
    print("=" * 50)

    baseline = None
    for tag, avg_time, iterations in results:
        if baseline is None:
            baseline = avg_time
            pct = "baseline"
        else:
            diff = ((avg_time - baseline) / baseline) * 100
            pct = f"{diff:+.1f}%"

        print(f"{tag:<20} {avg_time:>10.3f}      {iterations:<12} {pct}")
else:
    print("No results found")
EOFPYTHON

echo ""
echo "Detailed results available in: ${RESULTS_DIR}/"
