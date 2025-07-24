# Unified Memory Guide

## Overview
Unified Memory allows GPUs to access system RAM when GPU VRAM is insufficient. Essential for running large structures like 6QNR on consumer GPUs.

## When to Enable

### Enable Unified Memory:
- **Large structures exceeding GPU memory**
  - 6QNR requires ~15GB, RTX 4080 has 16GB total
- **Getting out-of-memory errors**
- **Consumer GPUs with limited VRAM**
  - RTX 4080 (16GB) + 6QNR ✅
  - RTX 3080 (10GB) + large proteins ✅

### Don't Enable:
- **High-end GPUs with sufficient VRAM**
  - H100 (80GB) ❌
  - A100 (40GB) ❌
  - RTX 4090 (24GB) ❌

## Configuration

Edit your config file:
```bash
nano my_system.config

# Change this line:
UNIFIED_MEMORY=true
```

## How It Works

When enabled, AFSysBench automatically sets:
```bash
XLA_PYTHON_CLIENT_PREALLOCATE=false    # Don't pre-allocate GPU memory
TF_FORCE_UNIFIED_MEMORY=true           # Enable TensorFlow unified memory
XLA_CLIENT_MEM_FRACTION=3.2            # Request 320% of GPU memory
```

## Performance Impact

| Configuration | 6QNR Runtime | Notes |
|--------------|--------------|-------|
| H100 (80GB) | ~5 minutes | No unified memory needed |
| RTX 4080 + Unified | ~8-10 minutes | 60-100% slower but works |
| RTX 4080 without | Fails | Out of memory |

## Example: 6QNR on RTX 4080

```bash
# 1. Enable unified memory
nano my_system.config
# Set: UNIFIED_MEMORY=true

# 2. Run benchmark
python af_bench_runner_updated.py -c my_system.config inference -i 6QNR_subset_data.json -t 1

# 3. Expected output in log:
# Running model inference with seed 1 took 486.67 seconds
# Fold job 6QNR_subset done, output written to /output/6qnr_subset
```

## Success Indicators
✅ Log shows: "Running model inference with seed 1 took XXX seconds"  
✅ Output contains: `*.cif`, `*_confidences.json` files  
✅ GPU memory stays at ~97% (not crashing)  
✅ System RAM usage increases during run

## Troubleshooting

### Still Getting OOM Errors
1. Verify: `grep UNIFIED_MEMORY my_system.config` shows `true`
2. Check: Sufficient system RAM available (`free -h`)
3. Ensure: No other GPU processes running

### Too Slow Performance
1. Close other GPU applications
2. Ensure fast system RAM (DDR4-3200+ recommended)
3. Consider upgrading to 24GB+ GPU for production use