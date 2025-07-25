#!/bin/bash

# Docker utilities for AlphaFold benchmarking

# Build base Docker command
build_docker_base() {
    local docker_cmd="docker run --rm"
    
    # Add interactive TTY if not in batch mode
    if [ -t 1 ]; then
        docker_cmd+=" -it"
    fi
    
    echo "$docker_cmd"
}

# Add volume mounts to Docker command
add_volume_mounts() {
    local docker_cmd=$1
    local input_dir=$2
    local output_dir=$3
    local db_dir=$4
    
    # Resolve paths to absolute paths
    local abs_input_dir=$(realpath "$input_dir")
    local abs_output_dir=$(realpath "$output_dir")
    local abs_db_dir=$(realpath "$db_dir")
    
    # Input directory (read-only) - using legacy approach
    docker_cmd+=" -v $abs_input_dir:/input:ro"
    
    # Output directory - using legacy approach
    docker_cmd+=" -v $abs_output_dir:/output"
    
    # Database directory (read-only) - using legacy approach
    docker_cmd+=" -v $abs_db_dir:/db:ro"
    
    # Add custom mounts if specified
    if [ -n "$CUSTOM_MOUNTS" ]; then
        for mount in $CUSTOM_MOUNTS; do
            docker_cmd+=" -v \"$mount\""
        done
    fi
    
    echo "$docker_cmd"
}

# Add GPU support to Docker command
add_gpu_support() {
    local docker_cmd=$1
    local system_type=$2
    
    if [ "$system_type" = "gpu" ]; then
        docker_cmd+=" --gpus all"
    fi
    
    echo "$docker_cmd"
}

# Add environment variables to Docker command
add_environment_vars() {
    local docker_cmd=$1
    local threads=$2
    
    # OpenMP thread count
    docker_cmd+=" -e OMP_NUM_THREADS=$threads"
    
    # Pass through profiling configuration
    if [ "$PROFILING_ENABLED" = true ]; then
        docker_cmd+=" -e ALPHAFOLD_PROFILING_ENABLED=true"
        docker_cmd+=" -e ALPHAFOLD_PROFILING_TOOL=$PROFILING_TOOL"
    fi
    
    # Debug mode
    if [ "$DEBUG_MODE" = true ]; then
        docker_cmd+=" -e ALPHAFOLD_DEBUG=true"
    fi
    
    # System identification
    docker_cmd+=" -e ALPHAFOLD_SYSTEM_NAME=$SYSTEM_NAME"
    docker_cmd+=" -e ALPHAFOLD_SYSTEM_TYPE=$SYSTEM_TYPE"
    
    # Add custom environment variables if specified
    if [ -n "$CUSTOM_ENV_VARS" ]; then
        for var in $CUSTOM_ENV_VARS; do
            docker_cmd+=" -e \"$var\""
        done
    fi
    
    echo "$docker_cmd"
}

# Add unified memory configuration for specific cases
add_unified_memory_config() {
    local docker_cmd=$1
    local input_name=$2
    
    # Check if this is a case requiring unified memory
    case "$input_name" in
        *multimer*)
            # Add unified memory percentage for multimer cases
            local unified_memory_pct=${UNIFIED_MEMORY_PCT:-50}
            docker_cmd+=" -e TF_FORCE_UNIFIED_MEMORY=1"
            docker_cmd+=" -e XLA_PYTHON_CLIENT_MEM_FRACTION=0.$unified_memory_pct"
            echo "Note: Enabling unified memory for multimer case (${unified_memory_pct}%)" >&2
            ;;
    esac
    
    echo "$docker_cmd"
}

# Add profiling tool configuration
add_profiling_config() {
    local docker_cmd=$1
    local profiling_tool=$2
    local output_dir=$3
    
    case "$profiling_tool" in
        perf_stat)
            # Use privileged mode but skip problematic /proc /sys mounts for our environment
            docker_cmd="${docker_cmd/docker run/docker run --privileged}"
            ;;
        perf_record)
            # Use privileged mode but skip problematic /proc /sys mounts for our environment
            docker_cmd="${docker_cmd/docker run/docker run --privileged}"
            ;;
        nsys)
            # For NVIDIA Nsight Systems
            docker_cmd="${docker_cmd/docker run/docker run --privileged}"
            docker_cmd+=" -v \"$output_dir/nsys_reports\":/nsys_output"
            ;;
        uprof)
            # For AMD uProf
            docker_cmd="${docker_cmd/docker run/docker run --privileged}"
            docker_cmd+=" -v \"$output_dir/uprof_reports\":/uprof_output"
            ;;
        memory_peak)
            # Memory profiling doesn't need special privileges
            ;;
    esac
    
    echo "$docker_cmd"
}

# Build complete Docker command for AlphaFold MSA
build_msa_docker_command() {
    local input_file=$1
    local output_dir=$2
    local threads=$3
    local db_dir=$4
    local docker_image=$5
    local system_type=$6
    
    # Start with base command
    local docker_cmd=$(build_docker_base)
    
    # Add GPU support if needed
    docker_cmd=$(add_gpu_support "$docker_cmd" "$system_type")
    
    # Add volume mounts
    docker_cmd=$(add_volume_mounts "$docker_cmd" "$(dirname "$input_file")" "$output_dir" "$db_dir")
    
    # Add environment variables
    docker_cmd=$(add_environment_vars "$docker_cmd" "$threads")
    
    # Add unified memory config if needed
    local input_name=$(basename "$input_file" .json)
    docker_cmd=$(add_unified_memory_config "$docker_cmd" "$input_name")
    
    # Add profiling configuration if enabled
    if [ "$PROFILING_ENABLED" = true ]; then
        docker_cmd=$(add_profiling_config "$docker_cmd" "$PROFILING_TOOL" "$output_dir")
    fi
    
    # Add image and command - use perf image when profiling is enabled
    if [ "$PROFILING_ENABLED" = true ]; then
        docker_cmd+=" ${docker_image}:perf"
        docker_cmd+=" bash /output/run_perf.sh"
    else
        docker_cmd+=" $docker_image"
        docker_cmd+=" python run_alphafold.py"
        docker_cmd+=" --json_path=/input/$(basename "$input_file")"
        docker_cmd+=" --output_dir=/output"
        docker_cmd+=" --db_dir=/db"
        docker_cmd+=" --max_template_date=2023-01-01"
        docker_cmd+=" --run_data_pipeline=true"
        docker_cmd+=" --run_inference=false"
    fi
    
    echo "$docker_cmd"
}

