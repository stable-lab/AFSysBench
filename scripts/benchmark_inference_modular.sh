#!/bin/bash
# benchmark_inference_refactored.sh - AlphaFold inference performance benchmark
# Refactored version using shared libraries

set -e

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/validation.sh"
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/docker_utils.sh"
source "$SCRIPT_DIR/../lib/monitoring.sh"
source "$SCRIPT_DIR/../lib/result_parser.sh"

# Initialize logging
init_logging "benchmark_inference"

# Default values
JSON_FILE=""
OVERRIDE_THREADS=""
NSYS_PROFILING=false
PERFORMANCE_ONLY=false
USE_GPU=true
MODELS_COUNT=1
UNIFIED_MEMORY=false

# Usage
show_usage() {
    echo "Usage: $0 -c <config_file> [OPTIONS] <json_file>"
    echo ""
    echo "Required:"
    echo "  -c <config_file>  Configuration file (.config)"
    echo "  <json_file>       Input JSON file (in input_inference/ directory)"
    echo ""
    echo "Options:"
    echo "  -t <threads>      Override thread counts (e.g., '4 8 16')"
    echo "  -n, --nsys        Enable NSYS profiling"
    echo "  -p, --perf-only   Performance timing only (no profiling)"
    echo "  --cpu-only        Force CPU-only inference"
    echo "  -m <count>        Number of models to generate (default: 5)"
    echo "  -h, --help        Show this help"
    echo ""
    echo "Directory Structure:"
    echo "  input_inference/  Input JSON files (with MSA data)"
    echo "  output_inference/ Inference results and benchmarks"
    echo "  configs/          Configuration files"
    echo ""
    echo "Examples:"
    echo "  $0 -c myenv.config protein_with_msa.json"
    echo "  $0 -c server.config -n -m 3 large_protein.json"
    echo "  $0 -c laptop.config --cpu-only -p small_protein.json"
    echo ""
    echo "Note: JSON files should contain MSA data to skip data pipeline"
}

# Parameter parsing
CONFIG_FILE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -t|--threads)
            OVERRIDE_THREADS="$2"
            shift 2
            ;;
        -n|--nsys)
            NSYS_PROFILING=true
            shift
            ;;
        -p|--perf-only)
            PERFORMANCE_ONLY=true
            shift
            ;;
        --cpu-only)
            USE_GPU=false
            shift
            ;;
        -m|--models)
            MODELS_COUNT="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            # Positional argument (JSON file)
            if [ -z "$JSON_FILE" ]; then
                JSON_FILE="$1"
            else
                log_error "Too many arguments"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate required arguments
if [ -z "$CONFIG_FILE" ]; then
    log_error "Config file is required (-c option)"
    show_usage
    exit 1
fi

if [ -z "$JSON_FILE" ]; then
    log_error "JSON file is required"
    show_usage
    exit 1
fi

# Load configuration using shared library
log_info "Loading configuration: $CONFIG_FILE"
load_config "$CONFIG_FILE"

# Apply overrides
if [ -n "$OVERRIDE_THREADS" ]; then
    THREAD_COUNTS="$OVERRIDE_THREADS"
fi

# Determine Docker image and run purpose
ACTUAL_DOCKER_IMAGE="$DOCKER_IMAGE"
RUN_PURPOSE="performance"
PROFILING_TOOL=""

if [ "$NSYS_PROFILING" = true ]; then
    ACTUAL_DOCKER_IMAGE="${DOCKER_IMAGE}:nsys"
    RUN_PURPOSE="profiling"
    PROFILING_TOOL="nsys"
fi

# Unified memory configuration (set via config file)
# UNIFIED_MEMORY can be set to true in config file for large structures that exceed GPU memory

# Setup paths - Inference specific
mkdir -p "$INFERENCE_INPUT_DIR"

JSON_BASENAME_NO_EXT=$(basename "$JSON_FILE" .json)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_DIR="${INFERENCE_OUTPUT_BASE}/inference_${SYSTEM_NAME}_${TIMESTAMP}"
mkdir -p "$RESULT_DIR"

