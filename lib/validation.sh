#!/bin/bash

# Input validation and prerequisites checking for AlphaFold benchmarking

# Source logging utilities
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/logging.sh" 2>/dev/null || true

# Check if a command exists
check_command() {
    local cmd=$1
    local description=$2
    
    if command -v "$cmd" &> /dev/null; then
        log_debug "✓ $description: $cmd found"
        return 0
    else
        log_error "✗ $description: $cmd not found"
        return 1
    fi
}

# Check Docker installation and daemon
check_docker() {
    log_info "Checking Docker installation..."
    
    # Check if Docker command exists
    if ! check_command "docker" "Docker command"; then
        log_error "Docker is not installed. Please install Docker first."
        log_error "Visit: https://docs.docker.com/get-docker/"
        return 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running or not accessible"
        log_error "Try: sudo systemctl start docker"
        return 1
    fi
    
    # Check Docker version
    local docker_version=$(docker --version | awk '{print $3}' | tr -d ',')
    log_info "Docker version: $docker_version"
    
    return 0
}

# Check if Docker image exists
check_docker_image() {
    local image=$1
    
    log_info "Checking Docker image: $image"
    
    if docker image inspect "$image" &> /dev/null; then
        log_info "✓ Docker image found: $image"
        
        # Get image details
        local image_size=$(docker image inspect "$image" --format='{{.Size}}' | awk '{printf "%.2f GB", $1/1024/1024/1024}')
        local image_created=$(docker image inspect "$image" --format='{{.Created}}')
        log_debug "  Size: $image_size"
        log_debug "  Created: $image_created"
        
        return 0
    else
        log_error "✗ Docker image not found: $image"
        log_error "Please pull the image with: docker pull $image"
        return 1
    fi
}

# Check input file
check_input_file() {
    local file=$1
    
    log_info "Checking input file: $file"
    
    if [ ! -f "$file" ]; then
        log_error "Input file not found: $file"
        return 1
    fi
    
    # Check if readable
    if [ ! -r "$file" ]; then
        log_error "Input file not readable: $file"
        return 1
    fi
    
    # Check file extension
    local extension="${file##*.}"
    case "$extension" in
        json)
            # Validate JSON syntax
            if command -v jq &> /dev/null; then
                if ! jq empty "$file" 2>/dev/null; then
                    log_error "Invalid JSON file: $file"
                    return 1
                fi
                log_debug "✓ Valid JSON file"
            fi
            ;;
        fasta|fa)
            # Basic FASTA validation
            if ! grep -q "^>" "$file"; then
                log_error "Invalid FASTA file (no headers found): $file"
                return 1
            fi
            log_debug "✓ Valid FASTA file"
            ;;
        *)
            log_warn "Unknown file extension: $extension"
            ;;
    esac
    
    # Check file size
    local file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
    local file_size_mb=$((file_size / 1024 / 1024))
    log_debug "  File size: ${file_size_mb} MB"
    
    if [ $file_size -eq 0 ]; then
        log_error "Input file is empty: $file"
        return 1
    fi
    
    return 0
}

# Check directory existence and permissions
check_directory() {
    local dir=$1
    local description=$2
    local require_write=${3:-false}
    
    log_info "Checking $description: $dir"
    
    if [ ! -d "$dir" ]; then
        log_error "$description not found: $dir"
        return 1
    fi
    
    if [ ! -r "$dir" ]; then
        log_error "$description not readable: $dir"
        return 1
    fi
    
    if [ "$require_write" = true ] && [ ! -w "$dir" ]; then
        log_error "$description not writable: $dir"
        return 1
    fi
    
    log_debug "✓ $description exists and is accessible"
    return 0
}

