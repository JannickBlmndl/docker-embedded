#!/bin/bash
# =============================================================================
# Docker Performance Statistical Benchmark
# Usage:
#   sudo ./statistical-benchmark.sh [NR_THREADS] [ITERATIONS] [PLATFORM_LABEL]
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

NR_THREADS=${1:-1} # Number of parallel threads
ITERATIONS=${2:-50} # Number of experiment iterations
PLATFORM=${3:-"unknown-platform"}

RESULTS_DIR="results/${PLATFORM}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT_FILENAME="cpu_test.py"
PYTHON_UPLIM_ARG=10 # FIXME get from bash argument
CPU_LIMIT="1.0" # CPU limit for container (e.g., 0.5 CPU core)
VENV_DIR=".venv" # Directory for the uv virtual environment

DOCKER_IMAGE="python:3.12-slim"
DOCKER_CONTAINER_IMAGE="cpu-bench"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

printf "%b\n" "${BLUE}============================================${NC}"
printf "%b\n" "${BLUE} Docker Performance Statistical Benchmark${NC}"
# echo -e "${BLUE} All Y Tests — Clean Run${NC}"
printf "%b\n" "${BLUE}============================================${NC}"
printf "\n"
printf "Platform:   %s\n" "${PLATFORM}"
printf "Iterations: %s\n" "${ITERATIONS}"
printf "Timestamp:  %s\n" "${TIMESTAMP}"
printf "\n"

mkdir -p "${RESULTS_DIR}"

# Pre-pull images
printf "%b\n" "${YELLOW}Pre-pulling images...${NC}"
docker pull alpine:latest > /dev/null 2>&1
# docker pull nginx:latest > /dev/null 2>&1
# docker pull nginx:alpine > /dev/null 2>&1
docker pull python:3.12-slim > /dev/null 2>&1
printf "%b\n" "${GREEN}Images ready.${NC}"
printf "\n"

# =============================================================================
# uv Setup
# =============================================================================
printf "%b\n" "${BLUE}[0/10] Checking for uv installation...${NC}"
UV_BIN=$(command -v uv)
if [ -z "$UV_BIN" ]; then
    printf "%b\n" "${BLUE}uv not found. Downloading uv...${NC}"
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
    printf "%b\n" "${GREEN}uv downloaded to $(pwd)/uv.${NC}"
else
    printf "%b\n" "${GREEN}uv found at $UV_BIN.${NC}"
fi

# --- Create and activate uv venv, install dependencies ---
printf "%b\n" "${BLUE} Setting up uv virtual environment...${NC}"
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
printf "%b\n" "${BLUE}[0/10] Collecting platform information...${NC}"
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
printf "%b\n" "${GREEN}Platform info saved.${NC}"
printf "\n"

# =============================================================================
# [X/10] CPU THROTTLING (CPU micro benchmark)
# Sieve of Eratosthenes uv CPU workload {NR_THREADS} parallel sessions
# =============================================================================
printf "%b\n" "${BLUE}[X/10] CPU Throttling (Python Script, ${ITERATIONS} iterations)...${NC}"
CSV="${RESULTS_DIR}/03-cpu-throttling-python.csv"
printf "Iteration,Type,Session,CPU_Limit,UpperLimit,Duration_ms,Result\n" > "${CSV}"

# --- Run without Container (native) ---
printf "%b\n" "${GREEN}Running CPU test directly on host (baseline) with ${NR_THREADS} parallel threads...${NC}"

run_single_thread()
{
    local i=$1
    local session=$2
    sleep 0.5
    
    START=$(now_ns)
    # TODO 
    #   either use c or python?
    #   choose UV or not?

    # RESULT=$("$(pwd)/runme.exe" -n "${PYTHON_UPLIM_ARG}" 2>/dev/null)
    RESULT=$("$UV_BIN" run "${PYTHON_SCRIPT_FILENAME}" -n "${PYTHON_UPLIM_ARG}" 2>/dev/null)
    END=$(now_ns)
    # echo "[DEBUG] result='${RESULT}'" >&2

    ELAPSED_NS=$((END - START))
    ELAPSED_MS=$(echo "scale=2; ${ELAPSED_NS} / 1000000" | bc)
    RESULT_INT=$(echo "$RESULT" | grep -o -E '^[0-9]+' || echo "0")
    printf "%s,Host,Session-%s,NaN,%s,%s,%s\n" "$i" "$session" "$PYTHON_UPLIM_ARG" "$ELAPSED_MS" "$RESULT_INT" >> "$CSV"
}

for i in $(seq 1 "${ITERATIONS}"); do
    PIDS=()
    for session in $(seq 1 "${NR_THREADS}"); do
        run_single_thread "$i" "$session" &
        PIDS+=($!)
    done
    for pid in "${PIDS[@]}"; do
        wait "$pid"
    done
    if (( i % 10 == 0 )); then printf "%b\n" "    ${GREEN}${i}/${ITERATIONS}${NC}"; fi