# Build complete Docker command for AlphaFold inference
build_inference_docker_command() {
    local input_file=$1
    local output_dir=$2
    local threads=$3
    local db_dir=$4
    local docker_image=$5
    local system_type=$6
    local model_name=$7
    
    # Start with base command
    local docker_cmd=$(build_docker_base)
    
    # Add GPU support if needed
    docker_cmd=$(add_gpu_support "$docker_cmd" "$system_type")
    
    # Add volume mounts
    docker_cmd=$(add_volume_mounts "$docker_cmd" "$(dirname "$input_file")" "$output_dir" "$db_dir")
    
    # Add environment variables
    docker_cmd=$(add_environment_vars "$docker_cmd" "$threads")
    
    # Add unified memory config if needed
    local input_name=$(basename "$input_file" .json)
    docker_cmd=$(add_unified_memory_config "$docker_cmd" "$input_name")
    
    # Add profiling configuration if enabled
    if [ "$PROFILING_ENABLED" = true ]; then
        docker_cmd=$(add_profiling_config "$docker_cmd" "$PROFILING_TOOL" "$output_dir")
    fi
    
    # Add image and command - use perf image when profiling is enabled
    if [ "$PROFILING_ENABLED" = true ]; then
        docker_cmd+=" ${docker_image}:perf"
        docker_cmd+=" bash /output/run_perf.sh"
    else
        docker_cmd+=" $docker_image"
        docker_cmd+=" python run_alphafold.py"
        docker_cmd+=" --json_path=/input/$(basename "$input_file")"
        docker_cmd+=" --output_dir=/output"
        docker_cmd+=" --db_dir=/db"
        docker_cmd+=" --max_template_date=2023-01-01"
        docker_cmd+=" --run_data_pipeline=false"
        docker_cmd+=" --run_inference=true"
        docker_cmd+=" --model_names=$model_name"
    fi
    
    echo "$docker_cmd"
}

# Execute Docker command with proper error handling
execute_docker_command() {
    local docker_cmd=$1
    local description=$2
    
    if [ "$DEBUG_MODE" = true ]; then
        echo "DEBUG: Docker command: $docker_cmd" >&2
    fi
    
    echo "Executing: $description"
    
    # Execute the command (perf now runs inside container with --privileged mode)
    if eval "$docker_cmd"; then
        echo "Success: $description completed"
        return 0
    else
        echo "Error: $description failed" >&2
        return 1
    fi
}

# Check if Docker is available
check_docker_available() {
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed or not in PATH" >&2
        return 1
    fi
    
    if ! docker info &> /dev/null; then
        echo "Error: Docker daemon is not running or not accessible" >&2
        return 1
    fi
    
    return 0
}

# Check if Docker image exists
check_docker_image() {
    local image=$1
    
    if ! docker image inspect "$image" &> /dev/null; then
        echo "Error: Docker image not found: $image" >&2
        echo "Please pull the image with: docker pull $image" >&2
        return 1
    fi
    
    return 0
}

# Get container ID for a running AlphaFold process
get_alphafold_container_id() {
    docker ps --filter "ancestor=$DOCKER_IMAGE" --format "{{.ID}}" | head -1
}

# Monitor Docker container stats
monitor_docker_stats() {
    local container_id=$1
    local output_file=$2
    
    if [ -n "$container_id" ]; then
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" "$container_id" >> "$output_file"
    fi
}

# Build Docker command for inference (generic version)
build_docker_command() {
    local docker_image=$1
    local threads=$2
    local use_gpu=$3
    local unified_memory=$4
    local input_dir=$5
    local output_dir=$6
    local db_dir=$7
    local model_dir=$8
    
    local docker_cmd="docker run --rm"
    
    # Add GPU support if enabled
    if [ "$use_gpu" = true ]; then
        docker_cmd="$docker_cmd --gpus all"
    fi
    
    # Add unified memory configuration
    if [ "$unified_memory" = true ]; then
        docker_cmd="$docker_cmd \
        -e XLA_PYTHON_CLIENT_PREALLOCATE=false \
        -e TF_FORCE_UNIFIED_MEMORY=true \
        -e XLA_CLIENT_MEM_FRACTION=3.2"
    fi
    
    # Add volume mounts and environment (use absolute paths to avoid character issues)
    local abs_input_dir=$(realpath "$PWD/$input_dir")
    local abs_output_dir=$(realpath "$PWD/$output_dir")
    local abs_db_dir=$(realpath "$db_dir")
    local abs_model_dir=$(realpath "$model_dir")
    
    docker_cmd="$docker_cmd \
        -v $abs_input_dir:/input:ro \
        -v $abs_output_dir:/output \
        -v $abs_db_dir:/db:ro \
        -v $abs_model_dir:/root/models:ro \
        -e OMP_NUM_THREADS=$threads \
        $docker_image"
    
    echo "$docker_cmd"
}