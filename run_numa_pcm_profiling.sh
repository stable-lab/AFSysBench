#!/bin/bash
set -e

# Updated test script with NUMA-aware performance comparison first, then PCM profiling
# Based on user requirements: NUMA test first, then PCM profiling for remaining inputs

# Load configuration and utilities
source ./lib/config.sh
source ./lib/logging.sh
source ./lib/docker_utils.sh

CONFIG_FILE="myenv.config"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULTS_DIR="numa_pcm_results_${TIMESTAMP}"

log_info "Starting NUMA-aware performance comparison and PCM profiling"
log_info "Results directory: $RESULTS_DIR"

# Load config
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Config file not found: $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

# Create results directory
mkdir -p "$RESULTS_DIR"

# Verified input files (checked against actual directory contents)
MSA_INPUTS=("2PV7.json" "promo.json" "rcsb_pdb_1YY9.json" "rcsb_pdb_7RCE.json" "6QNR_subset.json")
INFERENCE_INPUTS=("2pv7_data.json" "promo_data.json" "rcsb_pdb_7rce_data.json" "1yy9_data.json" "6QNR_subset_data.json")

# NUMA test configuration
NUMA_TEST_INPUT="2PV7.json"
NUMA_THREADS=(4 8)

log_info "=== PHASE 1: NUMA-AWARE PERFORMANCE COMPARISON ==="
log_info "Testing input: $NUMA_TEST_INPUT with threads: ${NUMA_THREADS[*]}"

# Function to run NUMA test
run_numa_test() {
    local input_file="$1"
    local threads="$2"
    local numa_policy="$3"
    local test_name="$4"
    
    local output_dir="$RESULTS_DIR/numa_${test_name}_${threads}t"
    mkdir -p "$output_dir"
    
    log_info "Running NUMA test: $test_name with $threads threads"
    
    # Docker command with NUMA settings
    local docker_cmd="docker run --rm \
        --gpus all \
        --shm-size=8g \
        -v \"$(pwd)/input_msa/$input_file\":/input/$input_file:ro \
        -v \"$(pwd)/$output_dir\":/output \
        -v \"$DB_DIR\":/db:ro \
        -v \"$MODEL_DIR\":/models:ro \
        -e CUDA_VISIBLE_DEVICES=0 \
        -e JAX_PLATFORMS=gpu \
        -e OMP_NUM_THREADS=$threads \
        -e OPENMM_CPU_THREADS=$threads"
    
    # Add unified memory settings if enabled
    if [ "$UNIFIED_MEMORY" = "true" ]; then
        docker_cmd="$docker_cmd \
        -e XLA_PYTHON_CLIENT_PREALLOCATE=false \
        -e TF_FORCE_UNIFIED_MEMORY=true \
        -e XLA_CLIENT_MEM_FRACTION=3.2"
    fi
    
    docker_cmd="$docker_cmd alphafold3:perf"
    
    # Create NUMA-aware execution script
    cat > "$output_dir/run_numa.sh" << EOF
#!/bin/bash
set -e
echo "=== NUMA Test: $test_name with $threads threads ==="
echo "NUMA policy: $numa_policy"
echo "Input: $input_file"
echo "Start time: \$(date)"

# Run with NUMA policy
time $numa_policy python run_alphafold.py \\
    --json_path=/input/$input_file \\
    --output_dir=/output \\
    --db_dir=/db \\
    --run_data_pipeline=true --run_inference=false

echo "End time: \$(date)"
echo "NUMA test completed: $test_name"
EOF
    
    chmod +x "$output_dir/run_numa.sh"
    
    # Execute the NUMA test
    echo "Executing: $docker_cmd bash /output/run_numa.sh"
    eval "$docker_cmd" bash /output/run_numa.sh 2>&1 | tee "$output_dir/numa_test.log"
    
    # Extract timing information
    if [ -f "$output_dir/numa_test.log" ]; then
        local runtime=$(grep -E "real|user|sys" "$output_dir/numa_test.log" | head -3)
        echo "=== $test_name Results ===" >> "$RESULTS_DIR/numa_summary.txt"
        echo "Threads: $threads" >> "$RESULTS_DIR/numa_summary.txt"
        echo "NUMA Policy: $numa_policy" >> "$RESULTS_DIR/numa_summary.txt"
        echo "$runtime" >> "$RESULTS_DIR/numa_summary.txt"
        echo "" >> "$RESULTS_DIR/numa_summary.txt"
    fi
}

