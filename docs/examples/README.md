# Examples

## Basic Usage

### MSA Benchmark
```bash
# Single protein MSA benchmark
python af_bench_runner_updated.py -c my_system.config msa -i 2PV7.json -t 4
```

### Inference Benchmark
```bash
# Single protein inference benchmark
python af_bench_runner_updated.py -c my_system.config inference -i 2pv7_data.json -t 4
```

## Multi-threading Analysis

### Test Different Thread Counts
```bash
# Test performance across thread configurations
SAMPLE="1YY9"
THREADS="1 2 4 8 16"

for t in $THREADS; do
    echo "Running with $t threads..."
    python af_bench_runner_updated.py -c my_system.config msa -i ${SAMPLE}.json -t $t
done
```

## Large Structure Processing

### 6QNR with Unified Memory
```bash
# Edit config to enable unified memory
nano my_system.config
# Set: UNIFIED_MEMORY=true

# Run 6QNR inference
python af_bench_runner_updated.py -c my_system.config inference -i 6QNR_subset_data.json -t 1
```

## Batch Processing

### Multiple Samples
```bash
# Process multiple proteins
SAMPLES="2PV7 7RCE 1YY9 promo"

for sample in $SAMPLES; do
    echo "Processing $sample..."
    
    # MSA benchmark
    python af_bench_runner_updated.py -c my_system.config msa -i ${sample}.json -t 4
    
    # Inference benchmark
    python af_bench_runner_updated.py -c my_system.config inference -i ${sample}_data.json -t 4
done
```

### Complete Benchmark Suite
```bash
# Run comprehensive benchmarks
SAMPLES=(
    "2PV7:2pv7_data"
    "7RCE:rcsb_pdb_7rce_data"  
    "1YY9:1yy9_data"
    "promo:promo_data"
)

THREADS="1 2 4 8"

for entry in "${SAMPLES[@]}"; do
    IFS=':' read -r msa_file inf_file <<< "$entry"
    
    for t in $THREADS; do
        echo "Processing $msa_file with $t threads..."
        
        # MSA
        python af_bench_runner_updated.py -c my_system.config msa -i ${msa_file}.json -t $t
        
        # Inference  
        python af_bench_runner_updated.py -c my_system.config inference -i ${inf_file}.json -t $t
    done
done
```

## Profiling Examples

### NVIDIA Nsight Systems
```bash
# Run with nsys profiling
python af_bench_runner_updated.py -c my_system.config inference -i sample_data.json -t 4 -p nsys

# Output: output_inference/*/nsys_profile_*.nsys-rep
```

### Linux Perf
```bash
# Run with perf profiling
python af_bench_runner_updated.py -c my_system.config msa -i sample.json -t 4 -p perf

# Output: output_msa/*/perf.data
```

## System Comparison

### Compare Two Configurations
```bash
# Test workstation config
cp configs/workstation.config my_system.config
python af_bench_runner_updated.py -c my_system.config inference -i test_data.json -t 8
mv results/master_results.csv results/workstation_results.csv

# Test server config
cp configs/server.config my_system.config
python af_bench_runner_updated.py -c my_system.config inference -i test_data.json -t 8
mv results/master_results.csv results/server_results.csv
```

## Monitoring During Benchmarks

### GPU Monitoring
```bash
# In separate terminal while benchmark runs
watch -n 1 'nvidia-smi; echo; free -h'
```

### Results Analysis
```bash
# Check latest results
tail -10 results/master_results.csv

# View GPU utilization
tail output_inference/*/gpu_monitoring.csv
```