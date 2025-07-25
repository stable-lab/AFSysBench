#!/bin/bash

# System monitoring utilities for AlphaFold benchmarking

# Global array to track monitoring PIDs
declare -a MONITORING_PIDS

# Start system monitoring (CPU, I/O, memory)
start_system_monitoring() {
    local log_dir=$1
    local monitor_interval=${2:-1}  # Default 1 second interval
    
    MONITORING_PIDS=()
    
    if [ "$SYSTEM_MONITOR" != true ]; then
        return 0
    fi
    
    echo "Starting system monitoring..."
    
    # Create log directory
    mkdir -p "$log_dir"
    
    # Start iostat monitoring
    if command -v iostat &> /dev/null; then
        iostat -x "$monitor_interval" > "$log_dir/iostat.log" 2>&1 &
        MONITORING_PIDS+=($!)
        echo "  - Started iostat (PID: ${MONITORING_PIDS[-1]})"
    else
        echo "  - Warning: iostat not available"
    fi
    
    # Start sar monitoring
    if command -v sar &> /dev/null; then
        sar -u -r "$monitor_interval" > "$log_dir/sar.log" 2>&1 &
        MONITORING_PIDS+=($!)
        echo "  - Started sar (PID: ${MONITORING_PIDS[-1]})"
    else
        echo "  - Warning: sar not available"
    fi
    
    # Start vmstat monitoring
    if command -v vmstat &> /dev/null; then
        vmstat "$monitor_interval" > "$log_dir/vmstat.log" 2>&1 &
        MONITORING_PIDS+=($!)
        echo "  - Started vmstat (PID: ${MONITORING_PIDS[-1]})"
    fi
    
    # Export PIDs for later use
    export MONITORING_PIDS
}

# Start GPU monitoring
start_gpu_monitoring() {
    local log_dir=$1
    local monitor_interval=${2:-1}  # Default 1 second interval
    
    if [ "$GPU_MONITOR" != true ] || [ "$SYSTEM_TYPE" != "gpu" ]; then
        return 0
    fi
    
    echo "Starting GPU monitoring..."
    
    # Create log directory
    mkdir -p "$log_dir"
    
    # Check if nvidia-smi is available
    if command -v nvidia-smi &> /dev/null; then
        # Monitor GPU utilization and memory
        nvidia-smi --query-gpu=timestamp,gpu_name,utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu,power.draw \
                   --format=csv,noheader \
                   -l "$monitor_interval" > "$log_dir/gpu_stats.csv" 2>&1 &
        local gpu_pid=$!
        MONITORING_PIDS+=($gpu_pid)
        echo "  - Started nvidia-smi monitoring (PID: $gpu_pid)"
        
        # Also capture detailed GPU process info periodically
        (
            while kill -0 $gpu_pid 2>/dev/null; do
                nvidia-smi pmon -c 1 >> "$log_dir/gpu_processes.log" 2>&1
                sleep 10  # Less frequent for process monitoring
            done
        ) &
        MONITORING_PIDS+=($!)
    else
        echo "  - Warning: nvidia-smi not available for GPU monitoring"
    fi
}

# Start memory monitoring for specific process
start_memory_monitoring() {
    local process_pattern=$1
    local output_file=$2
    local monitor_interval=${3:-1}  # Default 1 second interval
    
    if [ "$MEMORY_MONITOR" != true ]; then
        return 0
    fi
    
    echo "Starting memory monitoring for process: $process_pattern"
    
    # Check if monitor_mem.sh exists
    local monitor_script="./monitor_mem.sh"
    if [ ! -f "$monitor_script" ]; then
        echo "  - Warning: $monitor_script not found, trying to create it..."
        create_memory_monitor_script "$monitor_script"
    fi
    
    if [ -f "$monitor_script" ]; then
        chmod +x "$monitor_script"
        "$monitor_script" "$process_pattern" "$output_file" "$monitor_interval" &
        local mem_pid=$!
        MONITORING_PIDS+=($mem_pid)
        echo "  - Started memory monitoring (PID: $mem_pid)"
    else
        echo "  - Error: Could not create memory monitoring script"
    fi
}

