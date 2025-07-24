# Installation Guide

## Prerequisites

### System Requirements
- Linux (Ubuntu 20.04+ recommended)
- NVIDIA GPU with 8GB+ VRAM
- 32GB+ system RAM (for unified memory)
- Docker with GPU support

### AlphaFold 3 Setup
**Important**: You must first install AlphaFold 3 following the official instructions.

📖 **See**: [AlphaFold 3 GitHub Repository](https://github.com/google-deepmind/alphafold3) for complete installation instructions including:
- Docker image setup
- Database downloads  
- Model weights
- System requirements

## AFSysBench Installation

### 1. Clone AFSysBench
```bash
git clone https://github.com/stable-lab/AFSysBench.git
cd AFSysBench
```

### 2. Configure System
```bash
# Copy template configuration
cp benchmark.config.template my_system.config

# Edit configuration with your AlphaFold 3 paths
nano my_system.config
```

Update these settings based on your AlphaFold 3 installation:
```bash
DB_DIR="/path/to/alphafold_databases"      # From AlphaFold 3 setup
MODEL_DIR="/path/to/alphafold/models"      # From AlphaFold 3 setup  
DOCKER_IMAGE="alphafold3"                  # AlphaFold 3 Docker image name
```

### 3. Verify Installation
```bash
# Test AlphaFold 3 Docker access
docker run --rm --gpus all alphafold3 nvidia-smi

# Test AFSysBench
python af_bench_runner_updated.py --help
```

## Troubleshooting

### GPU Not Found
```bash
# Check NVIDIA drivers
nvidia-smi

# Check Docker GPU access
docker run --rm --gpus all nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi
```

### Permission Errors
```bash
# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker
```