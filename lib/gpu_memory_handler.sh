#!/bin/bash
# Smart GPU memory handler for different hardware configurations

check_gpu_capacity_for_input() {
    local input_file="$1"
    local gpu_memory_mb=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null || echo "0")
    
    case "$input_file" in
        *6QNR*|*6qnr*)
            if [ "$gpu_memory_mb" -lt 20000 ]; then  # Less than 20GB
                echo "WARNING: 6QNR requires ~15GB GPU memory. Your GPU has ${gpu_memory_mb}MB."
                echo "Recommendation: Use CPU mode or upgrade to 24GB+ GPU"
                return 1  # Insufficient memory
            fi
            ;;
    esac
    return 0  # Sufficient memory
}

suggest_memory_mode() {
    local input_file="$1"
    local gpu_memory_mb=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null || echo "0")
    
    case "$input_file" in
        *6QNR*|*6qnr*)
            if [ "$gpu_memory_mb" -lt 20000 ]; then
                echo "cpu"  # Force CPU mode for insufficient GPU memory
            else
                echo "gpu_unified"  # Use GPU with unified memory
            fi
            ;;
        *)
            echo "gpu"  # Standard GPU mode
            ;;
    esac
}
