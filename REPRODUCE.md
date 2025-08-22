# Reproduction Guide

This guide explains how to reproduce the key results from our paper using AFSysBench.

## System Requirements for Reproduction

### Server-scale Reproduction (Recommended)
- **RAM**: DDR5 512GB+
- **GPU**: NVIDIA H100 (80GB) or better
- **Storage**: PCIe Gen4 SSD (≥2TB)
- **Purpose**: Full paper reproduction with optimal performance

### Desktop Reproduction (IO-bound)
- **RAM**: DDR5 64–128GB
- **GPU**: RTX 4080 (16GB) or equivalent
- **Storage**: PCIe Gen4 SSD (≥2TB, critical for IO-bound workloads)
- **Note**: Large complexes may be impractical; smaller test cases are feasible

---

## Quick Test (5-7 minutes)

**For reviewers**: Start here to verify your setup works before running full benchmarks.

```bash
# Test complete pipeline - MSA + Inference
python runner -c benchmark.config msa -i 2PV7.json -t 1
python runner -c benchmark.config inference -i 2pv7_data.json -t 1

# Expected output:
# - MSA completes in 3-4 minutes (database search)
# - Inference completes in 2-3 minutes (structure prediction)
# - Creates results/msa_* and results/inference_* directories
# - Shows "Benchmark completed successfully" for both stages
```

**Success indicators:**
- No Docker errors
- GPU memory usage logged (if GPU available)
- Output structure file exists
- Timing metrics recorded

If this works, proceed with full reproduction below. If not, check [INSTALL.md](INSTALL.md) for troubleshooting.

## Reproducing Paper Results

### Figure 3: Total AF3 Execution Time (MSA + Inference)

**What it measures**: Complete AlphaFold 3 pipeline execution time across different thread counts on Server and Desktop platforms

**Tested structures**: 2PV7, 7RCE, 1YY9, promo, 6QNR

**Scripts to run**:
```bash
# Run comprehensive statistical benchmarks (covers all structures and thread counts)
./run_statistical_benchmarks.sh

# This script automatically runs:
# - All structures: 2PV7, 7RCE, 1YY9, promo  
# - All thread counts: 1, 2, 4, 6, 8
# - Both MSA and Inference stages
# - 5 iterations each for statistical analysis
```

**Expected execution times** (based on paper results):
- **2PV7**: 600-1000s (1T) → 300-400s (4T+)
- **7RCE**: 800-900s (1T) → 400-500s (4T+) 
- **1YY9**: 3000s (1T) → 1200-1500s (4T+)
- **promo**: 5000s (1T) → 1500-2000s (4T+)
- **6QNR**: 8000-9000s (1T) → 5500-6000s (4T+)

**Output location**: `statistical_results_*/` with analysis in `analysis_results/detailed_statistics.txt`

### Figure 4: MSA Execution Time Detail

**What it measures**: MSA execution time on different samples and hardware platforms across 1-8 threads

**Tested structures**: 2PV7, 7RCE, 1YY9, promo

**Scripts to run**:
```bash
# Use the comprehensive benchmark script (includes MSA analysis)
./run_statistical_benchmarks.sh

# For MSA-only analysis, the script will generate detailed MSA timing data
```

**Expected MSA execution times** (based on paper results):
- **2PV7**: 900s (1T Server), 650s (1T Desktop) → ~300-400s (4T+)
- **7RCE**: 850s (1T) → ~300-400s (4T+)
- **1YY9**: 2900s (1T Server), 1100s (1T Desktop) → ~1000-1200s (4T+)
- **promo**: 5000s (1T Server), 3900s (1T Desktop) → ~1300-1600s (4T+)

**Output location**: `statistical_results_*/` with analysis in `analysis_results/detailed_statistics.txt`

### Figure 6: Inference Phase Execution Time

**What it measures**: Inference phase execution time comparison across different thread configurations (1-8 threads) on Server and Desktop systems

**Tested structures**: 2PV7, 7RCE, 1YY9, promo

**Scripts to run**:
```bash
# Use the comprehensive benchmark script (includes inference analysis)
./run_statistical_benchmarks.sh

# For inference-only analysis, the script will generate detailed inference timing data
```

**Expected inference execution times** (based on paper results):
- **2PV7**: ~80-140s (Server), ~100s (Desktop)
- **7RCE**: ~150-210s (Server), ~210s (Desktop)
- **1YY9**: ~150-220s (Server), ~220s (Desktop)
- **promo**: ~140-220s (Desktop), similar on Server

**Output location**: `statistical_results_*/` with analysis in `analysis_results/detailed_statistics.txt`

### Figure 8: GPU Inference Time Breakdown (Nsight Profiling)

**What it measures**: Detailed breakdown of GPU inference time showing CPU Compute, XLA Compile, and GPU Compute phases

**Tested structures**: 2PV7, 1YY9, promo

**Scripts to run**:
```bash
# Run with Nsight profiling (requires NVIDIA Nsight Systems)
python runner -c benchmark.config profile -i 2pv7_data.json -p nsys -s inference
python runner -c benchmark.config profile -i 1yy9_data.json -p nsys -s inference  
python runner -c benchmark.config profile -i promo_data.json -p nsys -s inference
```

