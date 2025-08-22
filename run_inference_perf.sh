#!/bin/bash
set -e

# Load configuration
source ./lib/config.sh
source ./lib/logging.sh
source ./lib/docker_utils.sh

CONFIG_FILE="myenv.config"
INPUT_FILE="1yy9_data.json"
THREADS="4"
TIMEOUT_DURATION="600"

log_info "Starting inference perf profiling"
log_info "Input: $INPUT_FILE, Threads: $THREADS, Timeout: ${TIMEOUT_DURATION}s"

# Load config
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Config file not found: $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

# Generate timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_DIR="perf_inference_${TIMESTAMP}"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Prepare input paths
INPUT_PATH="input_inference/$INPUT_FILE"
if [ ! -f "$INPUT_PATH" ]; then
    log_error "Input file not found: $INPUT_PATH"
    exit 1
fi

log_info "Creating perf profiling container..."

# Docker run command with perf profiling
DOCKER_CMD="docker run --rm \
    --gpus all \
    --shm-size=8g \
    -v \"$(pwd)/$INPUT_PATH\":/input/$INPUT_FILE:ro \
    -v \"$(pwd)/$OUTPUT_DIR\":/output \
    -v \"$DB_DIR\":/db:ro \
    -v \"$MODEL_DIR\":/models:ro \
    -e CUDA_VISIBLE_DEVICES=0 \
    -e JAX_PLATFORMS=gpu \
    -e OMP_NUM_THREADS=$THREADS \
    -e OPENMM_CPU_THREADS=$THREADS"

# Add unified memory settings if enabled
if [ "$UNIFIED_MEMORY" = "true" ]; then
    DOCKER_CMD="$DOCKER_CMD \
    -e XLA_PYTHON_CLIENT_PREALLOCATE=false \
    -e TF_FORCE_UNIFIED_MEMORY=true \
    -e XLA_CLIENT_MEM_FRACTION=3.2"
    log_info "Unified memory enabled"
fi

# Add capabilities for perf
DOCKER_CMD="$DOCKER_CMD \
    --cap-add=SYS_ADMIN \
    --cap-add=SYS_PTRACE \
    --privileged \
    -v /proc:/host_proc:ro"

DOCKER_CMD="$DOCKER_CMD alphafold3:perf"

log_info "Running inference with perf profiling..."
log_info "Output directory: $OUTPUT_DIR"

# Create the perf script inside container
cat > "$OUTPUT_DIR/run_with_perf.sh" << 'EOF'
#!/bin/bash
set -e

# Find perf binary in alphafold3:perf image (should be pre-installed)
PERF_BIN=""
for perf_path in \
    "/usr/lib/linux-tools-$(uname -r)/perf" \
    "/usr/lib/linux-tools-5.15.0-151/perf" \
    "/usr/lib/linux-tools-5.15.0-141/perf" \
    $(find /usr/lib/linux-tools* -name "perf" -type f -executable 2>/dev/null) \
    "/usr/bin/perf" \
    "$(which perf 2>/dev/null)"; do
    
    if [ -x "$perf_path" ]; then
        PERF_BIN="$perf_path"
        break
    fi
done

if [ -z "$PERF_BIN" ] || [ ! -x "$PERF_BIN" ]; then
    echo "Error: perf binary not found in alphafold3:perf image"
    echo "Available tools:"
    find /usr -name "*perf*" -type f 2>/dev/null | head -10
    echo "Installing perf tools as fallback..."
    apt-get update -qq && apt-get install -y -qq linux-tools-generic linux-tools-common > /dev/null 2>&1 || true
    PERF_BIN="$(which perf 2>/dev/null)"
    if [ -z "$PERF_BIN" ]; then
        echo "Failed to install perf"
        exit 1
    fi
fi

echo "Using perf binary: $PERF_BIN"

# Setup perf permissions
echo -1 > /proc/sys/kernel/perf_event_paranoid 2>/dev/null || true
echo 0 > /proc/sys/kernel/kptr_restrict 2>/dev/null || true

# Perf events for CPU profiling
PERF_EVENTS="cycles,instructions,cache-references,cache-misses,L1-dcache-load-misses,L1-dcache-loads,dTLB-load-misses,dTLB-loads,branch-instructions,branch-misses"

# AlphaFold command
AF_CMD="python run_alphafold.py \
    --json_path=/input/INPUT_FILE \
    --output_dir=/output \
    --db_dir=/db \
    --run_data_pipeline=false --run_inference=true"

echo "Step 1: Running AlphaFold with perf stat..."
echo "Command: $PERF_BIN stat -e $PERF_EVENTS -x , -o /output/perf_inference_stat.csv $AF_CMD"

# First run with perf stat for complete analysis
$PERF_BIN stat -e $PERF_EVENTS -x , -o /output/perf_inference_stat.csv \
    $AF_CMD 2>&1 | tee /output/inference_stat.log

# Check if stat file was created
if [ -f /output/perf_inference_stat.csv ]; then
    echo "✓ Perf stat completed successfully"
    echo "Content preview:"
    head -10 /output/perf_inference_stat.csv
else
    echo "✗ Perf stat file was not created!"
fi

echo ""
echo "Step 2: Running AlphaFold with perf record (first 100 seconds)..."
echo "Command: timeout 100s $PERF_BIN record -e $PERF_EVENTS -F 999 --timestamp -o /output/perf_inference_record.data $AF_CMD"

# Second run with perf record for detailed profiling (first 100 seconds only)
timeout 100s $PERF_BIN record \
    -e $PERF_EVENTS \
    -F 999 \
    --timestamp \
    -o /output/perf_inference_record.data \
    $AF_CMD 2>&1 | tee /output/inference_record.log || true

# Generate perf report if data exists
if [ -f /output/perf_inference_record.data ]; then
    echo "Generating perf report..."
    $PERF_BIN report \
        -i /output/perf_inference_record.data \
        --stdio \
        --sort dso,symbol \
        --percent-limit 1.0 \
        -n 20 \
        > /output/perf_inference_detailed.txt 2>/dev/null || true
        
    echo "Perf profiling completed successfully"
    echo "Files generated:"
    ls -la /output/perf_*
else
    echo "Error: perf data file not created"
fi
EOF

# Replace INPUT_FILE placeholder
sed -i "s/INPUT_FILE/$INPUT_FILE/g" "$OUTPUT_DIR/run_with_perf.sh"
chmod +x "$OUTPUT_DIR/run_with_perf.sh"

# Run the container with perf profiling
eval "$DOCKER_CMD" bash /output/run_with_perf.sh

log_info "Perf profiling completed"
log_info "Results saved in: $OUTPUT_DIR"

# Show results summary
if [ -f "$OUTPUT_DIR/perf_inference_detailed.txt" ]; then
    log_info "Perf report generated successfully"
    echo "=== Perf Profile Summary ==="
    head -30 "$OUTPUT_DIR/perf_inference_detailed.txt"
else
    log_error "Perf report not generated"
fi