# Run NUMA tests for 2PV7.json
for threads in "${NUMA_THREADS[@]}"; do
    # Test 1: Default (no NUMA binding)
    run_numa_test "$NUMA_TEST_INPUT" "$threads" "" "default"
    
    # Test 2: Bind to NUMA nodes 0,1 with interleaved memory
    run_numa_test "$NUMA_TEST_INPUT" "$threads" "numactl --cpunodebind=0,1 --interleave=all" "numa_interleave"
    
    # Test 3: Bind to NUMA node 0 only
    run_numa_test "$NUMA_TEST_INPUT" "$threads" "numactl --cpunodebind=0 --membind=0" "numa_node0"
    
    # Test 4: Bind to NUMA node 1 only  
    run_numa_test "$NUMA_TEST_INPUT" "$threads" "numactl --cpunodebind=1 --membind=1" "numa_node1"
done

log_info "=== NUMA Performance Comparison Results ==="
if [ -f "$RESULTS_DIR/numa_summary.txt" ]; then
    cat "$RESULTS_DIR/numa_summary.txt"
else
    log_error "NUMA summary not generated"
fi

log_info "=== PHASE 2: PCM PROFILING FOR REMAINING INPUTS ==="

# Function to run PCM profiling
run_pcm_profiling() {
    local stage="$1"
    local input_file="$2"
    local input_dir="$3"
    local threads="4"  # Use 4 threads for PCM profiling
    
    local output_dir="$RESULTS_DIR/pcm_${stage}_$(basename "$input_file" .json)"
    mkdir -p "$output_dir"
    
    log_info "Running PCM profiling: $stage - $input_file"
    
    # Docker command for PCM profiling
    local docker_cmd="docker run --rm \
        --gpus all \
        --shm-size=8g \
        --privileged \
        --cap-add=SYS_ADMIN \
        -v \"$(pwd)/$input_dir/$input_file\":/input/$input_file:ro \
        -v \"$(pwd)/$output_dir\":/output \
        -v \"$DB_DIR\":/db:ro \
        -v \"$MODEL_DIR\":/models:ro \
        -v /proc:/host_proc:ro \
        -e CUDA_VISIBLE_DEVICES=0 \
        -e JAX_PLATFORMS=gpu \
        -e OMP_NUM_THREADS=$threads \
        -e OPENMM_CPU_THREADS=$threads"
    
    # Add unified memory settings if enabled
    if [ "$UNIFIED_MEMORY" = "true" ]; then
        docker_cmd="$docker_cmd \
        -e XLA_PYTHON_CLIENT_PREALLOCATE=false \
        -e TF_FORCE_UNIFIED_MEMORY=true \
        -e XLA_CLIENT_MEM_FRACTION=3.2"
    fi
    
    docker_cmd="$docker_cmd alphafold3:perf"
    
    # Create PCM profiling script
    local af_stage_flag=""
    if [ "$stage" = "msa" ]; then
        af_stage_flag="--run_data_pipeline=true --run_inference=false"
    else
        af_stage_flag="--run_data_pipeline=false --run_inference=true"
    fi
    
    cat > "$output_dir/run_pcm.sh" << EOF
#!/bin/bash
set -e
echo "=== PCM Profiling: $stage - $input_file ==="
echo "Threads: $threads"
echo "Start time: \$(date)"

# Check if PCM is available
if command -v pcm-memory.x >/dev/null 2>&1; then
    echo "PCM tools found, starting memory profiling..."
    # Start PCM memory monitoring in background
    pcm-memory.x -csv -o /output/pcm_memory.csv &
    PCM_PID=\$!
    echo "PCM memory monitoring started (PID: \$PCM_PID)"
else
    echo "PCM tools not found, continuing without PCM profiling"
    PCM_PID=""
fi

# Run AlphaFold with timing
time python run_alphafold.py \\
    --json_path=/input/$input_file \\
    --output_dir=/output \\
    --db_dir=/db \\
    $af_stage_flag

# Stop PCM monitoring
if [ -n "\$PCM_PID" ]; then
    echo "Stopping PCM monitoring..."
    kill \$PCM_PID 2>/dev/null || true
    wait \$PCM_PID 2>/dev/null || true
    echo "PCM monitoring stopped"
fi

echo "End time: \$(date)"
echo "PCM profiling completed: $stage - $input_file"
EOF
    
    chmod +x "$output_dir/run_pcm.sh"
    
    # Execute PCM profiling
    echo "Executing: $docker_cmd bash /output/run_pcm.sh"
    eval "$docker_cmd" bash /output/run_pcm.sh 2>&1 | tee "$output_dir/pcm_profile.log"
}

