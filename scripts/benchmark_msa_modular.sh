#!/bin/bash
# benchmark_msa_refactored.sh - Refactored MSA benchmark using shared libraries

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared libraries
source "$SCRIPT_DIR/../lib/config.sh"
source "$SCRIPT_DIR/../lib/logging.sh"
source "$SCRIPT_DIR/../lib/validation.sh"
source "$SCRIPT_DIR/../lib/docker_utils.sh"
source "$SCRIPT_DIR/../lib/monitoring.sh"
source "$SCRIPT_DIR/../lib/result_parser.sh"

# Script-specific variables
CONFIG_FILE=""
JSON_FILE=""
OVERRIDE_THREADS=""
FORCE_RUN=false

# Usage function
show_usage() {
    echo "Usage: $0 -c <config_file> [OPTIONS] <json_file>"
    echo ""
    echo "Required:"
    echo "  -c <config_file>  Configuration file (.config)"
    echo "  <json_file>       Input JSON file (in input_msa/ directory)"
    echo ""
    echo "Options:"
    echo "  -t <threads>      Override thread counts (e.g., '4 8 16')"
    echo "  -n, --no-monitor  Disable system monitoring"
    echo "  --peak            Enable peak memory monitoring"
    echo "  --force           Force run even if other processes exist"
    echo "  -h, --help        Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 -c myenv.config promo.json"
    echo "  $0 -c myenv.config -t '2 4' promo.json"
    echo "  $0 -c myenv.config --peak promo.json"
}

# Parse command line arguments
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
        -n|--no-monitor)
            SYSTEM_MONITOR=false
            shift
            ;;
        --peak)
            MEMORY_MONITOR=true
            shift
            ;;
        --force)
            FORCE_RUN=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            # Positional argument (JSON file)
            if [ -z "$JSON_FILE" ]; then
                JSON_FILE="$1"
            else
                echo "Error: Too many arguments"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Check required arguments
if [ -z "$CONFIG_FILE" ]; then
    echo "Error: Config file is required (-c option)"
    show_usage
    exit 1
fi

if [ -z "$JSON_FILE" ]; then
    echo "Error: JSON file is required"
    show_usage
    exit 1
fi

# Load and validate configuration
if ! load_and_validate_config "$CONFIG_FILE"; then
    exit 1
fi

# Setup paths
JSON_BASENAME=$(basename "$JSON_FILE" .json)
JSON_FILENAME=$(basename "$JSON_FILE")
INPUT_DIR="${INPUT_DIR:-input_msa}"
OUTPUT_BASE="${OUTPUT_BASE:-output_msa}"

# Create directories
mkdir -p "$INPUT_DIR"
mkdir -p "$OUTPUT_BASE"

# Initialize logging
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_DIR="${OUTPUT_BASE}/${SYSTEM_NAME}_${TIMESTAMP}"
mkdir -p "$RESULT_DIR"
init_logging "$RESULT_DIR" "benchmark_msa"

log_section "AlphaFold MSA Benchmark Starting"
log_kv "System" "$SYSTEM_NAME ($SYSTEM_TYPE)"
log_kv "Config" "$CONFIG_FILE"
log_kv "Input" "$JSON_FILE"
log_kv "Threads" "$THREAD_COUNTS"

# Check prerequisites
if ! check_prerequisites; then
    log_error "Prerequisites check failed"
    exit 1
fi

# Check for running processes
if ! check_running_processes "$FORCE_RUN"; then
    exit 1
fi

# Validate input file
if ! check_input_file "$INPUT_DIR/$JSON_FILE"; then
    log_error "Input file validation failed"
    exit 1
fi

# Create CSV file for results
RESULTS_CSV="$RESULT_DIR/results_${SYSTEM_NAME}_${JSON_BASENAME}.csv"
MASTER_CSV="${SCRIPT_DIR}/../results/master_results.csv"
create_csv_header "$RESULTS_CSV" "msa" "sequences_found,peak_memory_mb"

# Initialize master CSV if needed
init_master_csv "$MASTER_CSV"

# Start system monitoring
if [ "$SYSTEM_MONITOR" = true ]; then
    start_system_monitoring "$RESULT_DIR/logs"
fi

# Start GPU monitoring if applicable
if [ "$GPU_MONITOR" = true ] && [ "$SYSTEM_TYPE" = "gpu" ]; then
    start_gpu_monitoring "$RESULT_DIR/logs"