# Check database directories
check_databases() {
    local db_dir=$1
    
    log_info "Checking AlphaFold databases..."
    
    if ! check_directory "$db_dir" "Database directory" false; then
        return 1
    fi
    
    # Check for expected database subdirectories
    local required_dbs=("uniref90" "mgnify" "bfd" "uniclust30" "pdb70")
    local missing_dbs=()
    
    for db in "${required_dbs[@]}"; do
        if [ ! -d "$db_dir/$db" ]; then
            missing_dbs+=("$db")
        else
            log_debug "✓ Found database: $db"
        fi
    done
    
    if [ ${#missing_dbs[@]} -gt 0 ]; then
        log_warn "Missing databases: ${missing_dbs[*]}"
        log_warn "Some features may not work without all databases"
    fi
    
    # Check total database size
    if command -v du &> /dev/null; then
        local db_size=$(du -sh "$db_dir" 2>/dev/null | cut -f1)
        log_info "Total database size: $db_size"
    fi
    
    return 0
}

# Check GPU availability
check_gpu() {
    if [ "$SYSTEM_TYPE" != "gpu" ]; then
        log_debug "Skipping GPU check (system type: $SYSTEM_TYPE)"
        return 0
    fi
    
    log_info "Checking GPU availability..."
    
    if ! check_command "nvidia-smi" "NVIDIA GPU management"; then
        log_error "nvidia-smi not found. NVIDIA drivers may not be installed."
        return 1
    fi
    
    # Check if GPU is accessible
    if ! nvidia-smi &> /dev/null; then
        log_error "Cannot access GPU. Check NVIDIA driver installation."
        return 1
    fi
    
    # Get GPU information
    local gpu_count=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -1)
    local gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
    local gpu_memory=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader | head -1)
    
    log_info "✓ Found $gpu_count GPU(s): $gpu_name ($gpu_memory)"
    
    # Check CUDA availability in Docker
    if docker run --rm --gpus all nvidia/cuda:11.1.1-base-ubuntu20.04 nvidia-smi &> /dev/null; then
        log_debug "✓ Docker GPU support verified"
    else
        log_error "Docker cannot access GPU. Check nvidia-docker installation."
        return 1
    fi
    
    return 0
}

# Check system resources
check_system_resources() {
    log_info "Checking system resources..."
    
    # Check CPU
    local cpu_count=$(nproc)
    local cpu_model=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
    log_info "CPU: $cpu_model ($cpu_count cores)"
    
    # Check memory
    local total_mem=$(free -g | awk '/^Mem:/{print $2}')
    local available_mem=$(free -g | awk '/^Mem:/{print $7}')
    log_info "Memory: ${available_mem}GB available / ${total_mem}GB total"
    
    # Check if we have enough memory
    local min_memory_gb=16
    if [ "$total_mem" -lt "$min_memory_gb" ]; then
        log_warn "System has less than ${min_memory_gb}GB RAM. Large proteins may fail."
    fi
    
    # Check disk space
    local disk_free=$(df -BG . | awk 'NR==2 {print $4}' | tr -d 'G')
    log_info "Disk space: ${disk_free}GB free"
    
    # Check if we have enough disk space
    local min_disk_gb=100
    if [ "$disk_free" -lt "$min_disk_gb" ]; then
        log_warn "Less than ${min_disk_gb}GB free disk space. May run out during processing."
    fi
    
    return 0
}

# Check monitoring tools
check_monitoring_tools() {
    log_info "Checking monitoring tools..."
    
    local tools_status=0
    
    # Check system monitoring tools
    if [ "$SYSTEM_MONITOR" = true ]; then
        check_command "iostat" "I/O statistics" || tools_status=1
        check_command "sar" "System activity reporter" || tools_status=1
        check_command "vmstat" "Virtual memory statistics" || tools_status=1
    fi
    
    # Check memory monitoring
    if [ "$MEMORY_MONITOR" = true ]; then
        if [ ! -f "./monitor_mem.sh" ]; then
            log_warn "Memory monitoring script not found: ./monitor_mem.sh"
            log_debug "Will create it when needed"
        fi
    fi
    
    # Check GPU monitoring
    if [ "$GPU_MONITOR" = true ] && [ "$SYSTEM_TYPE" = "gpu" ]; then
        check_command "nvidia-smi" "GPU monitoring" || tools_status=1
    fi
    
    return $tools_status
}

# Check profiling tools
check_profiling_tools() {
    if [ "$PROFILING_ENABLED" != true ]; then
        return 0
    fi
    
    log_info "Checking profiling tool: $PROFILING_TOOL"
    
    case "$PROFILING_TOOL" in
        perf_stat|perf_record)
            if ! check_command "perf" "Linux perf tools"; then
                log_error "perf not installed. Install with: sudo apt-get install linux-tools-common"
                return 1
            fi
            ;;
        nsys)
            if ! check_command "nsys" "NVIDIA Nsight Systems"; then
                log_warn "nsys not found in host. Will use version in Docker container."
            fi
            ;;
        uprof)
            if ! check_command "AMDuProfCLI" "AMD uProf"; then
                log_warn "AMD uProf not found in host. Will use version in Docker container."
            fi
            ;;
        memory_peak)
            # No special tool needed
            log_debug "Memory peak monitoring will use built-in tools"
            ;;
        *)
            log_error "Unknown profiling tool: $PROFILING_TOOL"
            return 1
            ;;
    esac
    
    return 0
}