# Run PCM profiling for MSA inputs (excluding 2PV7.json which was used for NUMA testing)
log_info "PCM profiling MSA inputs..."
for input in "${MSA_INPUTS[@]}"; do
    if [ "$input" != "$NUMA_TEST_INPUT" ]; then
        run_pcm_profiling "msa" "$input" "input_msa"
    fi
done

# Run PCM profiling for inference inputs
log_info "PCM profiling inference inputs..."
for input in "${INFERENCE_INPUTS[@]}"; do
    run_pcm_profiling "inference" "$input" "input_inference"
done

# Generate final summary
log_info "=== PROFILING COMPLETED ==="
log_info "Results saved in: $RESULTS_DIR"

echo "=== Final Summary ===" > "$RESULTS_DIR/final_summary.txt"
echo "Test completed at: $(date)" >> "$RESULTS_DIR/final_summary.txt"
echo "" >> "$RESULTS_DIR/final_summary.txt"

echo "NUMA Tests Performed:" >> "$RESULTS_DIR/final_summary.txt"
echo "- Input: $NUMA_TEST_INPUT" >> "$RESULTS_DIR/final_summary.txt"
echo "- Threads: ${NUMA_THREADS[*]}" >> "$RESULTS_DIR/final_summary.txt"
echo "- Policies: default, numa_interleave, numa_node0, numa_node1" >> "$RESULTS_DIR/final_summary.txt"
echo "" >> "$RESULTS_DIR/final_summary.txt"

echo "PCM Profiling Performed:" >> "$RESULTS_DIR/final_summary.txt"
echo "MSA inputs (excluding NUMA test input):" >> "$RESULTS_DIR/final_summary.txt"
for input in "${MSA_INPUTS[@]}"; do
    if [ "$input" != "$NUMA_TEST_INPUT" ]; then
        echo "  - $input" >> "$RESULTS_DIR/final_summary.txt"
    fi
done
echo "Inference inputs:" >> "$RESULTS_DIR/final_summary.txt"
for input in "${INFERENCE_INPUTS[@]}"; do
    echo "  - $input" >> "$RESULTS_DIR/final_summary.txt"
done

if [ -f "$RESULTS_DIR/numa_summary.txt" ]; then
    echo "" >> "$RESULTS_DIR/final_summary.txt"
    echo "=== NUMA Performance Results ===" >> "$RESULTS_DIR/final_summary.txt"
    cat "$RESULTS_DIR/numa_summary.txt" >> "$RESULTS_DIR/final_summary.txt"
fi

log_info "Final summary saved to: $RESULTS_DIR/final_summary.txt"
cat "$RESULTS_DIR/final_summary.txt"