#!/bin/bash

# Centralized logging utilities for AlphaFold benchmarking

# Log levels (check if already defined to avoid readonly errors)
if [ -z "$LOG_LEVEL_ERROR" ]; then
    readonly LOG_LEVEL_ERROR=1
    readonly LOG_LEVEL_WARN=2
    readonly LOG_LEVEL_INFO=3
    readonly LOG_LEVEL_DEBUG=4
fi

# Default log level
LOG_LEVEL=${LOG_LEVEL:-$LOG_LEVEL_INFO}

# Colors for terminal output (check if already defined to avoid readonly errors)
if [ -z "$COLOR_RED" ]; then
    readonly COLOR_RED='\033[0;31m'
    readonly COLOR_YELLOW='\033[0;33m'
    readonly COLOR_GREEN='\033[0;32m'
    readonly COLOR_BLUE='\033[0;34m'
    readonly COLOR_RESET='\033[0m'
fi

# Global log file
LOG_FILE=""

# Initialize logging
init_logging() {
    local log_dir=$1
    local log_name=${2:-"benchmark"}
    
    # Create log directory
    mkdir -p "$log_dir"
    
    # Set log file with timestamp
    LOG_FILE="$log_dir/${log_name}_$(date +%Y%m%d_%H%M%S).log"
    
    # Set log level from environment or config
    if [ "$DEBUG_MODE" = true ]; then
        LOG_LEVEL=$LOG_LEVEL_DEBUG
    fi
    
    # Write initial log entry
    log_info "=== AlphaFold Benchmark Logging Started ==="
    log_info "System: $SYSTEM_NAME"
    log_info "Timestamp: $(date)"
    log_info "Log Level: $(get_log_level_name $LOG_LEVEL)"
}

# Get log level name
get_log_level_name() {
    local level=$1
    case $level in
        $LOG_LEVEL_ERROR) echo "ERROR" ;;
        $LOG_LEVEL_WARN)  echo "WARN" ;;
        $LOG_LEVEL_INFO)  echo "INFO" ;;
        $LOG_LEVEL_DEBUG) echo "DEBUG" ;;
        *) echo "UNKNOWN" ;;
    esac
}

# Core logging function
log_message() {
    local level=$1
    local message=$2
    local color=$3
    
    # Check if we should log this level
    if [ $level -gt $LOG_LEVEL ]; then
        return
    fi
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local level_name=$(get_log_level_name $level)
    local formatted_message="[$timestamp] [$level_name] $message"
    
    # Log to file if set
    if [ -n "$LOG_FILE" ]; then
        echo "$formatted_message" >> "$LOG_FILE"
    fi
    
    # Log to terminal with color if interactive
    if [ -t 1 ]; then
        echo -e "${color}${formatted_message}${COLOR_RESET}"
    else
        echo "$formatted_message"
    fi
}

# Log error message
log_error() {
    log_message $LOG_LEVEL_ERROR "$1" "$COLOR_RED" >&2
}

# Log warning message
log_warn() {
    log_message $LOG_LEVEL_WARN "$1" "$COLOR_YELLOW"
}

# Log info message
log_info() {
    log_message $LOG_LEVEL_INFO "$1" "$COLOR_GREEN"
}

# Log debug message
log_debug() {
    log_message $LOG_LEVEL_DEBUG "$1" "$COLOR_BLUE"
}

# Log command execution
log_command() {
    local command=$1
    log_debug "Executing: $command"
}

# Log with prefix (for subsystems)
log_with_prefix() {
    local prefix=$1
    local level=$2
    local message=$3
    
    case $level in
        error) log_error "[$prefix] $message" ;;
        warn)  log_warn "[$prefix] $message" ;;
        info)  log_info "[$prefix] $message" ;;
        debug) log_debug "[$prefix] $message" ;;
    esac
}

# Log section separator
log_section() {
    local title=$1
    log_info "=== $title ==="
}

# Log key-value pair
log_kv() {
    local key=$1
    local value=$2
    log_info "  $key: $value"
}