# Main prerequisites check function
check_prerequisites() {
    log_section "Checking Prerequisites"
    
    local errors=0
    
    # Check Docker
    check_docker || ((errors++))
    
    # Check Docker image
    check_docker_image "$DOCKER_IMAGE" || ((errors++))
    
    # Check databases
    check_databases "$DB_DIR" || ((errors++))
    
    # Check GPU if needed
    if [ "$SYSTEM_TYPE" = "gpu" ]; then
        check_gpu || ((errors++))
    fi
    
    # Check system resources
    check_system_resources || ((errors++))
    
    # Check monitoring tools
    check_monitoring_tools || log_warn "Some monitoring features may not work"
    
    # Check profiling tools
    check_profiling_tools || ((errors++))
    
    if [ $errors -gt 0 ]; then
        log_error "Prerequisites check failed with $errors error(s)"
        return 1
    fi
    
    log_info "✓ All prerequisites satisfied"
    return 0
}

# Validate thread count
validate_thread_count() {
    local threads=$1
    local max_threads=$(nproc)
    
    if ! [[ "$threads" =~ ^[0-9]+$ ]]; then
        log_error "Invalid thread count: $threads (must be a number)"
        return 1
    fi
    
    if [ "$threads" -lt 1 ]; then
        log_error "Thread count must be at least 1"
        return 1
    fi
    
    if [ "$threads" -gt "$max_threads" ]; then
        log_warn "Thread count ($threads) exceeds available cores ($max_threads)"
    fi
    
    return 0
}

# Validate output directory
validate_output_directory() {
    local output_dir=$1
    
    # Create if it doesn't exist
    if [ ! -d "$output_dir" ]; then
        log_info "Creating output directory: $output_dir"
        mkdir -p "$output_dir" || {
            log_error "Failed to create output directory: $output_dir"
            return 1
        }
    fi
    
    # Check if writable
    if [ ! -w "$output_dir" ]; then
        log_error "Output directory not writable: $output_dir"
        return 1
    fi
    
    return 0
}

# Check for running AlphaFold processes
check_running_processes() {
    local force=${1:-false}
    
    # Check for running Docker containers
    local running_containers=$(docker ps --filter "ancestor=$DOCKER_IMAGE" --format "{{.ID}}" | wc -l)
    
    if [ "$running_containers" -gt 0 ]; then
        log_warn "Found $running_containers running AlphaFold container(s)"
        
        if [ "$force" != true ]; then
            log_error "Other AlphaFold processes are running. Use --force to override."
            return 1
        else
            log_warn "Continuing despite running processes (--force specified)"
        fi
    fi
    
    return 0
}

# Validate Docker setup
validate_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        return 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running or not accessible"
        return 1
    fi
    
    log_info "✓ Docker is available"
    return 0
}

# Validate Docker image
validate_docker_image() {
    local image=$1
    
    if ! docker image inspect "$image" &> /dev/null; then
        log_error "Docker image not found: $image"
        return 1
    fi
    
    log_info "✓ Docker image found: $image"
    return 0
}

# Validate input file
validate_input_file() {
    local file=$1
    
    if [ ! -f "$file" ]; then
        log_error "Input file not found: $file"
        return 1
    fi
    
    log_info "✓ Input file found: $file"
    return 0
}

# Validate model directory
validate_model_directory() {
    local model_dir=$1
    
    if [ ! -d "$model_dir" ]; then
        log_error "Model directory not found: $model_dir"
        return 1
    fi
    
    log_info "✓ Model directory found: $model_dir"
    return 0
}

# Validate GPU setup
validate_gpu_setup() {
    if ! command -v nvidia-smi &> /dev/null; then
        log_warn "nvidia-smi not found. GPU may not be available"
        log_warn "Consider using --cpu-only flag"
    else
        log_info "GPU Status:"
        nvidia-smi --query-gpu=name,memory.total,memory.used --format=csv
    fi
}