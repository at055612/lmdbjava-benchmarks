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

# Development script for testing local LmdbJava changes
# Compiles LmdbJava from dev/lmdbjava and runs benchmarks with it

# ==============================================================================
# CONFIGURATION - Edit these variables as needed
# ==============================================================================

# Benchmark to run (full JMH benchmark qualifier)
BENCHMARK_NAME="LmdbJavaAgrona.write"

# JMH configuration (defaults to fast settings for quick iteration)
# For full bisection-matching results, use: JMH_RUNTIME=30, NUM_ENTRIES=1000000
JMH_FORKS=1
JMH_ITERATIONS=1
JMH_WARMUP=1
JMH_RUNTIME=3  # seconds

# Test configuration
NUM_ENTRIES=10000  # Small for fast testing

# ==============================================================================
# SETUP
# ==============================================================================

DEV_DIR="dev"
LMDBJAVA_DIR="$DEV_DIR/lmdbjava"
OUTPUT_DIR="$DEV_DIR/output"

# Check for dev/lmdbjava
if [ ! -d "$LMDBJAVA_DIR" ]; then
  echo "ERROR: $LMDBJAVA_DIR not found"
  echo ""
  echo "Please clone LmdbJava to $LMDBJAVA_DIR:"
  echo "  git clone git@github.com:lmdbjava/lmdbjava.git $LMDBJAVA_DIR"
  echo ""
  echo "Or use HTTPS:"
  echo "  git clone https://github.com/lmdbjava/lmdbjava.git $LMDBJAVA_DIR"
  exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get current git revision
cd "$LMDBJAVA_DIR"
GIT_REV=$(git rev-parse --short HEAD)
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
cd - > /dev/null

echo "=========================================="
echo "LmdbJava Development Benchmark"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  LmdbJava: $GIT_BRANCH @ $GIT_REV"
echo "  Benchmark: $BENCHMARK_NAME"
echo "  Entries: $NUM_ENTRIES"
echo "  JMH: -f $JMH_FORKS -wi $JMH_WARMUP -i $JMH_ITERATIONS -r ${JMH_RUNTIME}s"
echo ""

# ==============================================================================
# BUILD LMDBJAVA
# ==============================================================================

echo "Building LmdbJava..."
cd "$LMDBJAVA_DIR"
if ! mvn clean install -DskipTests -Dfmt.skip -q; then
  echo "ERROR: LmdbJava build failed"
  exit 1
fi
cd - > /dev/null
echo "  ✓ LmdbJava built successfully"
echo ""

# ==============================================================================
# BUILD BENCHMARKS
# ==============================================================================

echo "Building benchmarks..."

# Update pom.xml to use local SNAPSHOT version
cp pom.xml pom.xml.backup
sed -i 's|<lmdbjava.version>.*</lmdbjava.version>|<lmdbjava.version>0.9.2-SNAPSHOT</lmdbjava.version>|g' pom.xml

if ! mvn clean package -DskipTests -q; then
  echo "ERROR: Benchmark build failed"
  cp pom.xml.backup pom.xml
  exit 1
fi

# Restore original pom
cp pom.xml.backup pom.xml

echo "  ✓ Benchmarks built successfully"
echo ""

# ==============================================================================
# RUN BENCHMARK
# ==============================================================================

TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
JSON_FILE="$OUTPUT_DIR/result-${GIT_REV}-${TIMESTAMP}.json"
LOG_FILE="$OUTPUT_DIR/result-${GIT_REV}-${TIMESTAMP}.log"

echo "Running benchmark..."
echo "  Output: $LOG_FILE"
echo "  JSON: $JSON_FILE"
echo ""

# JVM flags for Java 9+ module system compatibility
JVM_OPTS="--add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.lang.reflect=ALL-UNNAMED --add-opens java.base/java.nio=ALL-UNNAMED --add-exports java.base/jdk.internal.misc=ALL-UNNAMED --add-exports java.base/sun.nio.ch=ALL-UNNAMED --add-exports jdk.compiler/com.sun.tools.javac.file=ALL-UNNAMED --enable-native-access=ALL-UNNAMED"

# Run JMH benchmark with verbose output to capture forked process debug logs
java -jar target/benchmarks.jar \
  -v EXTRA \
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
  -jvmArgs "$JVM_OPTS" \
  -rff "$JSON_FILE" \
  "$BENCHMARK_NAME" > "$LOG_FILE" 2>&1 || true

echo "=========================================="
echo "Benchmark Complete"
echo "=========================================="
echo ""

# Extract and display results
if [ -f "$JSON_FILE" ]; then
  SCORE=$(python3 -c "
import json
with open('$JSON_FILE') as f:
    data = json.load(f)
    if data:
        print(f\"{data[0]['primaryMetric']['score']:.2f} ms/op\")
    else:
        print('N/A')
" 2>/dev/null || echo "N/A")

  echo "Result: $SCORE"
  echo ""
fi

echo "Output files:"
echo "  Log: $LOG_FILE"
echo "  JSON: $JSON_FILE"
echo ""
echo "To view debug output:"
echo "  grep DEBUG $LOG_FILE"
echo ""
