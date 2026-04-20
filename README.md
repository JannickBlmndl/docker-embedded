# Embedded Containers
## Research Goal: 
Quantify limits of containerization on small embedded systems.

This repository provides a reproducible measurement framework for evaluating how much performance overhead containerization introduces on constrained embedded hardware (e.g., Raspberry Pi, ARMv8) compared to running the same workloads directly on the host OS.

## Platforms Under Test

| Platform / Device         | Storage Type               | Intended Role                         |
|---------------------------|----------------------------|----------------------------------------|
| Raspberry Pi 4B           | microSD        | Embedded baseline                      |
| macOS Docker Desktop      | NVMe (APFS via VM)         | Development reference                  |

> **Note:** macOS Docker Desktop performs I/O through a virtualized filesystem layer, which affects latency and throughput.

---

## Quick Start

### Running Benchmarks

```bash
# Format:
# ./statistical-benchmark.sh [PR_SESSIONS] [ITERATIONS] [PLATFORM_LABEL]

# Examples:
sudo ./statistical-benchmark.sh 1 1 RPi4B
./statistical-benchmark.sh 1 1 macos-docker-desktop
```

### Analyzing Results (TO DO) <!-- USE uv run instead of pip3 -->
<!-- ```bash
pip install scipy

# Single platform
python3 analyze_results.py results/RPi4B

# Cross-platform comparison
python3 analyze_results.py --compare \
    results/RPi4B \
    results/macos-docker-desktop
``` -->

## Generate graphs (TO DO)

<!-- ```bash
uv run gen_graphs.py
``` -->

---

## Measurement Dimensions

Each benchmark captures iterations.

| #  | Test Category          | Output CSV                      | Key Metric                                   |
|----|-------------------------|----------------------------------|-----------------------------------------------|
| X  | CPU throttling          | 03-cpu-throttling-python.csv     | Runtime (s)     |
| —  | (others in progress)    | —                                |   |

---

## Statistical Methods

---

## Reproducibility Steps

1. Prepare hardware OS, python>=3.13.
2. Clone this repository.
3. Run `statistical-benchmark.sh`.
4. Use `analyze_results.py`

---

Khan, S. (2026). *Decomposing Docker container startup performance: A three‑tier measurement study of Docker on heterogeneous infrastructure*.
[https://github.com/opscart/docker-internals-guide](https://github.com/opscart/docker-internals-guide)

---