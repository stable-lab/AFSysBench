# Reproduction Guide

This guide explains how to reproduce the key results from our paper using AFSysBench.

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

### Table 1: Inference Performance Across Different Structures

**What it measures**: Inference time and memory usage for structures of varying sizes

**Scripts to run**:
```bash
# Run inference benchmarks for all structures
./run_inference_perf.sh

# Or run individually:
python runner -c benchmark.config inference -i 2pv7_data.json -t 4
python runner -c benchmark.config inference -i 1yy9_data.json -t 4  
python runner -c benchmark.config inference -i rcsb_pdb_7rce_data.json -t 4
python runner -c benchmark.config inference -i promo_data.json -t 4
python runner -c benchmark.config inference -i 6QNR_subset_data.json -t 4
```

**Expected runtime**: 
- Small structures (2pv7): 3-5 minutes
- Medium structures (1yy9, 7rce): 10-15 minutes
- Large structures (promo): 20-30 minutes
- Very large (6QNR): 45-60 minutes

**Output location**: `results/inference_benchmark_*/`

### Table 2: MSA Generation Performance

**What it measures**: Time for Multiple Sequence Alignment generation

**Scripts to run**:
```bash
# Run MSA benchmarks
python runner -c benchmark.config msa -i 2PV7.json -t 4
python runner -c benchmark.config msa -i rcsb_pdb_1YY9.json -t 4
python runner -c benchmark.config msa -i rcsb_pdb_7RCE.json -t 4
python runner -c benchmark.config msa -i promo.json -t 4
```

**Expected runtime**: 15-30 minutes per structure (depends on database size)

**Output location**: `results/msa_benchmark_*/`

### Figure 3: Memory Usage Patterns

**What it measures**: GPU memory consumption during inference

**Scripts to run**:
```bash
# Monitor memory during inference
./monitor_realtime.sh &  # Start monitoring in background
MONITOR_PID=$!

# Run inference
./scripts/benchmark_inference_modular.sh input_inference/6QNR_subset_data.json 1

# Stop monitoring
kill $MONITOR_PID
```

**Output location**: `results/memory_profile_*/`

### Figure 4: Unified Memory Performance

**What it measures**: Performance with and without unified memory

**Scripts to run**:
```bash
# Edit config file for each test:

# Without unified memory (requires 24GB+ GPU)
# Set ENABLE_UNIFIED_MEMORY=false in benchmark.config
python runner -c benchmark.config inference -i 6QNR_subset_data.json -t 4

# With unified memory (works on 16GB GPU) 
# Set ENABLE_UNIFIED_MEMORY=true in benchmark.config
python runner -c benchmark.config inference -i 6QNR_subset_data.json -t 4
```

**Compare**: Execution times and memory usage between runs

### Table 3: Statistical Analysis (10 runs)

**What it measures**: Performance variance across multiple runs

**Scripts to run**:
```bash
# Run statistical benchmarks (10 iterations each)
./run_statistical_benchmarks.sh

# This will run each structure 10 times and collect statistics
```

**Expected runtime**: 3-4 hours total

**Output location**: `statistical_results_*/`

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
# Extract timing information
grep "Total inference time" results/*/logs/*.log

# Extract memory usage
grep "Peak GPU memory" results/*/logs/*.log
```

### Expected Performance Ranges

Based on our testing with NVIDIA A100 (40GB):

| Structure | Inference Time | Peak GPU Memory |
|-----------|---------------|-----------------|
| 2pv7      | 3-5 min       | 4-6 GB          |
| 1yy9      | 10-15 min     | 8-10 GB         |
| 7rce      | 10-15 min     | 8-10 GB         |
| promo     | 20-30 min     | 12-15 GB        |
| 6QNR      | 45-60 min     | 20-24 GB        |

**Note**: Times may vary based on:
- GPU model and compute capability
- CPU performance
- I/O speed
- System load

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
# Check output directory setting
grep OUTPUT_DIR benchmark.config

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
python runner -c benchmark.config msa -i promo.json -t 1
python runner -c benchmark.config inference -i promo_data.json -t 1
killall monitor_realtime.sh
```

## Full Reproduction Set

For complete paper reproduction (8-10 hours):

```bash
# Run all benchmarks
./run_full_validation.sh

# This includes:
# - All inference benchmarks (5 structures × 10 runs)
# - All MSA benchmarks (4 structures × 10 runs)
# - Memory profiling
# - Statistical analysis
```

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
@misc{afsysbench2024,
  title={AFSysBench: Systematic Benchmarking of AlphaFold 3 for Optimized Deployment},
  author={[To be updated]},
  year={2024},
  note={Manuscript in preparation. Citation details will be updated upon publication.}
}
```

*Note: This work is currently under review. Full citation details will be provided upon publication.*