fi

# Run benchmarks for each thread count
for N in $THREAD_COUNTS; do
    log_section "Testing with $N threads"
    
    RUN_NAME="${JSON_BASENAME}_${N}threads"
    RUN_DIR="$(realpath "$RESULT_DIR/$RUN_NAME")"
    mkdir -p "$RUN_DIR"
    
    # Start memory monitoring if enabled
    if [ "$MEMORY_MONITOR" = true ]; then
        start_memory_monitoring "hmmer" "$RUN_DIR/memory.log"
    fi
    
    # Record start time
    start_time=$(date +%s.%N)
    run_timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Build and execute Docker command
    docker_cmd=$(build_msa_docker_command \
        "$(realpath "$INPUT_DIR/$JSON_FILE")" \
        "$RUN_DIR" \
        "$N" \
        "$DB_DIR" \
        "$DOCKER_IMAGE" \
        "$SYSTEM_TYPE")
    
    log_command "$docker_cmd"
    
    # Execute with logging (with perf inside container if enabled)
    if [ "$PROFILING_ENABLED" = true ]; then
        # Create legacy-style perf script in output directory
        PERF_SCRIPT="$RUN_DIR/run_perf.sh"
        log_info "Creating legacy perf script: $PERF_SCRIPT"
        
        cat > "$PERF_SCRIPT" << EOF
#!/bin/bash
set -e

echo "=== Legacy Perf Profiling Inside Container ==="
echo "Tool: $PROFILING_TOOL"
echo "Thread count: $N"

# Find perf binary - use direct path to avoid wrapper issues
PERF_BIN="/usr/lib/linux-tools-5.15.0-141/perf"

# Fallback if specific version not found
if [ ! -x "\$PERF_BIN" ]; then
    PERF_BIN=\$(find /usr/lib/linux-tools* -name "perf" -type f -executable 2>/dev/null | head -1)
fi

if [ -z "\$PERF_BIN" ] || [ ! -x "\$PERF_BIN" ]; then
    echo "Warning: perf binary not found in container, trying system perf"
    PERF_BIN="perf"
fi

echo "Using perf binary: \$PERF_BIN"
echo "Perf version: \$(\$PERF_BIN --version 2>&1 | head -1 || echo 'version check failed')"

# Setup kernel permissions for perf
if [ -w /proc/sys/kernel/perf_event_paranoid ]; then
    echo "Setting kernel parameters for perf..."
    echo -1 > /proc/sys/kernel/perf_event_paranoid 2>/dev/null || true
    echo 0 > /proc/sys/kernel/kptr_restrict 2>/dev/null || true
    echo "perf_event_paranoid: \$(cat /proc/sys/kernel/perf_event_paranoid 2>/dev/null || echo 'cannot read')"
else
    echo "Warning: Cannot write to kernel parameters (not privileged?)"
fi

# Perf events to monitor
PERF_EVENTS="cycles,instructions,cache-references,cache-misses"

# AlphaFold command
AF_CMD="python run_alphafold.py \\
    --json_path=/input/$(basename "$JSON_FILE") \\
    --output_dir=/output \\
    --db_dir=/db \\
    --run_data_pipeline=true \\
    --run_inference=false \\
    --jackhmmer_n_cpu=$N"

echo "AlphaFold command: \$AF_CMD"

case "$PROFILING_TOOL" in
    perf_stat)
        echo "Running perf stat with events: \$PERF_EVENTS"
        echo "Output file: /output/perf_stat.csv"
        \$PERF_BIN stat -e \$PERF_EVENTS -x , -o /output/perf_stat.csv \\
            \$AF_CMD 2>&1 | tee /output/msa_with_perf.log
        
        # Check if stat file was created
        if [ -f /output/perf_stat.csv ]; then
            echo "✓ Perf stat file created successfully"
            echo "Content preview:"
            head -10 /output/perf_stat.csv || true
        else
            echo "✗ ERROR: Perf stat file was not created!"
        fi
        ;;
    perf_record)
        echo "Running perf record with events: \$PERF_EVENTS"
        echo "Output file: /output/perf_msa_record.data"
        \$PERF_BIN record -e \$PERF_EVENTS -F 99 --timestamp -o /output/perf_msa_record.data \\
            \$AF_CMD 2>&1 | tee /output/msa_with_perf.log
        
        # Generate detailed report if record was successful
        if [ -f /output/perf_msa_record.data ]; then
            echo "✓ Perf record file created, generating report..."
            \$PERF_BIN report \\
                -i /output/perf_msa_record.data \\
                --stdio \\
                --sort dso,symbol \\
                --percent-limit 1.0 \\
                > /output/perf_msa_detailed.txt 2>/dev/null || echo "Report generation failed"
        else
            echo "✗ ERROR: Perf record file was not created!"
        fi
        ;;
    *)
        echo "Running without profiling..."
        \$AF_CMD 2>&1 | tee /output/msa_no_perf.log
        ;;
