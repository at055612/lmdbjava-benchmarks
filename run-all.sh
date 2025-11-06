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

# Usage: ./run-all.sh [ram_percent]
# Runs all three benchmark suites (LMDB, libraries, versions) in benchmark mode
# Designed for overnight runs - takes several hours to complete

RAM_PERCENT="${1:-25}"

echo "========================================"
echo "LmdbJava Full Benchmark Suite"
echo "========================================"
echo ""
echo "This will run all three benchmark suites:"
echo "  1. LMDB library comparison"
echo "  2. Library comparison (all implementations)"
echo "  3. Version regression testing"
echo ""
echo "Using ${RAM_PERCENT}% of system RAM with full 120s iterations."
echo ""
echo "Estimated duration: Several hours (depends on system performance)"
echo "Started at: $(date)"
echo ""

START_TIME=$(date +%s)

# Run LMDB library comparison benchmarks
echo "========================================"
echo "Step 1/3: LMDB Library Comparison"
echo "========================================"
echo ""

if ./run-lmdb.sh benchmark; then
  echo ""
  echo "✓ LMDB library comparison completed successfully"
  LMDB_SUCCESS=true
else
  echo ""
  echo "✗ LMDB library comparison failed"
  LMDB_SUCCESS=false
fi

LMDB_END_TIME=$(date +%s)
LMDB_DURATION=$((LMDB_END_TIME - START_TIME))
LMDB_HOURS=$((LMDB_DURATION / 3600))
LMDB_MINUTES=$(((LMDB_DURATION % 3600) / 60))

echo ""
echo "LMDB benchmarks duration: ${LMDB_HOURS}h ${LMDB_MINUTES}m"
echo ""

# Run library comparison benchmarks
echo "========================================"
echo "Step 2/3: Library Comparison Benchmarks"
echo "========================================"
echo ""

if ./run-libs.sh benchmark "$RAM_PERCENT"; then
  echo ""
  echo "✓ Library comparison benchmarks completed successfully"
  LIBS_SUCCESS=true
else
  echo ""
  echo "✗ Library comparison benchmarks failed"
  LIBS_SUCCESS=false
fi

LIBS_END_TIME=$(date +%s)
LIBS_DURATION=$((LIBS_END_TIME - LMDB_END_TIME))
LIBS_HOURS=$((LIBS_DURATION / 3600))
LIBS_MINUTES=$(((LIBS_DURATION % 3600) / 60))

echo ""
echo "Library benchmarks duration: ${LIBS_HOURS}h ${LIBS_MINUTES}m"
echo ""

# Run version regression benchmarks
echo "========================================"
echo "Step 3/3: Version Regression Benchmarks"
echo "========================================"
echo ""

if ./run-vers.sh benchmark "$RAM_PERCENT"; then
  echo ""
  echo "✓ Version regression benchmarks completed successfully"
  VERS_SUCCESS=true
else
  echo ""
  echo "✗ Version regression benchmarks failed"
  VERS_SUCCESS=false
fi

VERS_END_TIME=$(date +%s)
VERS_DURATION=$((VERS_END_TIME - LIBS_END_TIME))
VERS_HOURS=$((VERS_DURATION / 3600))
VERS_MINUTES=$(((VERS_DURATION % 3600) / 60))

echo ""
echo "Version benchmarks duration: ${VERS_HOURS}h ${VERS_MINUTES}m"
echo ""

# Summary
END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))
TOTAL_HOURS=$((TOTAL_DURATION / 3600))
TOTAL_MINUTES=$(((TOTAL_DURATION % 3600) / 60))

echo "========================================"
echo "Benchmark Suite Complete"
echo "========================================"
echo ""
echo "Finished at: $(date)"
echo ""
echo "Results:"
if [ "$LMDB_SUCCESS" = true ]; then
  echo "  ✓ LMDB benchmarks: ${LMDB_HOURS}h ${LMDB_MINUTES}m"
else
  echo "  ✗ LMDB benchmarks failed: ${LMDB_HOURS}h ${LMDB_MINUTES}m"
fi

if [ "$LIBS_SUCCESS" = true ]; then
  echo "  ✓ Library benchmarks: ${LIBS_HOURS}h ${LIBS_MINUTES}m"
else
  echo "  ✗ Library benchmarks failed: ${LIBS_HOURS}h ${LIBS_MINUTES}m"
fi

if [ "$VERS_SUCCESS" = true ]; then
  echo "  ✓ Version benchmarks: ${VERS_HOURS}h ${VERS_MINUTES}m"
else
  echo "  ✗ Version benchmarks failed: ${VERS_HOURS}h ${VERS_MINUTES}m"
fi

echo ""
echo "Total duration: ${TOTAL_HOURS}h ${TOTAL_MINUTES}m"
echo ""
echo "Generate reports with:"
echo "  ./report-lmdb.sh"
echo "  ./report-libs.sh"
echo "  ./report-vers.sh"
echo ""

if [ "$LMDB_SUCCESS" = true ] && [ "$LIBS_SUCCESS" = true ] && [ "$VERS_SUCCESS" = true ]; then
  exit 0
else
  exit 1
fi
