#!/bin/bash
# Memory retry handler for automatic unified memory fallback

# Function to parse error logs for memory issues
check_memory_error() {
    local log_file="$1"
    
    # Common OOM error patterns
    local oom_patterns=(
        "CUDA_ERROR_OUT_OF_MEMORY"
        "CUDA out of memory"
        "OOM when allocating tensor"
        "ResourceExhaustedError"
        "failed to allocate.*memory"
        "GPU memory allocation failed"
        "tensorflow.python.framework.errors_impl.ResourceExhaustedError"
    )
    
    for pattern in "${oom_patterns[@]}"; do
        if grep -q "$pattern" "$log_file" 2>/dev/null; then
            return 0  # Memory error found
        fi
    done
    
    return 1  # No memory error
}

# Enhanced inference runner with automatic retry
run_inference_with_memory_fallback() {
    local config_file="$1"
    local json_file="$2"
    local threads="$3"
    local output_dir="$4"
    
    log_info "Running inference with automatic memory fallback..."
    
    # First attempt without unified memory
    local first_attempt_log=$(mktemp)
    
    # Run the benchmark
    UNIFIED_MEMORY=false \
    timeout 300 bash scripts/benchmark_inference_modular.sh \
        -c "$config_file" \
        -t "$threads" \
        "$json_file" 2>&1 | tee "$first_attempt_log"
    
    local exit_code=$?
    
    # Check if it failed due to memory
    if [ $exit_code -ne 0 ] && check_memory_error "$first_attempt_log"; then
        log_warning "First attempt failed with memory error, retrying with unified memory..."
        
        # Save the failed log
        cp "$first_attempt_log" "${output_dir}/failed_attempt_memory_error.log"
        
        # Retry with unified memory
        log_info "Enabling unified memory for retry..."
        
        # Temporarily enable unified memory
        export FORCE_UNIFIED_MEMORY=true
        export XLA_PYTHON_CLIENT_PREALLOCATE=false
        export TF_FORCE_UNIFIED_MEMORY=true
        export XLA_CLIENT_MEM_FRACTION=3.2
        
        # Second attempt with unified memory
        bash scripts/benchmark_inference_modular.sh \
            -c "$config_file" \
            -t "$threads" \
            "$json_file"
        
        exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            log_success "Succeeded with unified memory enabled"
            # Record that unified memory was used
            echo "unified_memory_used=true" >> "${output_dir}/run_metadata.txt"
        else
            log_error "Failed even with unified memory"
        fi
    fi
    
    rm -f "$first_attempt_log"
    return $exit_code
}