esac

echo "=== Profiling Complete ==="
EOF
        
        chmod +x "$PERF_SCRIPT"
        log_info "Executing Docker with legacy perf script..."
        
        # Execute with perf script inside container
        if $docker_cmd bash /output/run_perf.sh 2>&1 | tee "$RUN_DIR/alphafold.log"; then
            EXIT_CODE=0
        else
            EXIT_CODE=$?
        fi
    else
        # Normal execution without profiling
        if execute_docker_command "$docker_cmd" "MSA generation" 2>&1 | tee "$RUN_DIR/alphafold.log"; then
            EXIT_CODE=0
        else
            EXIT_CODE=$?
        fi
    fi
    
    # Record end time
    end_time=$(date +%s.%N)
    duration=$(extract_timing "$start_time" "$end_time")
    
    log_execution_time "$start_time" "$end_time" "MSA with $N threads"
    
    # Stop memory monitoring
    if [ "$MEMORY_MONITOR" = true ]; then
        stop_monitoring
        peak_memory_kb=$(get_peak_memory "$RUN_DIR/memory.log")
        peak_memory_mb=$((peak_memory_kb / 1024))
        log_kv "Peak Memory" "${peak_memory_mb} MB"
    else
        peak_memory_mb=0
    fi
    
    # Parse results
    eval "$(parse_msa_results "$RUN_DIR" "$RUN_DIR/alphafold.log")"
    
    # Generate experiment ID
    experiment_id=$(generate_experiment_id "$SYSTEM_NAME" "$JSON_BASENAME" "$run_timestamp")
    
    # Build CSV line
    csv_line=$(build_csv_line \
        "$experiment_id" \
        "$SYSTEM_NAME" \
        "$run_timestamp" \
        "$JSON_FILE" \
        "msa" \
        "$N" \
        "$duration" \
        "$status" \
        "$(determine_run_purpose)" \
        "$sequences_found" \
        "$peak_memory_mb")
    
    echo "$csv_line" >> "$RESULTS_CSV"
    
    # Update master CSV
    update_master_csv "$MASTER_CSV" \
        "$experiment_id" \
        "$SYSTEM_NAME" \
        "$run_timestamp" \
        "$JSON_FILE" \
        "msa" \
        "$N" \
        "$duration" \
        "$status" \
        "$(determine_run_purpose)" \
        "$sequences_found" \
        "$peak_memory_mb" \
        "$(calculate_config_hash)" \
        "" \
        "{\"test_run\":\"functionality_validation\"}"
    
    # Validate results
    if ! validate_results "$RUN_DIR" "msa"; then
        log_warn "Result validation failed for $N threads"
    fi
    
    # Log resource usage
    log_resource_usage "MSA with $N threads"
done

# Stop all monitoring
stop_monitoring

# Generate summary
SUMMARY_FILE="$RESULT_DIR/summary.txt"
generate_summary "$RESULT_DIR" "msa" "$RESULTS_CSV" "$SUMMARY_FILE"

# Create monitoring summary if enabled
if [ "$SYSTEM_MONITOR" = true ]; then
    create_monitoring_summary "$RESULT_DIR/logs" "$RESULT_DIR/monitoring_summary.txt"
fi

# Log completion
log_section "Benchmark Complete"
log_kv "Results directory" "$RESULT_DIR"
log_kv "Summary" "$SUMMARY_FILE"
log_kv "CSV" "$RESULTS_CSV"

# Display summary
echo ""
cat "$SUMMARY_FILE"

# Create log summary
create_log_summary "$RESULT_DIR/log_summary.txt"

# Find and display best result
best_result=$(find_best_result "$RESULTS_CSV")
if [ -n "$best_result" ]; then
    log_info "Best result: $best_result"
fi