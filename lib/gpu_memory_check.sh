#!/bin/bash
# GPU memory checking utilities for intelligent unified memory handling

# Function to get GPU memory capacity in MB
get_gpu_memory_capacity() {
    local gpu_mem_mb=0
    
    # Try nvidia-smi first
    if command -v nvidia-smi &> /dev/null; then
        # Get total memory in MiB from nvidia-smi
        gpu_mem_mb=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
        if [ -n "$gpu_mem_mb" ]; then
            echo "$gpu_mem_mb"
            return 0
        fi
    fi
    
    # Fallback: try to get from Docker
    if command -v docker &> /dev/null; then
        gpu_mem_mb=$(docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu20.04 nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
        if [ -n "$gpu_mem_mb" ]; then
            echo "$gpu_mem_mb"
            return 0
        fi
    fi
    
    # Return 0 if unable to detect
    echo "0"
    return 1
}

# Function to estimate memory requirement based on input
estimate_memory_requirement() {
    local input_file="$1"
    local base_name=$(basename "$input_file" .json)
    
    # Known memory requirements (in MB) - could be loaded from a config file
    case "$base_name" in
        "6QNR_subset_data")
            echo "24000"  # 24GB
            ;;
        "promo_data"|"promo_data_seed1")
            echo "8000"   # 8GB
            ;;
        "2pv7_data")
            echo "4000"   # 4GB
            ;;
        "1yy9_data")
            echo "6000"   # 6GB
            ;;
        "rcsb_pdb_7rce_data")
            echo "6000"   # 6GB
            ;;
        *)
            # Default estimate based on file size
            if [ -f "$input_file" ]; then
                local file_size_mb=$(stat -c%s "$input_file" 2>/dev/null | awk '{print int($1/1048576)}')
                # Rough estimate: 1000x file size
                echo $((file_size_mb * 1000))
            else
                echo "8000"  # Default 8GB
            fi
            ;;
    esac
}

# Function to check if unified memory is needed
check_unified_memory_requirement() {
    local input_file="$1"
    local safety_factor="${2:-1.2}"  # 20% safety margin by default
    
    # Get GPU memory capacity
    local gpu_mem_mb=$(get_gpu_memory_capacity)
    if [ "$gpu_mem_mb" -eq 0 ]; then
        log_warning "Unable to detect GPU memory, assuming unified memory not needed"
        echo "false"
        return
    fi
    
    # Estimate memory requirement
    local required_mem_mb=$(estimate_memory_requirement "$input_file")
    local required_with_safety=$(awk "BEGIN {print int($required_mem_mb * $safety_factor)}")
    
    log_info "GPU Memory: ${gpu_mem_mb}MB, Required: ${required_mem_mb}MB (with safety: ${required_with_safety}MB)"
    
    # Check if unified memory is needed
    if [ "$required_with_safety" -gt "$gpu_mem_mb" ]; then
        log_info "Unified memory REQUIRED: ${required_with_safety}MB > ${gpu_mem_mb}MB GPU memory"
        echo "true"
    else
        log_info "Unified memory NOT needed: ${required_with_safety}MB <= ${gpu_mem_mb}MB GPU memory"
        echo "false"
    fi
}