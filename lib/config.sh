#!/bin/bash

# Configuration loading and validation utilities for AlphaFold benchmarking

# Load configuration from file
load_config() {
    local config_file=$1
    
    if [ -z "$config_file" ]; then
        echo "Error: No configuration file specified" >&2
        return 1
    fi
    
    if [ ! -f "$config_file" ]; then
        echo "Error: Configuration file not found: $config_file" >&2
        return 1
    fi
    
    echo "Loading configuration from: $config_file"
    source "$config_file"
    
    return 0
}

# Apply command-line overrides to configuration
apply_overrides() {
    # Override thread counts if specified
    if [ -n "$OVERRIDE_THREADS" ]; then
        echo "Overriding thread counts: $OVERRIDE_THREADS"
        THREAD_COUNTS="$OVERRIDE_THREADS"
    fi
    
    # Override system name if specified
    if [ -n "$OVERRIDE_SYSTEM_NAME" ]; then
        echo "Overriding system name: $OVERRIDE_SYSTEM_NAME"
        SYSTEM_NAME="$OVERRIDE_SYSTEM_NAME"
    fi
    
    # Override output directory if specified
    if [ -n "$OVERRIDE_OUTPUT_DIR" ]; then
        echo "Overriding output directory: $OVERRIDE_OUTPUT_DIR"
        OUTPUT_BASE="$OVERRIDE_OUTPUT_DIR"
    fi
}

# Set default values for missing configuration
set_defaults() {
    # System identification
    SYSTEM_NAME=${SYSTEM_NAME:-"unknown_system"}
    SYSTEM_TYPE=${SYSTEM_TYPE:-"cpu"}
    
    # Thread configuration
    THREAD_COUNTS=${THREAD_COUNTS:-"1 4 8 16"}
    
    # Docker configuration
    DOCKER_IMAGE=${DOCKER_IMAGE:-"alphafold/alphafold:latest"}
    
    # Directory configuration
    DB_DIR=${DB_DIR:-"/data/alphafold_dbs"}
    INPUT_DIR=${INPUT_DIR:-"input"}
    OUTPUT_BASE=${OUTPUT_BASE:-"output"}
    
    # Monitoring configuration
    SYSTEM_MONITOR=${SYSTEM_MONITOR:-false}
    MEMORY_MONITOR=${MEMORY_MONITOR:-false}
    GPU_MONITOR=${GPU_MONITOR:-false}
    
    # Debug mode
    DEBUG_MODE=${DEBUG_MODE:-false}
    
    # Profiling configuration
    PROFILING_ENABLED=${PROFILING_ENABLED:-false}
    PROFILING_TOOL=${PROFILING_TOOL:-""}
}

# Validate configuration
validate_config() {
    local errors=0
    
    # Check required variables
    if [ -z "$SYSTEM_NAME" ]; then
        echo "Error: SYSTEM_NAME not set" >&2
        ((errors++))
    fi
    
    if [ -z "$DOCKER_IMAGE" ]; then
        echo "Error: DOCKER_IMAGE not set" >&2
        ((errors++))
    fi
    
    if [ -z "$DB_DIR" ]; then
        echo "Error: DB_DIR not set" >&2
        ((errors++))
    fi
    
    # Validate directories exist
    if [ ! -d "$DB_DIR" ]; then
        echo "Error: Database directory not found: $DB_DIR" >&2
        ((errors++))
    fi
    
    # Validate system type
    case "$SYSTEM_TYPE" in
        cpu|gpu)
            ;;
        *)
            echo "Error: Invalid SYSTEM_TYPE: $SYSTEM_TYPE (must be 'cpu' or 'gpu')" >&2
            ((errors++))
            ;;
    esac
    
    # Validate boolean values
    for var in SYSTEM_MONITOR MEMORY_MONITOR GPU_MONITOR DEBUG_MODE PROFILING_ENABLED; do
        value=$(eval echo \$$var)
        case "$value" in
            true|false)
                ;;
            *)
                echo "Error: $var must be 'true' or 'false', got: $value" >&2
                ((errors++))
                ;;
        esac
    done
    
    return $errors
}

# Print configuration summary
print_config() {
    echo "=== Configuration Summary ==="
    echo "System Name: $SYSTEM_NAME"
    echo "System Type: $SYSTEM_TYPE"
    echo "Docker Image: $DOCKER_IMAGE"
    echo "Database Directory: $DB_DIR"
    echo "Input Directory: $INPUT_DIR"
    echo "Output Base: $OUTPUT_BASE"
    echo "Thread Counts: $THREAD_COUNTS"
    echo "System Monitoring: $SYSTEM_MONITOR"
    echo "Memory Monitoring: $MEMORY_MONITOR"
    echo "GPU Monitoring: $GPU_MONITOR"
    echo "Debug Mode: $DEBUG_MODE"
    echo "Profiling Enabled: $PROFILING_ENABLED"
    [ -n "$PROFILING_TOOL" ] && echo "Profiling Tool: $PROFILING_TOOL"
    echo "=========================="
}

# Export configuration as environment variables (for Docker)
export_config() {
    export ALPHAFOLD_SYSTEM_NAME="$SYSTEM_NAME"
    export ALPHAFOLD_SYSTEM_TYPE="$SYSTEM_TYPE"
    export ALPHAFOLD_DEBUG_MODE="$DEBUG_MODE"
    
    # Export profiling configuration
    if [ "$PROFILING_ENABLED" = true ]; then
        export ALPHAFOLD_PROFILING_ENABLED="true"
        export ALPHAFOLD_PROFILING_TOOL="$PROFILING_TOOL"
    fi
}

# Get configuration hash for tracking
get_config_hash() {
    local config_string=""
    config_string+="SYSTEM_NAME=$SYSTEM_NAME"
    config_string+="|SYSTEM_TYPE=$SYSTEM_TYPE"
    config_string+="|DOCKER_IMAGE=$DOCKER_IMAGE"
    config_string+="|THREAD_COUNTS=$THREAD_COUNTS"
    config_string+="|PROFILING=$PROFILING_ENABLED"
    config_string+="|PROFILING_TOOL=$PROFILING_TOOL"
    
    echo "$config_string" | sha256sum | cut -d' ' -f1 | cut -c1-8
}

# Main configuration loading function
load_and_validate_config() {
    local config_file=$1
    
    # Load configuration
    if ! load_config "$config_file"; then
        return 1
    fi
    
    # Set defaults
    set_defaults
    
    # Apply overrides
    apply_overrides
    
    # Validate
    if ! validate_config; then
        echo "Error: Configuration validation failed" >&2
        return 1
    fi
    
    # Export for Docker
    export_config
    
    # Print summary if debug mode
    if [ "$DEBUG_MODE" = true ]; then
        print_config
    fi
    
    return 0
}