# CSV file paths
RESULTS_CSV="$RESULT_DIR/inference_results_${SYSTEM_NAME}_${JSON_BASENAME_NO_EXT}.csv"
MASTER_CSV="${SCRIPT_DIR}/../results/master_results.csv"
PROFILING_CSV="${SCRIPT_DIR}/../results/profiling_metadata.csv"

# Initialize master CSV if needed
init_master_csv "$MASTER_CSV"
init_profiling_csv "$PROFILING_CSV"

# Log benchmark configuration
log_info "=== AlphaFold Inference Benchmark ==="
log_info "System: $SYSTEM_NAME ($SYSTEM_TYPE)"
log_info "Config: $CONFIG_FILE"
log_info "Input: $JSON_FILE"
log_info "DB: $DB_DIR"
log_info "Model: $MODEL_DIR"
log_info "Docker: $ACTUAL_DOCKER_IMAGE"
log_info "Threads: $THREAD_COUNTS"
log_info "Models: $MODELS_COUNT"
log_info "GPU: $USE_GPU"
log_info "Results: $RESULT_DIR"
log_info "Run purpose: $RUN_PURPOSE"
if [ -n "$PROFILING_TOOL" ]; then
    log_info "Profiling tool: $PROFILING_TOOL"
fi

# Validate prerequisites using shared library
validate_docker
validate_docker_image "$ACTUAL_DOCKER_IMAGE"
# Handle both absolute paths and relative filenames
if [[ "$JSON_FILE" == */* ]]; then
    # JSON_FILE already contains a path
    validate_input_file "$JSON_FILE"
    FULL_INPUT_PATH="$JSON_FILE"
    JSON_FILENAME=$(basename "$JSON_FILE")
else
    # JSON_FILE is just a filename, prepend INFERENCE_INPUT_DIR
    validate_input_file "$INFERENCE_INPUT_DIR/$JSON_FILE"
    FULL_INPUT_PATH="$INFERENCE_INPUT_DIR/$JSON_FILE"
    JSON_FILENAME="$JSON_FILE"
fi
validate_model_directory "$MODEL_DIR"

# GPU validation
if [ "$USE_GPU" = true ]; then
    validate_gpu_setup
fi

# CSV header for local results
{
    echo "# System: $SYSTEM_NAME"
    echo "# Date: $(date)"
    echo "# Input: $JSON_FILE"
    echo "# Config: $CONFIG_FILE"
    echo "# Models: $MODELS_COUNT"
    echo "# Stage: Inference"
    echo "# Run purpose: $RUN_PURPOSE"
    if [ "$NSYS_PROFILING" = true ]; then
        echo "Threads,Duration(s),System,Timestamp,Models_Generated,GPU_Util_Avg_%,Memory_Peak_MB,NSYS_Profile"
    else
        echo "Threads,Duration(s),System,Timestamp,Models_Generated,GPU_Util_Avg_%,Memory_Peak_MB"
    fi
} > "$RESULTS_CSV"

# Run benchmarks
for N in $THREAD_COUNTS; do
    log_info ""
    log_info "===== Testing inference with $N threads ====="
    
    RUN_NAME="${JSON_BASENAME_NO_EXT}_${N}threads_inf"
    RUN_DIR="$RESULT_DIR/$RUN_NAME"
    mkdir -p "$RUN_DIR"
    
    # Generate experiment ID
    EXPERIMENT_ID="${SYSTEM_NAME}_inference_${JSON_BASENAME_NO_EXT}_${N}threads_${TIMESTAMP}"
    
    # Start GPU monitoring if enabled
    GPU_LOG=""
    GPU_MONITOR_PID=""
    if [ "$USE_GPU" = true ]; then
        GPU_LOG="$RUN_DIR/gpu_monitoring.csv"
        start_gpu_monitoring "$GPU_LOG"
        GPU_MONITOR_PID=$MONITOR_PID
    fi
    
    # Record start time
    start_time=$(date +%s.%N)
    run_timestamp=$(date +%Y-%m-%d_%H:%M:%S)
    
    # Prepare AlphaFold command
    AF_CMD="python run_alphafold.py \
        --json_path=/input/$JSON_FILENAME \
        --output_dir=/output \
        --db_dir=/db \
        --run_data_pipeline=false \
        --run_inference=true"
    
    if [ "$USE_GPU" = false ]; then
        AF_CMD="$AF_CMD --use_gpu=false"
    fi
    
    # Build Docker command using shared library
    INPUT_DIR=$(dirname "$FULL_INPUT_PATH")
    DOCKER_CMD=$(build_docker_command \
        "$ACTUAL_DOCKER_IMAGE" \
        "$N" \
        "$USE_GPU" \
        "$UNIFIED_MEMORY" \
        "$INPUT_DIR" \
        "$RUN_DIR" \
        "$DB_DIR" \
        "$MODEL_DIR")
    
    # Execute with or without NSYS/perf profiling
    if [ "$NSYS_PROFILING" = true ]; then
        log_info "Running with NSYS profiling..."
        
        NSYS_CMD="nsys profile --trace=cuda,nvtx,osrt --output=/output/nsys_profile_${N}threads"
        
        $DOCKER_CMD bash -c "$NSYS_CMD $AF_CMD 2>&1 | tee /output/alphafold.log"
        EXIT_CODE=$?
        
        NSYS_PROFILE="nsys_profile_${N}threads.nsys-rep"
    elif [ "$PROFILING_ENABLED" = true ] && [ "$PROFILING_TOOL" = "perf_stat" ]; then
        log_info "Running with legacy perf stat profiling inside container..."
        
        # Create legacy-style perf script
        PERF_SCRIPT="$RUN_DIR/run_perf.sh"
        log_info "Creating legacy perf script: $PERF_SCRIPT"
        
        cat > "$PERF_SCRIPT" << EOF
#!/bin/bash
set -e

echo "=== Legacy Perf Stat Profiling (Inference) ==="

# Find perf binary
PERF_BIN="/usr/lib/linux-tools-5.15.0-141/perf"
if [ ! -x "\$PERF_BIN" ]; then
    PERF_BIN=\$(find /usr/lib/linux-tools* -name "perf" -type f -executable 2>/dev/null | head -1)
fi
if [ -z "\$PERF_BIN" ] || [ ! -x "\$PERF_BIN" ]; then
    PERF_BIN="perf"
fi

echo "Using perf binary: \$PERF_BIN"

# Setup kernel permissions
if [ -w /proc/sys/kernel/perf_event_paranoid ]; then
    echo -1 > /proc/sys/kernel/perf_event_paranoid 2>/dev/null || true
    echo 0 > /proc/sys/kernel/kptr_restrict 2>/dev/null || true
fi

# Perf events
PERF_EVENTS="cycles,instructions,cache-references,cache-misses,L1-dcache-loads,LLC-loads,branch-misses"

echo "Running: \$PERF_BIN stat -e \$PERF_EVENTS -x , -o /output/perf_inference_stat.csv $AF_CMD"
\$PERF_BIN stat -e \$PERF_EVENTS -x , -o /output/perf_inference_stat.csv $AF_CMD 2>&1 | tee /output/inference_with_perf.log

if [ -f /output/perf_inference_stat.csv ]; then
    echo "✓ Perf stat file created successfully"
    head -5 /output/perf_inference_stat.csv || true
else
    echo "✗ ERROR: Perf stat file was not created!"
fi
EOF
        
        chmod +x "$PERF_SCRIPT"
        $DOCKER_CMD bash /output/run_perf.sh
        EXIT_CODE=$?
        
        NSYS_PROFILE="N/A"
    elif [ "$PROFILING_ENABLED" = true ] && [ "$PROFILING_TOOL" = "perf_record" ]; then
        log_info "Running with legacy perf record profiling inside container..."
        
        # Create legacy-style perf script
        PERF_SCRIPT="$RUN_DIR/run_perf.sh"
        log_info "Creating legacy perf script: $PERF_SCRIPT"
        
        cat > "$PERF_SCRIPT" << EOF
#!/bin/bash
set -e

echo "=== Legacy Perf Record Profiling (Inference) ==="

# Find perf binary
PERF_BIN="/usr/lib/linux-tools-5.15.0-141/perf"
if [ ! -x "\$PERF_BIN" ]; then
    PERF_BIN=\$(find /usr/lib/linux-tools* -name "perf" -type f -executable 2>/dev/null | head -1)
fi
if [ -z "\$PERF_BIN" ] || [ ! -x "\$PERF_BIN" ]; then
    PERF_BIN="perf"
fi

echo "Using perf binary: \$PERF_BIN"

# Setup kernel permissions
if [ -w /proc/sys/kernel/perf_event_paranoid ]; then
    echo -1 > /proc/sys/kernel/perf_event_paranoid 2>/dev/null || true
    echo 0 > /proc/sys/kernel/kptr_restrict 2>/dev/null || true
fi

# Record for limited time for inference (inference is usually faster than MSA)
echo "Running: timeout 120s \$PERF_BIN record -F 99 --timestamp -o /output/perf_inference_record.data $AF_CMD"
timeout 120s \$PERF_BIN record -F 99 --timestamp -o /output/perf_inference_record.data $AF_CMD 2>&1 | tee /output/inference_with_perf.log || true

# Generate report if record was successful
if [ -f /output/perf_inference_record.data ]; then
    echo "✓ Perf record file created, generating report..."
    \$PERF_BIN report -i /output/perf_inference_record.data --stdio --sort dso,symbol --percent-limit 1.0 > /output/perf_inference_detailed.txt 2>/dev/null || echo "Report generation failed"
else
    echo "✗ ERROR: Perf record file was not created!"
fi
EOF
        
        chmod +x "$PERF_SCRIPT"
        $DOCKER_CMD bash /output/run_perf.sh
        EXIT_CODE=$?
        
        NSYS_PROFILE="N/A"
    else
        log_info "Running performance timing only..."
        
        $DOCKER_CMD bash -c "$AF_CMD 2>&1 | tee /output/alphafold.log"
        EXIT_CODE=$?
        
        NSYS_PROFILE="N/A"
    fi
    
    # Record end time
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc)
    
    # Stop GPU monitoring
    if [ -n "$GPU_MONITOR_PID" ]; then
        stop_monitoring $GPU_MONITOR_PID
    fi
    
    # Process results
    STATUS="SUCCESS"
    if [ $EXIT_CODE -eq 0 ]; then
        log_info "✓ Inference completed in ${duration}s"
        
        # Validate results using shared library
        if validate_inference_output "$RUN_DIR"; then
            MODELS_GENERATED=1
        else
            MODELS_GENERATED=0
            STATUS="FAILED"
        fi
        
        # Analyze GPU usage using shared library
        if [ -f "$GPU_LOG" ]; then
            GPU_STATS=$(analyze_gpu_log "$GPU_LOG")
            GPU_UTIL_AVG=$(echo "$GPU_STATS" | cut -d',' -f1)
            MEMORY_PEAK=$(echo "$GPU_STATS" | cut -d',' -f2)
        else
            GPU_UTIL_AVG="N/A"
            MEMORY_PEAK="N/A"
        fi
        
        # Build CSV line for local results
        CSV_LINE="$N,$duration,$SYSTEM_NAME,$run_timestamp,$MODELS_GENERATED,$GPU_UTIL_AVG,$MEMORY_PEAK"
        
        if [ "$NSYS_PROFILING" = true ]; then
            CSV_LINE="$CSV_LINE,$NSYS_PROFILE"
        fi
        
        echo "$CSV_LINE" >> "$RESULTS_CSV"
        
    else
        log_error "✗ Inference failed with exit code $EXIT_CODE"
        STATUS="FAILED"
        CSV_LINE="$N,FAILED,$SYSTEM_NAME,$run_timestamp,0,N/A,N/A"
        if [ "$NSYS_PROFILING" = true ]; then
            CSV_LINE="$CSV_LINE,FAILED"
        fi
        echo "$CSV_LINE" >> "$RESULTS_CSV"
    fi
    
    # Update master CSV
    update_master_csv "$MASTER_CSV" \
        "$EXPERIMENT_ID" \
        "$SYSTEM_NAME" \
        "$run_timestamp" \
        "$JSON_FILE" \
        "inference" \
        "$N" \
        "$duration" \
        "$STATUS" \
        "$RUN_PURPOSE" \
        "$(calculate_config_hash "$CONFIG_FILE")" \
        "$PROFILING_TOOL" \
        "{\"models_count\": $MODELS_COUNT, \"gpu\": $USE_GPU}"
    
    # Update profiling metadata if applicable
    if [ "$RUN_PURPOSE" = "profiling" ] && [ "$STATUS" = "SUCCESS" ]; then
        update_profiling_metadata "$PROFILING_CSV" \
            "$EXPERIMENT_ID" \
            "$SYSTEM_NAME" \
            "$run_timestamp" \
            "$JSON_FILE" \
            "inference" \
            "$N" \
            "$PROFILING_TOOL" \
            "$STATUS" \
            "$RUN_DIR"
        
        # Handle NSYS output file
        if [ "$NSYS_PROFILING" = true ] && [ -f "$RUN_DIR/$NSYS_PROFILE" ]; then
            handle_nsys_output "$RUN_DIR/$NSYS_PROFILE" \
                "$SYSTEM_NAME" \
                "$JSON_BASENAME_NO_EXT" \
                "$N" \
                "$STATUS"
        fi
    fi
    
    # Exit on failure
    if [ "$STATUS" = "FAILED" ]; then
        log_error "Exiting due to inference failure."
        exit 1
    fi
done

# Generate analysis report
ANALYSIS_FILE="$RESULT_DIR/inference_analysis.txt"
generate_inference_analysis "$ANALYSIS_FILE" \
    "$SYSTEM_NAME" \
    "$SYSTEM_TYPE" \
    "$CONFIG_FILE" \
    "$JSON_FILE" \
    "$MODELS_COUNT" \
    "$USE_GPU" \
    "$RESULTS_CSV" \
    "$RESULT_DIR" \
    "$NSYS_PROFILING"

log_info ""
log_info "=== Inference Benchmark Complete ==="
log_info "Results directory: $RESULT_DIR"
log_info "Analysis: $ANALYSIS_FILE"
log_info "CSV: $RESULTS_CSV"
log_info "Master CSV updated: $MASTER_CSV"
if [ "$RUN_PURPOSE" = "profiling" ]; then
    log_info "Profiling metadata updated: $PROFILING_CSV"
fi
log_info ""
cat "$ANALYSIS_FILE"

# NSYS post-processing
if [ "$NSYS_PROFILING" = true ]; then
    log_info ""
    log_info "=== NSYS Post-processing ==="
    
    for profile in $(find "$RESULT_DIR" -name "*.nsys-rep"); do
        log_info "Processing: $(basename $profile)"
        profile_dir=$(dirname "$profile")
        
        # Generate summary statistics using Docker container
        log_info "Generating NSYS statistics..."
        docker run --rm \
            -v "$(realpath $profile_dir):/profiles" \
            "$ACTUAL_DOCKER_IMAGE" \
            bash -c "
                nsys stats --report gputrace /profiles/$(basename $profile) --output text > /profiles/nsys_gpu_summary.txt 2>/dev/null || true
                nsys stats --report cudaapisum /profiles/$(basename $profile) --output text > /profiles/nsys_cuda_summary.txt 2>/dev/null || true
            "
        
        log_info "  GPU trace: $profile_dir/nsys_gpu_summary.txt"
        log_info "  CUDA API: $profile_dir/nsys_cuda_summary.txt"
    done
    
    log_info ""
    log_info "Open profiles with: nsys-ui <profile_file>"
fi

log_info "Benchmark inference completed successfully"