# Configuration Reference

## Overview
AFSysBench uses a configuration file to manage system-specific settings. Copy `benchmark.config.template` to create your configuration.

## Required Settings

### System Information
```bash
SYSTEM_NAME="my_system"              # Unique name for your system
SYSTEM_TYPE="workstation"            # "workstation" or "gpu"
CPU_ARCHITECTURE="amd"               # "amd" or "intel"
```

### Paths (Must be edited)
```bash
DB_DIR="/path/to/alphafold_databases"    # AlphaFold database directory
MODEL_DIR="/path/to/alphafold/models"    # Model weights directory
DOCKER_IMAGE="alphafold3"                # Docker image name
```

### Input/Output Directories
```bash
MSA_INPUT_DIR="input_msa"                # MSA input files
INFERENCE_INPUT_DIR="input_inference"     # Inference input files
MSA_OUTPUT_BASE="output_msa"             # MSA results
INFERENCE_OUTPUT_BASE="output_inference"  # Inference results
```

## Benchmark Settings

### Thread Configuration
```bash
THREAD_COUNTS="1 2 4 6 8"               # Space-separated thread counts to test
```

### Memory Settings
```bash
UNIFIED_MEMORY=false                     # Set to true for large structures
```

### Profiling Options
```bash
PERF_RECORD=false                       # Enable perf recording
PERF_STAT=false                         # Enable perf stat
SYSTEM_MONITOR=false                    # Enable system monitoring
```

## Example Configurations

### RTX 4080 Workstation
```bash
SYSTEM_NAME="rtx4080_workstation"
SYSTEM_TYPE="workstation"
UNIFIED_MEMORY=true                    # Enable for large structures
THREAD_COUNTS="1 2 4 6 8"
```

### High-End GPU Server
```bash
SYSTEM_NAME="gpu_server"
SYSTEM_TYPE="gpu"
UNIFIED_MEMORY=false                   # H100/A100 has sufficient VRAM
THREAD_COUNTS="8 16 32 48"
```