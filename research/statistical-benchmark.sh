#!/bin/bash
# =============================================================================
# Docker Performance Statistical Benchmark
# Usage:
#   sudo ./statistical-benchmark.sh [PR_SESSIONS] [ITERATIONS] [PLATFORM_LABEL]
#
# Examples:
#   sudo ./statistical-benchmark.sh 1 3 RPi4B
#   sudo ./statistical-benchmark.sh 1 3 macos-docker-desktop
#
# From academic paper: "Decomposing Container Startup Performance"
# Shamsher Khan
# Repository: https://github.com/opscart/docker-internals-guide
#
# =============================================================================

set -euo pipefail

PR_SESSIONS=${1:-1} # Number of parallel sessions
ITERATIONS=${2:-50} # Number of experiment iterations
PLATFORM=${3:-"unknown-platform"}

RESULTS_DIR="results/${PLATFORM}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

PYTHON_SCRIPT_PATH="cpu_test.py"
PYTHON_UPLIM_ARG=1000 # FIXME get from bash argument
CPU_LIMIT="1.0" # CPU limit for container (e.g., 0.5 CPU core)
VENV_DIR=".venv" # Directory for the uv virtual environment

DOCKER_IMAGE="python:3.12-slim"
DOCKER_CONTAINER_IMAGE="cpu-bench"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE} Docker Performance Statistical Benchmark${NC}"
# echo -e "${BLUE} All Y Tests — Clean Run${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo "Platform:   ${PLATFORM}"
echo "Iterations: ${ITERATIONS}"
echo "Timestamp:  ${TIMESTAMP}"
echo ""

mkdir -p "${RESULTS_DIR}"

# Pre-pull images
# echo -e "${YELLOW}Pre-pulling images...${NC}"
# docker pull alpine:latest > /dev/null 2>&1
# docker pull nginx:latest > /dev/null 2>&1
# docker pull nginx:alpine > /dev/null 2>&1
# docker pull python:3.12-slim > /dev/null 2>&1
# echo -e "${GREEN}Images ready.${NC}"
# echo ""

# =============================================================================
# uv Setup
# =============================================================================
echo -e "${BLUE}[0/10] Checking for uv installation...${NC}"
UV_BIN=$(command -v uv)
if [ -z "$UV_BIN" ]; then
    echo -e "${BLUE}uv not found. Downloading uv...${NC}"
    # This downloads uv to the current directory, adjust if you prefer a different location
    # Get OS and architecture for uv download
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    case "$OS" in
        linux) OS="unknown-linux-gnu" ;;
        darwin) OS="apple-darwin" ;;
        *) echo "Unsupported OS: $OS"; exit 1 ;;
    esac

    case "$ARCH" in
        x86_64) ARCH="x86_64" ;;
        arm64|aarch64) ARCH="aarch64" ;;
        *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
    esac

    UV_URL="https://github.com/astral-sh/uv/releases/latest/download/uv-${ARCH}-${OS}"
    curl -L "$UV_URL" -o uv
    chmod +x uv
    UV_BIN="$(pwd)/uv" # Set UV_BIN to the downloaded executable
    echo -e "${GREEN}uv downloaded to $(pwd)/uv.${NC}"
else
    echo -e "${GREEN}uv found at $UV_BIN.${NC}"
fi

# --- Create and activate uv venv, install dependencies ---
echo -e "${BLUE} Setting up uv virtual environment...${NC}"
"$UV_BIN" venv "${VENV_DIR}" --clear || { echo "Failed to create uv venv"; exit 1; }

# =============================================================================
# HELPERS
# =============================================================================

clear_caches() {
    if [ -f /proc/sys/vm/drop_caches ]; then
        sync
        echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    fi
    sleep 1
}

# Nanosecond timestamp — works on both Linux and macOS
now_ns() {
    if date +%s%N 2>/dev/null | grep -qv 'N'; then
        date +%s%N
    else
        python3 -c "import time; print(int(time.time() * 1000000000))"
    fi
}