# Create memory monitoring script if it doesn't exist
create_memory_monitor_script() {
    local script_path=$1
    
    cat > "$script_path" << 'EOF'
#!/bin/bash
# Memory monitoring script for AlphaFold benchmarking

PROCESS_PATTERN="$1"
OUTPUT_FILE="$2"
INTERVAL="${3:-1}"

echo "timestamp,pid,vsz_kb,rss_kb,cpu_percent,command" > "$OUTPUT_FILE"

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    ps aux | grep -E "$PROCESS_PATTERN" | grep -v grep | while read -r line; do
        PID=$(echo "$line" | awk '{print $2}')
        VSZ=$(echo "$line" | awk '{print $5}')
        RSS=$(echo "$line" | awk '{print $6}')
        CPU=$(echo "$line" | awk '{print $3}')
        CMD=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}')
        echo "$TIMESTAMP,$PID,$VSZ,$RSS,$CPU,$CMD" >> "$OUTPUT_FILE"
    done
    sleep "$INTERVAL"
done
EOF
    
    chmod +x "$script_path"
}

# Stop all monitoring processes
stop_monitoring() {
    if [ ${#MONITORING_PIDS[@]} -eq 0 ]; then
        return 0
    fi
    
    echo "Stopping monitoring processes..."
    
    for pid in "${MONITORING_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            echo "  - Stopped PID: $pid"
        fi
    done
    
    # Clear the array
    MONITORING_PIDS=()
    
    # Wait a moment for processes to terminate
    sleep 1
}

# Get peak memory usage from memory log
get_peak_memory() {
    local memory_log=$1
    
    if [ ! -f "$memory_log" ]; then
        echo "0"
        return
    fi
    
    # Skip header and get maximum RSS value (in KB)
    tail -n +2 "$memory_log" | awk -F',' '{print $4}' | sort -n | tail -1
}

# Get average CPU usage from monitoring logs
get_average_cpu() {
    local sar_log=$1
    
    if [ ! -f "$sar_log" ]; then
        echo "0"
        return
    fi
    
    # Extract CPU usage percentages and calculate average
    grep -E '^[0-9]' "$sar_log" | awk '{print 100-$NF}' | \
        awk '{sum+=$1; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}'
}

# Get GPU utilization statistics
get_gpu_stats() {
    local gpu_log=$1
    
    if [ ! -f "$gpu_log" ]; then
        echo "gpu_util=0,gpu_mem=0,gpu_temp=0"
        return
    fi
    
    # Calculate averages from GPU stats
    local gpu_util=$(awk -F',' '{sum+=$3; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}' "$gpu_log")
    local gpu_mem=$(awk -F',' '{sum+=$4; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}' "$gpu_log")
    local gpu_temp=$(awk -F',' '{sum+=$7; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}' "$gpu_log")
    
    echo "gpu_util=$gpu_util,gpu_mem=$gpu_mem,gpu_temp=$gpu_temp"
}

# Monitor Docker container resource usage
monitor_docker_resources() {
    local container_pattern=$1
    local output_file=$2
    local interval=${3:-5}  # Default 5 second interval
    
    echo "timestamp,container_id,cpu_percent,mem_usage,mem_limit,mem_percent" > "$output_file"
    
    (
        while true; do
            local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
            docker stats --no-stream --format "{{.Container}},{{.CPUPerc}},{{.MemUsage}}" | \
                grep -E "$container_pattern" | \
                while IFS=',' read -r container cpu mem; do
                    # Parse memory usage (e.g., "1.5GiB / 8GiB")
                    local mem_used=$(echo "$mem" | awk '{print $1}')
                    local mem_limit=$(echo "$mem" | awk '{print $3}')
                    local mem_percent=$(echo "$mem" | awk -F'[()]' '{print $2}')
                    echo "$timestamp,$container,$cpu,$mem_used,$mem_limit,$mem_percent" >> "$output_file"
                done
            sleep "$interval"
        done
    ) &
    
    local docker_monitor_pid=$!
    MONITORING_PIDS+=($docker_monitor_pid)
    echo "Started Docker resource monitoring (PID: $docker_monitor_pid)"
}

# Create monitoring summary report
create_monitoring_summary() {
    local log_dir=$1
    local summary_file=$2
    
    echo "=== System Monitoring Summary ===" > "$summary_file"
    echo "Generated: $(date)" >> "$summary_file"
    echo "" >> "$summary_file"
    
    # CPU statistics
    if [ -f "$log_dir/sar.log" ]; then
        echo "CPU Usage:" >> "$summary_file"
        echo "  Average: $(get_average_cpu "$log_dir/sar.log")%" >> "$summary_file"
        echo "" >> "$summary_file"
    fi
    
    # Memory statistics
    if [ -f "$log_dir/memory.log" ]; then
        local peak_mem=$(get_peak_memory "$log_dir/memory.log")
        echo "Memory Usage:" >> "$summary_file"
        echo "  Peak RSS: $(echo "scale=2; $peak_mem/1024/1024" | bc) GB" >> "$summary_file"
        echo "" >> "$summary_file"
    fi
    
    # GPU statistics
    if [ -f "$log_dir/gpu_stats.csv" ]; then
        echo "GPU Statistics:" >> "$summary_file"
        eval "$(get_gpu_stats "$log_dir/gpu_stats.csv")"
        echo "  Average Utilization: ${gpu_util}%" >> "$summary_file"
        echo "  Average Memory Usage: ${gpu_mem}%" >> "$summary_file"
        echo "  Average Temperature: ${gpu_temp}°C" >> "$summary_file"
        echo "" >> "$summary_file"
    fi
    
    # I/O statistics
    if [ -f "$log_dir/iostat.log" ]; then
        echo "I/O Statistics:" >> "$summary_file"
        # Extract average read/write throughput
        local avg_read=$(grep -E '^[a-z]' "$log_dir/iostat.log" | awk '{sum+=$6; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}')
        local avg_write=$(grep -E '^[a-z]' "$log_dir/iostat.log" | awk '{sum+=$7; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}')
        echo "  Average Read: ${avg_read} KB/s" >> "$summary_file"
        echo "  Average Write: ${avg_write} KB/s" >> "$summary_file"
    fi
}

# Cleanup function to ensure monitoring stops on script exit
cleanup_monitoring() {
    if [ ${#MONITORING_PIDS[@]} -gt 0 ]; then
        echo "Cleaning up monitoring processes..."
        stop_monitoring
    fi
}

# Set up trap to cleanup on exit
trap cleanup_monitoring EXIT INT TERM

# Start GPU monitoring (simplified version for inference)
start_gpu_monitoring() {
    local output_file=$1
    
    if [ "$USE_GPU" = true ] && command -v nvidia-smi &> /dev/null; then
        log_info "Starting GPU monitoring..."
        {
            echo "# GPU Monitoring"
            echo "# Started: $(date)"
            echo "Timestamp,GPU_Util_%,Memory_Used_MB,Memory_Total_MB,Temperature_C,Power_W"
        } > "$output_file"
        
        # Monitor GPU in background
        while true; do
            TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
            GPU_STATS=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw --format=csv,noheader,nounits)
            if [ -n "$GPU_STATS" ]; then
                echo "$TIMESTAMP,$GPU_STATS" >> "$output_file"
            fi
            sleep 2
        done &
        
        MONITOR_PID=$!
        log_info "GPU monitoring started (PID: $MONITOR_PID)"
    fi
}

# Stop monitoring process
stop_monitoring() {
    local pid=$1
    
    if [ -n "$pid" ]; then
        kill $pid 2>/dev/null || true
        wait $pid 2>/dev/null || true
        log_info "Monitoring stopped"
    fi
}

# Analyze GPU log
analyze_gpu_log() {
    local gpu_log=$1
    
    if [ -f "$gpu_log" ]; then
        # Skip comment lines and header (usually first 3 lines)
        GPU_UTIL_AVG=$(tail -n +4 "$gpu_log" | cut -d',' -f2 | awk '{sum+=$1; count++} END {if(count>0) printf "%.1f", sum/count; else print "0"}')
        MEMORY_PEAK=$(tail -n +4 "$gpu_log" | cut -d',' -f3 | sort -n | tail -1)
        echo "$GPU_UTIL_AVG,$MEMORY_PEAK"
    else
        echo "N/A,N/A"
    fi
}