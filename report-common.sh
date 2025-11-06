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

# Common functions for HTML report generation

# System information extraction
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

# Detect benchmark mode from JSON file
get_benchmark_mode() {
  local json_file=$1
  local warmup_iterations=$(jq -r '.[0].warmupIterations' "$json_file")
  if [ "$warmup_iterations" = "0" ]; then
    echo "smoketest"
  else
    echo "benchmark"
  fi
}

# Calculate SHA256 hash for cache busting
get_file_hash() {
  local file=$1
  sha256sum "$file" | cut -d' ' -f1
}

# Emit img tag with cache-busting hash
emit_img() {
  local filename=$1
  local alt_text=$2
  local hash=$(get_file_hash "$filename")
  echo "    <img src=\"${filename}?v=${hash}\" alt=\"${alt_text}\" style=\"max-width: 100%; height: auto;\">"
}

# Get LmdbJava git metadata (from files written by run scripts in results directory)
# Takes data directory as parameter
get_lmdbjava_branch() {
  local data_dir=${1:-lmdb/results}
  if [ -f "${data_dir}/lmdbjava-git-branch.txt" ]; then
    cat "${data_dir}/lmdbjava-git-branch.txt"
  else
    echo "unknown"
  fi
}

get_lmdbjava_commit_short() {
  local data_dir=${1:-lmdb/results}
  if [ -f "${data_dir}/lmdbjava-git-commit-short.txt" ]; then
    cat "${data_dir}/lmdbjava-git-commit-short.txt"
  else
    echo "unknown"
  fi
}

get_lmdbjava_commit_full() {
  local data_dir=${1:-lmdb/results}
  if [ -f "${data_dir}/lmdbjava-git-commit-full.txt" ]; then
    cat "${data_dir}/lmdbjava-git-commit-full.txt"
  else
    echo "unknown"
  fi
}

# Emit GitHub-style CSS (embedded in HTML)
emit_html_css() {
  cat <<'CSS'
  <style>
    html {
      min-height: 100%;
    }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
      line-height: 1.6;
      color: #24292e;
      margin: 0;
      padding: 0;
      background: #eaeef2;
      min-height: 100%;
    }
    .container {
      max-width: 1012px;
      margin: 2rem auto;
      padding: 2rem;
      background: #ffffff;
      box-shadow: 0 1px 3px rgba(27,31,35,0.12), 0 8px 24px rgba(66,74,83,0.12);
    }
    h1, h2, h3 {
      border-bottom: 1px solid #e1e4e8;
      padding-bottom: 0.3em;
      margin-top: 1.5em;
      margin-bottom: 1em;
    }
    h1 { font-size: 2em; margin-top: 0; }
    h2 { font-size: 1.5em; }
    h3 { font-size: 1.25em; }
    table {
      width: auto;
      border-collapse: collapse;
      margin: 1em 0;
      border: 1px solid #d0d7de;
    }
    th, td {
      padding: 6px 13px;
      border: 1px solid #d0d7de;
      text-align: left;
    }
    th {
      background-color: #f6f8fa;
      font-weight: 600;
    }
    tr:nth-child(even) {
      background-color: #f6f8fa;
    }
    code {
      background-color: rgba(175,184,193,0.2);
      padding: 0.2em 0.4em;
      border-radius: 3px;
      font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
      font-size: 85%;
    }
    figure {
      max-width: 100%;
      overflow-x: auto;
      margin: 2em 0;
    }
    figure img {
      max-width: 100%;
      height: auto;
    }
    blockquote {
      margin: 1em 0;
      padding: 0 1em;
      color: #57606a;
    }
    @media (max-width: 768px) {
      .container {
        margin: 1rem;
        padding: 1rem;
      }
      table {
        font-size: 0.9em;
      }
      th, td {
        padding: 4px 8px;
      }
    }
  </style>
CSS
}

# Emit HTML header with title
emit_html_header() {
  local title=$1
  cat <<HEADER
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title}</title>
HEADER
  emit_html_css
  cat <<'HEADER_END'
</head>
<body>
  <div class="container">
HEADER_END
}

# Emit smoketest warning block
emit_smoketest_warning() {
  local bench_mode=$1
  if [ "$bench_mode" = "smoketest" ]; then
    cat <<'WARNING'
  <blockquote style="border-left: 4px solid #f0ad4e; background: #fcf8e3; padding: 1em;">
    <strong>⚠️ SMOKETEST RESULTS</strong>
    <p>This report was generated from a <strong>smoketest run</strong> and should NOT be used for
    performance comparisons or production decisions. Smoketest results have:</p>
    <ul>
      <li>No warmup iterations</li>
      <li>Single iteration</li>
      <li>Minimal entry counts</li>
      <li>Short runtime</li>
    </ul>
    <p>For valid performance results, run the benchmark script with <code>benchmark</code> mode instead.</p>
  </blockquote>
WARNING
  fi
}

# Emit system environment table
emit_system_environment() {
  local cpu_model=$1
  local cpu_count=$2
  local ram_gib=$3
  local kernel=$4
  local java_version=$5
  local lmdbjava_branch=${6:-}
  local lmdbjava_commit_short=${7:-}
  local lmdbjava_commit_full=${8:-}

  cat <<SYSENV
  <h3>Test Environment</h3>
  <table>
    <tbody>
      <tr><td><strong>CPU</strong></td><td>${cpu_model} (${cpu_count} cores)</td></tr>
      <tr><td><strong>RAM</strong></td><td>${ram_gib} GiB</td></tr>
      <tr><td><strong>OS</strong></td><td>Linux ${kernel} (x86_64)</td></tr>
      <tr><td><strong>Java</strong></td><td>${java_version}</td></tr>
SYSENV

  # Only include LmdbJava row if commit info is provided
  if [ -n "$lmdbjava_commit_full" ]; then
    cat <<LMDBJAVA
      <tr><td><strong>LmdbJava</strong></td><td><a href="https://github.com/lmdbjava/lmdbjava/tree/${lmdbjava_commit_full}"><code>${lmdbjava_branch}#${lmdbjava_commit_short}</code></a></td></tr>
LMDBJAVA
  fi

  cat <<'SYSENV_END'
    </tbody>
  </table>
SYSENV_END
}

# Emit HTML footer
emit_html_footer() {
  cat <<'FOOTER'
  </div>
</body>
</html>
FOOTER
}