**Expected time breakdown patterns** (based on paper results):
- **Server systems**: More balanced between CPU/XLA/GPU (e.g., 45%/32%/23% for 2PV7)
- **Desktop systems**: GPU-dominated (e.g., 19%/10%/71% for 2PV7)
- **Larger structures**: Higher GPU compute percentage

**Output location**: `results/nsight_profile_*/`

### Unified Memory Performance Test

**What it measures**: Performance comparison with and without unified memory for large structures

**Scripts to run**:
```bash
# Edit config file for each test:

# Without unified memory (requires 24GB+ GPU)
# Set UNIFIED_MEMORY=false in benchmark.config
python runner -c benchmark.config inference -i 6QNR_subset_data.json -t 4

# With unified memory (works on 16GB GPU) 
# Set UNIFIED_MEMORY=true in benchmark.config
python runner -c benchmark.config inference -i 6QNR_subset_data.json -t 4
```

**Compare**: Execution times and memory usage between runs



## Validation

### Verify Output Structures

Check that generated structures are valid:

```bash
# List generated structure files
ls -la results/*/output/*.cif

# Check file sizes (should be non-zero)
find results -name "*.cif" -exec ls -lh {} \;
```

### Compare Performance Metrics

```bash
# View statistical analysis results
cat statistical_results_*/analysis_results/detailed_statistics.txt

# Extract timing information from individual runs
grep "Total inference time" results/*/logs/*.log

# Extract memory usage
grep "Peak GPU memory" results/*/logs/*.log
```

### Expected Performance Ranges

Based on paper results with Server and Desktop platforms:

| Structure | Total Time (1T) | Total Time (4T+) | MSA Time (1T) | Inference Time |
|-----------|----------------|------------------|---------------|----------------|
| 2pv7      | 600-1000s      | 300-400s         | 650-900s      | 80-140s        |
| 7rce      | 800-900s       | 400-500s         | 850s          | 150-210s       |
| 1yy9      | 1100-3000s     | 1000-1500s       | 1100-2900s    | 150-220s       |
| promo     | 3900-5000s     | 1300-2000s       | 3900-5000s    | 140-220s       |
| 6QNR      | 8000-9000s     | 5500-6000s       | N/A           | N/A            |

**Performance varies by**:
- Hardware platform (Server vs Desktop)
- Thread count (1T vs 4T+ shows significant improvement)  
- GPU model and compute capability
- I/O performance for database access

## Troubleshooting Reproduction

### Results differ significantly from paper

1. **Check GPU model**: Performance scales with GPU compute capability
2. **Verify AlphaFold version**: Ensure using the same AF3 version
3. **Check configuration**: Compare your `benchmark.config` with template
4. **System load**: Run benchmarks on idle system for consistency

### Benchmark fails to complete

1. **Memory issues**: Enable unified memory or reduce batch size
2. **Timeout**: Increase timeout values in configuration
3. **Docker issues**: Check Docker daemon and GPU access

### Cannot find output files

```bash
# List all result directories
ls -la results/

# Find all generated structures
find results -name "*.cif" -o -name "*.pdb"
```

## Minimal Reproduction Set

If you want to quickly verify the setup works (30 minutes total):

```bash
# 1. Quick test - complete pipeline (5-7 min)
python runner -c benchmark.config msa -i 2PV7.json -t 1
python runner -c benchmark.config inference -i 2pv7_data.json -t 1

# 2. Medium structure test (15-20 min)  
python runner -c benchmark.config msa -i rcsb_pdb_1YY9.json -t 1
python runner -c benchmark.config inference -i 1yy9_data.json -t 1

# 3. Large structure with monitoring (25-30 min)
./monitor_realtime.sh &
MONITOR_PID=$!
python runner -c benchmark.config msa -i promo.json -t 1
python runner -c benchmark.config inference -i promo_data.json -t 1
kill $MONITOR_PID
```

## Full Reproduction Set

For complete paper reproduction (covers all Figures 3, 4, 6):

```bash
# Single script covers all paper figures
./run_statistical_benchmarks.sh

# This comprehensive script includes:
# - Figure 3: Complete AF3 pipeline (MSA + Inference) 
# - Figure 4: MSA execution time analysis
# - Figure 6: Inference execution time analysis
# - All structures: 2PV7, 7RCE, 1YY9, promo
# - All thread counts: 1, 2, 4, 6, 8 threads
# - Statistical analysis with 5 iterations each
```

**Expected runtime**: 8-10 hours total

**Output**: Raw CSV data with timing results + automatic statistical analysis
- **CSV data**: `statistical_results_*/statistical_summary.csv`
- **Analysis report**: `statistical_results_*/analysis_results/detailed_statistics.txt`
- **No Python dependencies required** - built-in bash/awk analysis included

## Data Format

### Input Format
- JSON files with structure information
- See `input_inference/*.json` for examples

### Output Format
- CIF/PDB structure files
- JSON confidence scores
- Log files with timing information
- CSV performance metrics

## Contact

For reproduction issues:
- GitHub Issues: https://github.com/stable-lab/AFSysBench/issues
- Include: System specs, error logs, configuration used

## Citation

If you use AFSysBench in your research, please cite:

```bibtex
@misc{afsysbench2025,
  title={AFSysBench: Systematic Benchmarking of AlphaFold 3 for Optimized Deployment},
  author={[To be updated]},
  year={2024},
  note={Manuscript in preparation. Citation details will be updated upon publication.}
}
```

*Note: This work is currently under review. Full citation details will be provided upon publication.*