# Log array contents
log_array() {
    local array_name=$1
    local array=("${@:2}")
    
    log_debug "$array_name (${#array[@]} items):"
    for item in "${array[@]}"; do
        log_debug "  - $item"
    done
}

# Log file contents (with size limit)
log_file_contents() {
    local file=$1
    local max_lines=${2:-50}
    
    if [ ! -f "$file" ]; then
        log_error "File not found: $file"
        return 1
    fi
    
    log_debug "Contents of $file (max $max_lines lines):"
    head -n "$max_lines" "$file" | while IFS= read -r line; do
        log_debug "  $line"
    done
}

# Log execution time
log_execution_time() {
    local start_time=$1
    local end_time=$2
    local description=$3
    
    local duration=$(echo "$end_time - $start_time" | bc)
    log_info "Execution time for $description: ${duration}s"
}

# Log resource usage
log_resource_usage() {
    local description=$1
    
    log_debug "Resource usage for $description:"
    
    # Memory usage
    local mem_usage=$(free -m | awk 'NR==2{printf "%.1f%%", $3/$2*100}')
    log_debug "  Memory: $mem_usage"
    
    # CPU load
    local cpu_load=$(uptime | awk -F'load average:' '{print $2}')
    log_debug "  Load average:$cpu_load"
    
    # Disk usage
    local disk_usage=$(df -h . | awk 'NR==2{print $5}')
    log_debug "  Disk usage: $disk_usage"
}

# Log benchmark progress
log_progress() {
    local current=$1
    local total=$2
    local description=$3
    
    local percent=$((current * 100 / total))
    log_info "Progress: $description [$current/$total] ${percent}%"
}

# Create log summary
create_log_summary() {
    local summary_file=$1
    
    if [ ! -f "$LOG_FILE" ]; then
        return 1
    fi
    
    {
        echo "=== Log Summary ==="
        echo "Log file: $LOG_FILE"
        echo "Total lines: $(wc -l < "$LOG_FILE")"
        echo ""
        
        echo "Message counts:"
        echo "  Errors: $(grep -c "\[ERROR\]" "$LOG_FILE")"
        echo "  Warnings: $(grep -c "\[WARN\]" "$LOG_FILE")"
        echo "  Info: $(grep -c "\[INFO\]" "$LOG_FILE")"
        echo "  Debug: $(grep -c "\[DEBUG\]" "$LOG_FILE")"
        echo ""
        
        # Extract errors and warnings
        local error_count=$(grep -c "\[ERROR\]" "$LOG_FILE")
        if [ $error_count -gt 0 ]; then
            echo "Recent errors:"
            grep "\[ERROR\]" "$LOG_FILE" | tail -5 | sed 's/^/  /'
            echo ""
        fi
        
        local warn_count=$(grep -c "\[WARN\]" "$LOG_FILE")
        if [ $warn_count -gt 0 ]; then
            echo "Recent warnings:"
            grep "\[WARN\]" "$LOG_FILE" | tail -5 | sed 's/^/  /'
        fi
    } > "$summary_file"
}

# Rotate logs if they get too large
rotate_log_if_needed() {
    local max_size=${1:-104857600}  # 100MB default
    
    if [ -z "$LOG_FILE" ] || [ ! -f "$LOG_FILE" ]; then
        return
    fi
    
    local file_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null)
    
    if [ "$file_size" -gt "$max_size" ]; then
        local rotated_log="${LOG_FILE}.$(date +%Y%m%d_%H%M%S)"
        mv "$LOG_FILE" "$rotated_log"
        gzip "$rotated_log" &
        
        log_info "Log rotated to: ${rotated_log}.gz"
        
        # Start new log
        log_info "=== Log Rotated - Continuing ==="
    fi
}

# Cleanup old logs
cleanup_old_logs() {
    local log_dir=$1
    local days_to_keep=${2:-7}
    
    log_info "Cleaning up logs older than $days_to_keep days in $log_dir"
    
    find "$log_dir" -name "*.log" -type f -mtime +$days_to_keep -delete
    find "$log_dir" -name "*.log.gz" -type f -mtime +$days_to_keep -delete
}

# Export logging functions for use in subshells
export -f log_error log_warn log_info log_debug