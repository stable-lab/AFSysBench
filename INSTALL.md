# Installation Guide

## Prerequisites

### System Requirements (AlphaFold 3 + Benchmarking)

#### Minimum Requirements
- **RAM**: 64GB (more needed for large structures)
- **GPU**: NVIDIA GPU with Compute Capability 8.0+ and 16GB+ VRAM (CUDA 12.6 compatible)
- **Storage**: 630GB+ for full databases (252GB download), 10GB+ for testing (SSD recommended)
- **OS**: Ubuntu 22.04 LTS (recommended by AlphaFold 3 team)

#### Recommended for Production
- **RAM**: 128GB+ (256GB for very large complexes)
- **GPU**: NVIDIA A100 (80GB) or H100 (80GB) recommended (CUDA 12.6 compatible)
- **Storage**: 4TB+ SSD for databases (630GB required minimum)

### Software Requirements

#### AlphaFold 3 Requirements
- **Python**: 3.10+ (AF3 requires Python 3.10 or later)
- **Docker**: Latest version recommended
- **NVIDIA Driver**: 550.120+ (CUDA 12.6 compatible)
- **Git**: For repository cloning

#### AFSysBench Requirements
- **Python**: 3.10+ (matching AF3, standard library only for benchmarking)
- **Bash**: 4.0+ (for scripts)

## AlphaFold 3 Setup

### 1. Get AlphaFold 3 from the official repository

```bash
git clone https://github.com/google-deepmind/alphafold3.git
cd alphafold3
```

### 2. Build the AlphaFold 3 Docker image

```bash
# Build from source
docker build -f docker/Dockerfile -t alphafold3 .
```

Or use the official pre-built image if available:
```bash
docker pull ghcr.io/google-deepmind/alphafold3:latest
```

### 3. Install AlphaFold 3 Python dependencies

AlphaFold 3 requires specific Python packages. Follow the official setup:
```bash
# Create conda environment (recommended by AF3 team)
conda create -n alphafold3 python=3.10
conda activate alphafold3

# Install JAX with CUDA support
pip install --upgrade "jax[cuda12_pip]" -f https://storage.googleapis.com/jax-releases/jax_cuda_releases.html

# Install other AF3 requirements
pip install -r https://raw.githubusercontent.com/google-deepmind/alphafold3/main/requirements.txt
```

**Note**: AFSysBench itself doesn't need these packages - only AlphaFold 3 does.

### 4. Download model weights and databases

Follow the official instructions at: https://github.com/google-deepmind/alphafold3#model-parameters

**Important**: 
- Model weights require accepting the license terms
- Database download can take ~45 minutes (252GB download, 630GB when unzipped)
- Ensure you have sufficient storage space and permissions (chmod 755)

### 5. Verify AlphaFold 3 installation

```bash
# Test with a simple example
docker run --gpus all alphafold3 --version
```

## AFSysBench Setup

### 1. Clone this repository

```bash
git clone https://github.com/stable-lab/AFSysBench.git
cd AFSysBench
```

### 2. Configure benchmark settings

```bash
# Copy the template configuration
cp benchmark.config.template benchmark.config

# Edit with your preferred editor
nano benchmark.config  # or vim, emacs, etc.
```

Key configuration parameters:
- `AF3_DOCKER_IMAGE`: Name of your AlphaFold 3 Docker image (e.g., "alphafold3")
- `AF3_MODEL_DIR`: Absolute path to downloaded model parameters
- `AF3_DATABASE_DIR`: Absolute path to genetic databases (for MSA)
- `OUTPUT_DIR`: Where to store benchmark results
- `MAX_GPU_MEMORY`: GPU memory limit in GB
- `ENABLE_UNIFIED_MEMORY`: Set to "true" for large structures

### 3. Set up permissions

```bash
# Make scripts executable
chmod +x *.sh
chmod +x scripts/*.sh
chmod +x runner

# If using Docker, ensure user is in docker group
sudo usermod -aG docker $USER
# Log out and back in for group changes to take effect
```

### 4. Verify installation with quick test

Test your setup with the complete AF3 pipeline (5-7 minutes):

```bash
# Test both MSA generation and inference - complete pipeline
python runner -c benchmark.config msa -i 2PV7.json -t 1
python runner -c benchmark.config inference -i 2pv7_data.json -t 1

# Expected output:
# - MSA completes in 3-4 minutes
# - Inference completes in 2-3 minutes  
# - Creates results/msa_* and results/inference_* directories
# - Generates MSA files and structure files
# - Shows "Benchmark completed successfully" for both
```

**Expected behavior:**
- ✅ Docker container starts successfully for both stages
- ✅ AF3 MSA generation completes without errors
- ✅ AF3 inference loads models and completes
- ✅ Output files created in `results/` for both stages

If both work, your installation is ready for full benchmarks!

## Configuration Examples

### For systems with limited GPU memory (16GB)
```bash
MAX_GPU_MEMORY=15
ENABLE_UNIFIED_MEMORY=true
BATCH_SIZE=1
```

### For high-memory systems (48GB+ GPU)
```bash
MAX_GPU_MEMORY=46
ENABLE_UNIFIED_MEMORY=false
BATCH_SIZE=4
```

### For CPU-only profiling
```bash
USE_GPU=false
NUM_THREADS=32
```

## No Python Dependencies Required!

This benchmarking suite uses only Python standard library. No `pip install` or `conda env` needed - just run!

## Troubleshooting

### GPU Memory Issues
```bash
# Check available GPU memory
nvidia-smi

# Enable unified memory for large structures
export ENABLE_UNIFIED_MEMORY=true
```

### Docker Permission Denied
```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Apply changes (or log out/in)
newgrp docker
```

### CUDA Version Mismatch
```bash
# Check driver CUDA version
nvidia-smi

# Check Docker CUDA version
docker run --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
```

### Cannot Find AlphaFold Model Files
Ensure paths in `benchmark.config` are absolute paths:
```bash
# Good
AF3_MODEL_DIR=/home/user/alphafold3/models

# Bad
AF3_MODEL_DIR=~/alphafold3/models
AF3_MODEL_DIR=./models
```

### Benchmark Hangs or Crashes
1. Check system resources:
   ```bash
   # Monitor during run
   htop  # CPU/RAM
   nvidia-smi -l 1  # GPU
   ```

2. Start with smaller test cases:
   ```bash
   # Use 2pv7 (smallest) first
   ./runner --input input_inference/2pv7_data.json
   ```

3. Check Docker logs:
   ```bash
   docker logs $(docker ps -lq)
   ```

## Performance Tuning

### Memory Optimization
- Use `ENABLE_UNIFIED_MEMORY=true` for structures requiring >GPU VRAM
- Reduce `BATCH_SIZE` if encountering OOM errors
- Monitor with `nvidia-smi` during runs

### Speed Optimization
- Increase `NUM_THREADS` for CPU portions
- Use `ENABLE_ASYNC=true` for overlapped I/O
- Disable logging for production runs: `LOG_LEVEL=ERROR`

## Support

For issues specific to:
- **AlphaFold 3**: https://github.com/google-deepmind/alphafold3/issues
- **AFSysBench**: https://github.com/stable-lab/AFSysBench/issues

## References

- Official AlphaFold 3 Repository: https://github.com/google-deepmind/alphafold3
- AlphaFold 3 Paper: https://doi.org/10.1038/s41586-024-07487-w
- Model License: https://github.com/google-deepmind/alphafold3/blob/main/WEIGHTS_TERMS_OF_USE.md