done
printf "%b\n" "${GREEN}CPU native part complete.${NC}"

# --- Run with Container ---
# Build Docker Image
echo -e "${BLUE} Building Docker image for CPU benchmark...${NC}"
if [ ! -f "Dockerfile" ]; then
    echo -e "${RED}Error: Dockerfile not found in current directory${NC}"
    exit 1
fi
if ! docker build -t "${DOCKER_CONTAINER_IMAGE}" . > /dev/null 2>&1; then
    echo -e "${RED}Failed to build Docker image${NC}"
    exit 1
fi
echo -e "${GREEN}Docker image '${DOCKER_CONTAINER_IMAGE}' built successfully.${NC}"
printf "\n"

#
printf "%b\n" "${GREEN}Running CPU test inside Docker container (with --cpus=${CPU_LIMIT}) and ${NR_THREADS} parallel sessions...${NC}"

run_container_session()
{
    local i=$1
    local session=$2
    sleep 0.5

    START=$(now_ns) # Host time tracking 

    # With built docker image
    RESULT=$(docker run --cpus="${CPU_LIMIT}" \
        -v "$(pwd)/${PYTHON_SCRIPT_FILENAME}:/${PYTHON_SCRIPT_FILENAME}" \
        ${DOCKER_CONTAINER_IMAGE} \
        "/${PYTHON_SCRIPT_FILENAME}" -n ${PYTHON_UPLIM_ARG} 2>/dev/null)

    # BASH 2 seconds 100% throtte
    # RESULT=$(docker run --rm alpine sh -c '
    #     START=$(date +%s); COUNT=0
    #     while true; do
    #         NOW=$(date +%s); ELAPSED=$((NOW - START))
    #         if [ $ELAPSED -ge 2 ]; then break; fi
    #         COUNT=$((COUNT + 1))
    #     done
    #     echo $COUNT
    # ' 2>/dev/null)

    # PYTHON PRIMES WORKLOAD (dep error)
    # RESULT=$(docker run --rm \
    #     -v "${SCRIPT_DIR}:/app" \
    #     python:3.12-slim \
    #     python3 "/app/${PYTHON_SCRIPT_FILENAME}" -n "${PYTHON_UPLIM_ARG}" \
    #     2>/dev/null
    # )

    END=$(now_ns)

    # Calculate elapsed time in milliseconds
    ELAPSED_NS=$((END - START))
    ELAPSED_MS=$(echo "scale=2; ${ELAPSED_NS} / 1000000" | bc)
    
    RESULT_INT=$(echo "$RESULT" | grep -o -E '^[0-9]+' | head -1 || echo "0")

    # echo "Python script output (RESULT_INT):"
    # echo "${RESULT}"
    
    printf "%s,Docker,Session-%s,%s,%s,%s,%s\n" "$i" "$session" "$CPU_LIMIT" "$PYTHON_UPLIM_ARG" "$ELAPSED_MS" "$RESULT_INT" >> "$CSV"
}

for i in $(seq 1 "${ITERATIONS}"); do
    PIDS=()
    for session in $(seq 1 "${NR_THREADS}"); do
        run_container_session "$i" "$session" &
        PIDS+=($!)
    done
    for pid in "${PIDS[@]}"; do
        wait "$pid"
    done
    if (( i % 10 == 0 )); then printf "%b\n" "    ${GREEN}${i}/${ITERATIONS}${NC}"; fi
done

printf "%b\n" "${GREEN}Container test complete.${NC}"
printf "\n"

printf "%b\n" "${GREEN}Test X complete.${NC}"
printf "\n"


# =============================================================================
# FINAL SUMMARY
# =============================================================================

printf "%b\n" "${BLUE}============================================${NC}"
printf "%b\n" "${BLUE} All Y Tests Complete!${NC}"
printf "%b\n" "${BLUE}============================================${NC}"
printf "\n"
printf "Results saved to: %s/\n" "${RESULTS_DIR}"
printf "\n"
ls -la "${RESULTS_DIR}/"
printf "\n"
printf "%b\n" "${YELLOW}Next steps:${NC}"
printf "\n"
printf "  1. Fix file ownership (if run with sudo):\n"
printf "      sudo chown -R $(whoami) results/\n"
printf "\n"
printf "  2. Install scipy and analyze:\n"
printf "     pip3 install scipy\n"
printf "     python3 analyze_results.py %s | tee %s/analysis-summary.txt\n" "${RESULTS_DIR}" "${RESULTS_DIR}"
printf "\n"
printf "  3. Commit results:\n"
printf "     git add %s/\n" "${RESULTS_DIR}"
printf "     git commit -m 'research: benchmark data (%s)'\n" "${PLATFORM}"
printf "     git push\n"
printf "\n"

# echo "  4. After all platforms are done, compare:"
# echo "     python3 analyze_results.py --compare results/azure-premium-ssd results/azure-standard-hdd results/macos-docker-desktop"