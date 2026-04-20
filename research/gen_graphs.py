# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "numpy==1.26.4",
#     "pandas==2.2.3",
#     "matplotlib==3.7.5"
# ]
# ///
""" Generate graphs from data
Usage:
uv run gen_graphs.py

"""

import os
import csv
import pandas as pd
import numpy as np
from collections import defaultdict

try:
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    import matplotlib.patches as mpatches
except ImportError:
    print("Install matplotlib!")

PLATFORMS = {
    'macos-docker-desktop': {'label': 'macOS Docker Desktop', 'color': '#4CAF50', 'short': 'macOS DD'},
}

RESULTS_BASE = 'results'
FIGURES_DIR = 'figures'
os.makedirs(FIGURES_DIR, exist_ok=True)

plt.rcParams.update({
    'font.family': 'arial',
    'font.size': 10,
    'axes.titlesize': 13,
    'axes.labelsize': 12,
    'xtick.labelsize': 10,
    'ytick.labelsize': 10,
    'legend.fontsize': 10,
    'figure.dpi': 300,
    'savefig.bbox': 'tight',
    'savefig.pad_inches': 0.1,
})

def load_csv(filepath):
    if not os.path.exists(filepath):
        return []
    with open(filepath, 'r') as f:
        return list(csv.DictReader(f))


def parse_float(val):
    if val is None:
        return None
    val = str(val).strip()
    for suffix in [' ms', 'ms', ' MB/s', 'MB/s', ' MB', 'MB', ' KB', 'KB', '%']:
        if val.endswith(suffix):
            val = val[:-len(suffix)].strip()
    try:
        return float(val)
    except ValueError:
        return None


def get_values(platform, csv_file, field, mode_filter=None, mode_field='mode'):
    fp = os.path.join(RESULTS_BASE, platform, csv_file)
    rows = load_csv(fp)
    vals = []
    for r in rows:
        if mode_filter and r.get(mode_field) != mode_filter:
            continue
        v = parse_float(r.get(field))
        if v is not None:
            vals.append(v)
    return vals

#####################
def figx_cpu_throttling():

    fig, ax = plt.subplots(figsize=(8, 5))
    for idx, (platform, cfg) in enumerate(PLATFORMS.items()):
        csv_path = os.path.join(RESULTS_BASE, platform, '03-cpu-throttling-python.csv')
        if not os.path.exists(csv_path):
            print(f"WARNING: Missing {csv_path}")
            continue
        df = pd.read_csv(csv_path)

        # --- Clean data ---
        for t in df['Type'].unique():
            subset = df[df['Type'] == t]

            # Scatter
            ax.scatter(
                subset['UpperLimit'],
                subset['Duration_ms'],
                label=f"{cfg['short']} {t}",
                alpha=0.4
            )


    ax.set_xlabel('Upper Limit (Workload Size)')
    ax.set_ylabel('Execution Time (ms)')
    ax.set_title('CPU Workload Performance: Host vs Docker')
    ax.set_xscale('log')

    ax.legend()
    ax.grid(alpha=0.3)

    plt.savefig(os.path.join(FIGURES_DIR, 'figx-cpu-throttling.png'))
    plt.savefig(os.path.join(FIGURES_DIR, 'figx-cpu-throttling.pdf'))
    plt.close()

    print("  Generated: figx-cpu-throttling.png")


if __name__ == '__main__':
    print("Generating figures...")
    print()

    available = [p for p in PLATFORMS if os.path.isdir(os.path.join(RESULTS_BASE, p))]
    if not available:
        print(f"ERROR: No platform directories found in {RESULTS_BASE}/")
        print(f"Expected: {list(PLATFORMS.keys())}")
        exit(1)

    print(f"Found platforms: {available}")
    print()

    figx_cpu_throttling()

    print()
    print(f"All figures saved to {FIGURES_DIR}/")
    print("Both PNG (for review) and PDF (for LaTeX) formats generated.")