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

# Publishes benchmark results to Cloudflare Pages
# Auto-detects type and mode from target/benchmark/README.md

RESULTS_DIR="target/benchmark"
README="${RESULTS_DIR}/README.md"

# Check prerequisites
if [ ! -f "${README}" ]; then
  echo "ERROR: ${README} not found"
  echo "Please run ./run-libs.sh or ./run-vers.sh first, followed by the corresponding report script"
  exit 1
fi

if [ ! -f "${RESULTS_DIR}/index.html" ]; then
  echo "ERROR: ${RESULTS_DIR}/index.html not found"
  echo "Please run the corresponding report script (./report-libs.sh or ./report-vers.sh)"
  exit 1
fi

# Check for required environment variables
if [ -z "${CLOUDFLARE_API_TOKEN:-}" ] || [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
  echo "ERROR: Required environment variables not set"
  echo ""
  echo "Please set the following environment variables:"
  echo "  export CLOUDFLARE_API_TOKEN=\"your-token\""
  echo "  export CLOUDFLARE_ACCOUNT_ID=\"your-account-id\""
  echo ""
  echo "These should be set in your ~/.bashrc or ~/.zshrc for convenience"
  exit 1
fi

# Check for wrangler
if ! command -v wrangler &> /dev/null; then
  echo "ERROR: wrangler not found"
  echo "Please install: npm install -g wrangler"
  exit 1
fi

echo "Analyzing benchmark results..."

# Detect benchmark type from README heading
if grep -q "## LmdbJava Library Comparison Benchmarks" "${README}"; then
  BENCH_TYPE="libraries"
  echo "  Detected: Library comparison benchmarks"
elif grep -q "## LmdbJava Performance Regression Testing" "${README}"; then
  BENCH_TYPE="versions"
  echo "  Detected: Version regression benchmarks"
else
  echo "ERROR: Could not determine benchmark type from ${README}"
  echo "Expected heading: '## LmdbJava Library Comparison Benchmarks' or '## LmdbJava Performance Regression Testing'"
  exit 1
fi

# Detect benchmark mode from smoketest warning
if grep -q "⚠️ SMOKETEST RESULTS" "${README}"; then
  BENCH_MODE="smoketest"
  echo "  Detected: Smoketest mode (fast verification)"
else
  BENCH_MODE="benchmark"
  echo "  Detected: Benchmark mode (full 120s iterations)"
fi

# Determine Cloudflare Pages project and DNS name
PROJECT="lmdbjava-${BENCH_TYPE}-${BENCH_MODE}"
DNS_NAME="${BENCH_TYPE}-${BENCH_MODE}.lmdbjava.org"

echo ""
echo "Publishing to Cloudflare Pages..."
echo "  Project: ${PROJECT}"
echo "  DNS: https://${DNS_NAME}"
echo ""

# Check if project exists, create if needed
if ! wrangler pages project list 2>/dev/null | grep -q "│ ${PROJECT} "; then
  echo "Creating new Cloudflare Pages project: ${PROJECT}"
  if ! wrangler pages project create "${PROJECT}" --production-branch=main; then
    echo ""
    echo "ERROR: Failed to create project"
    exit 1
  fi
  echo ""
fi

# Deploy using wrangler (environment variables are automatically used)
if ! wrangler pages deploy "${RESULTS_DIR}" \
    --project-name="${PROJECT}" \
    --branch=main \
    --commit-dirty=true; then
  echo ""
  echo "ERROR: Deployment failed"
  exit 1
fi

echo ""
echo "✓ Deployment successful!"
echo ""
echo "Your results are now available at:"
echo "  https://${DNS_NAME}"
echo ""
echo "Note: If this is the first deployment, you'll need to set up the custom domain:"
echo "  1. Go to Cloudflare Dashboard → Workers & Pages"
echo "  2. Click on project: ${PROJECT}"
echo "  3. Go to Custom domains → Set up a custom domain"
echo "  4. Enter: ${DNS_NAME}"
echo "  5. Click Activate domain"
echo ""
