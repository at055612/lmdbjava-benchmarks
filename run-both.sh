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

# Usage: ./run-both.sh [ram_percent]
# Runs both library and version benchmarks in benchmark mode (full 120s iterations)
# Designed for overnight runs - takes several hours to complete

RAM_PERCENT="${1:-25}"

echo "========================================"
echo "LmdbJava Full Benchmark Suite"
echo "========================================"
echo ""
echo "This will run both library comparison and version regression benchmarks"
echo "using ${RAM_PERCENT}% of system RAM with full 120s iterations."
echo ""
echo "Estimated duration: Several hours (depends on system performance)"
echo "Started at: $(date)"
echo ""

START_TIME=$(date +%s)

# Run library comparison benchmarks
echo "========================================"
echo "Step 1/2: Library Comparison Benchmarks"
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
LIBS_DURATION=$((LIBS_END_TIME - START_TIME))
LIBS_HOURS=$((LIBS_DURATION / 3600))
LIBS_MINUTES=$(((LIBS_DURATION % 3600) / 60))

echo ""
echo "Library benchmarks duration: ${LIBS_HOURS}h ${LIBS_MINUTES}m"
echo ""

# Run version regression benchmarks
echo "========================================"
echo "Step 2/2: Version Regression Benchmarks"
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
echo "Use report-*.sh to generate target/benchmark suitable for publish-results.sh"
echo ""

if [ "$LIBS_SUCCESS" = true ] && [ "$VERS_SUCCESS" = true ]; then
  exit 0
else
  exit 1
fi