# =============================================================================
# [0/10] PLATFORM INFO
# =============================================================================
echo -e "${BLUE}[0/10] Collecting platform information...${NC}"
{
    echo "=== Platform Information ==="
    echo "Collected: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Platform Label: ${PLATFORM}"
    echo "Script Version: v3"
    echo ""
    echo "--- OS ---"
    uname -a
    echo ""
    if [ -f /etc/os-release ]; then
        cat /etc/os-release
    elif command -v sw_vers &>/dev/null; then
        sw_vers
    fi
    echo ""
    echo "--- CPU ---"
    if [ -f /proc/cpuinfo ]; then
        grep "model name" /proc/cpuinfo | head -1
        echo "CPU cores: $(nproc)"
    elif command -v sysctl &>/dev/null; then
        sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "N/A"
        echo "CPU cores: $(sysctl -n hw.ncpu 2>/dev/null || echo 'N/A')"
    fi
    echo ""
    echo "--- Memory ---"
    if command -v free &>/dev/null; then
        free -h
    elif command -v sysctl &>/dev/null; then
        echo "Total: $(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1024 / 1024 / 1024 )) GB"
    fi
    echo ""
    echo "--- Storage ---"
    df -h / 2>/dev/null || true
    if [ -f /sys/block/sda/queue/rotational ]; then
        ROT=$(cat /sys/block/sda/queue/rotational)
        if [ "$ROT" = "0" ]; then echo "Disk type: SSD"; else echo "Disk type: HDD"; fi
    fi
    echo ""
    echo "--- Docker ---"
    docker version --format '{{.Server.Version}}' 2>/dev/null || docker --version
    docker info --format '{{.Driver}}' 2>/dev/null || true
    echo ""
    echo "--- Kernel ---"
    uname -r
} > "${RESULTS_DIR}/platform-info.txt" 2>&1
echo -e "${GREEN}Platform info saved.${NC}"
echo ""

# =============================================================================
# [X/10] CPU THROTTLING (CPU micro benchmark)
# Sieve of Eratosthenes uv CPU workload {PR_SESSIONS} parallel sessions
# =============================================================================
echo -e "${BLUE}[X/10] CPU Throttling (Python Script, ${ITERATIONS} iterations)...${NC}"
CSV="${RESULTS_DIR}/03-cpu-throttling-python.csv"
echo "Iteration,Type,Session,CPU_Limit,UpperLimit,Duration_ms,Result" > "${CSV}"

# --- Run without Container (native) ---
echo -e "${GREEN}Running CPU test directly on host (baseline) with ${PR_SESSIONS} parallel sessions...${NC}"

run_single_session() {
    local i=$1
    local session=$2
    sleep 0.5
    
    START=$(now_ns)
    # TODO 
    #   either use c or python?
    #   choose UV or not?

    # RESULT=$("$(pwd)/runme.exe" -n "${PYTHON_UPLIM_ARG}" 2>/dev/null)
    RESULT=$("$UV_BIN" run "${PYTHON_SCRIPT_PATH}" -n "${PYTHON_UPLIM_ARG}" 2>/dev/null)
    END=$(now_ns)
    # echo "[DEBUG] result='${RESULT}'" >&2

    ELAPSED_NS=$((END - START))
    ELAPSED_MS=$(echo "scale=2; ${ELAPSED_NS} / 1000000" | bc)
    RESULT_INT=$(echo "$RESULT" | grep -o -E '^[0-9]+' || echo "0")
    echo "${i},Host,Session-${session},NaN,${PYTHON_UPLIM_ARG},${ELAPSED_MS},${RESULT_INT}" >> "${CSV}"
}

for i in $(seq 1 "${ITERATIONS}"); do
    PIDS=()
    for session in $(seq 1 "${PR_SESSIONS}"); do
        run_single_session "$i" "$session" &
        PIDS+=($!)
    done
    for pid in "${PIDS[@]}"; do
        wait "$pid"
    done
    if (( i % 10 == 0 )); then echo -e "    ${GREEN}${i}/${ITERATIONS}${NC}"; fi
done
echo -e "${GREEN}Host part complete.${NC}"

# --- Run with Container ---
# # Build Docker Images
# echo -e "${BLUE} Building Docker image for CPU benchmark...${NC}"
# if [ ! -f "Dockerfile" ]; then
#     echo -e "${RED}Error: Dockerfile not found in current directory${NC}"
#     exit 1
# fi
# if ! docker build -t "${DOCKER_CONTAINER_IMAGE}" . > /dev/null 2>&1; then
#     echo -e "${RED}Failed to build Docker image${NC}"
#     exit 1
# fi
# echo -e "${GREEN}Docker image '${DOCKER_CONTAINER_IMAGE}' built successfully.${NC}"
# echo ""

## 
echo -e "${GREEN}Running CPU test inside Docker container (with --cpus=${CPU_LIMIT}) and ${PR_SESSIONS} parallel sessions...${NC}"

run_container_session() {
    local i=$1
    local session=$2
    sleep 0.5

    # Dockerfile entry point python3
    # CMD="docker run --cpus=${CPU_LIMIT} \
    #   -v \"$(pwd)/${PYTHON_SCRIPT_PATH}:/${PYTHON_SCRIPT_PATH}\" \
    #   ${DOCKER_CONTAINER_IMAGE} \
    #   \"/${PYTHON_SCRIPT_PATH}\" -n ${PYTHON_UPLIM_ARG}"

    # echo -e "[DEBUG] ContainerCMD: $CMD"

    START=$(now_ns)
    # RESULT=$(eval $"CMD")
    
    RESULT=$(docker run --rm --cpus="${CPU_LIMIT}" \
      -v "$(pwd)/${PYTHON_SCRIPT_PATH}:/${PYTHON_SCRIPT_PATH}" \
      "${DOCKER_CONTAINER_IMAGE}" \
      "/${PYTHON_SCRIPT_PATH}" -n "${PYTHON_UPLIM_ARG}" 2>\
      /dev/null)
    
    END=$(now_ns)

    # Calculate elapsed time in milliseconds
    ELAPSED_NS=$((END - START))
    ELAPSED_MS=$(echo "scale=2; ${ELAPSED_NS} / 1000000" | bc)
    
    # Extract the result (should be an integer count of primes)
    RESULT_INT=$(echo "$RESULT" | grep -o -E '^[0-9]+' | head -1 || echo "0")

    echo "${i},Docker,Session-${session},${CPU_LIMIT},${PYTHON_UPLIM_ARG},${ELAPSED_MS},${RESULT_INT}" >> "${CSV}"
}

for i in $(seq 1 "${ITERATIONS}"); do
    PIDS=()
    for session in $(seq 1 "${PR_SESSIONS}"); do
        run_container_session "$i" "$session" &
        PIDS+=($!)
    done
    for pid in "${PIDS[@]}"; do
        wait "$pid"
    done
    if (( i % 10 == 0 )); then echo -e "    ${GREEN}${i}/${ITERATIONS}${NC}"; fi
done

echo -e "${GREEN}Container test complete.${NC}"
echo ""

echo -e "${GREEN}Test X complete.${NC}"
echo ""

# =============================================================================
# FINAL SUMMARY
# =============================================================================

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE} All Y Tests Complete!${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo "Results saved to: ${RESULTS_DIR}/"
echo ""
ls -la "${RESULTS_DIR}/"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo "  1. Fix file ownership (if run with sudo):"
echo "     sudo chown -R \$(whoami) results/"
echo ""
echo "  2. Install scipy and analyze:"
echo "     pip3 install scipy"
echo "     python3 analyze_results.py ${RESULTS_DIR} | tee ${RESULTS_DIR}/analysis-summary.txt"
echo ""
echo "  3. Commit results:"
echo "     git add ${RESULTS_DIR}/"
echo "     git commit -m 'research: benchmark data (${PLATFORM})'"
echo "     git push"
echo ""
# echo "  4. After all platforms are done, compare:"
# echo "     python3 analyze_results.py --compare results/azure-premium-ssd results/azure-standard-hdd results/macos-docker-desktop"