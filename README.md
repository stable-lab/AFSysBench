# AFSysBench - AlphaFold 3 System Benchmarking

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.10+](https://img.shields.io/badge/python-3.10+-blue.svg)](https://www.python.org/downloads/)
[![Docker](https://img.shields.io/badge/docker-required-blue.svg)](https://www.docker.com/)
[![AlphaFold 3](https://img.shields.io/badge/AlphaFold-3-green.svg)](https://github.com/google-deepmind/alphafold3)

A systematic benchmarking suite for evaluating [AlphaFold 3](https://github.com/google-deepmind/alphafold3) performance across different hardware configurations. **No external Python dependencies required!**

## 🚀 Key Features

- **Modular Architecture** - Clean separation between MSA and inference benchmarking
- **Unified Memory Support** - Run large structures (e.g., 6QNR) on consumer GPUs
- **Multi-threading Analysis** - Test performance across thread configurations
- **Hardware Profiling** - Built-in support for NVIDIA Nsight, Linux perf, and custom profilers
- **Real-time Monitoring** - Live system resource monitoring with `monitor_realtime.sh`
- **NUMA Profiling** - Advanced NUMA and PCM performance analysis
- **Automated Results** - CSV generation with master results tracking
- **Docker Integration** - Consistent environment across systems

## 📊 Proven Performance

Successfully tested on:

**Server System:**
- **Intel Xeon + H100 (80GB)** - Full benchmark suite without unified memory
- **Server-grade performance** - Optimal for large structure analysis

**Desktop System:**  
- **AMD Ryzen 9 7900X + RTX 4080 (16GB)** - 6QNR inference in ~8 minutes with unified memory
- **Consumer-grade accessibility** - Efficient multi-threaded MSA performance

## 🏃 Quick Start

### Prerequisites

- **AlphaFold 3**: Official implementation from [google-deepmind/alphafold3](https://github.com/google-deepmind/alphafold3)
- **Hardware**: NVIDIA GPU (16GB+ VRAM), 64GB+ RAM, 3TB+ storage for databases
- **Software**: Docker 20.10+, CUDA 12.0+, Python 3.10+ (for AF3 compatibility)
- **No additional Python packages needed** for benchmarking - uses only standard library!

### Installation

1. Clone the repository:
```bash
git clone https://github.com/stable-lab/AFSysBench.git
cd AFSysBench
```

2. Configure your system:
```bash
cp benchmark.config.template benchmark.config
# Edit benchmark.config with your AF3 paths
```

3. Quick test (5-7 minutes):
```bash
# Test complete pipeline: MSA + Inference
python runner -c benchmark.config msa -i 2PV7.json -t 1
python runner -c benchmark.config inference -i 2pv7_data.json -t 1

# Success = structure files created in results/
```

### For Large Structures (Consumer GPUs with Unified Memory)

```bash
# Only for desktop/consumer GPUs (≤16GB VRAM) - edit your config file
nano benchmark.config
# Set: ENABLE_UNIFIED_MEMORY=true

# Run 6QNR on consumer GPUs (e.g., RTX 4080)
# Note: Server GPUs (H100/A100 ≥80GB) run without unified memory
python runner -c benchmark.config inference -i 6QNR_subset_data.json -t 1
```

## 📖 Documentation

- [Installation Guide](INSTALL.md) - Detailed setup instructions
- [Reproduction Guide](REPRODUCE.md) - Reproduce paper results
- [Configuration Reference](docs/guides/configuration.md)
- [Unified Memory Guide](docs/guides/unified_memory.md)
- [Examples](docs/examples/README.md)

## 🏗️ Architecture

```
AFSysBench/
├── runner                           # Main Python orchestrator (executable)
├── scripts/
│   ├── benchmark_msa_modular.sh    # MSA benchmarking logic
│   ├── benchmark_inference_modular.sh # Inference benchmarking
├── lib/
│   ├── config.sh                   # Configuration management
│   ├── docker_utils.sh             # Docker management
│   ├── gpu_memory_manager.py       # GPU memory management
│   ├── logging.sh                  # Logging utilities
│   ├── monitoring.sh               # System monitoring
│   ├── result_parser.sh            # Result parsing and analysis
│   └── validation.sh               # System validation
├── input_msa/                      # MSA input files
├── input_inference/                # Inference input files
├── output_msa/                     # MSA benchmark results (generated)
├── output_inference/               # Inference benchmark results (generated)
├── results/                        # Aggregated benchmark results
├── monitor_realtime.sh             # Real-time system monitoring
├── run_statistical_benchmarks.sh   # Comprehensive statistical analysis
├── run_numa_pcm_profiling.sh       # NUMA/PCM profiling
├── run_full_msa_validation.sh      # MSA validation suite
└── docs/                           # Documentation
```

## 🔬 Usage Examples

### Basic Benchmarking
```bash
# Run MSA benchmark
python runner -c benchmark.config msa -i rcsb_pdb_7RCE.json -t 8

# Run inference benchmark
python runner -c benchmark.config inference -i 1yy9_data.json -t 4

# Run with profiling
python runner -c benchmark.config profile -i 1yy9_data.json -p nsys -s inference
```

### Monitoring and Profiling
```bash
# Real-time system monitoring
./monitor_realtime.sh

# NUMA and PCM profiling
./run_numa_pcm_profiling.sh myenv.config 2pv7_data.json


# Performance profiling (edit config file)
# Set PERF_STAT=true in benchmark.config for CPU performance statistics
python runner -c benchmark.config inference -i 2pv7_data.json -t 4

# Or set PERF_RECORD=true for detailed profiling
python runner -c benchmark.config msa -i 2PV7.json -t 4


# Note: Profiling requires specialized Docker images with tools pre-installed:
#   For PERF_STAT/PERF_RECORD: DOCKER_IMAGE="alphafold3" -> auto-selects "alphafold3:perf"
#   For NSYS profiling: requires "alphafold3:nsys" image
#   For uProf profiling: requires "alphafold3:uprof" image
#
# To build profiling images, modify Dockerfile to install tools:
#   perf: apt-get install linux-tools-generic
#   nsys: Install NVIDIA Nsight Systems
#   uprof: Install AMD uProf toolkit
#
# Alternative: Install all profiling tools in default image for unified setup

```

## 📈 Results

Results are automatically saved in CSV format:
- `results/master_results.csv` - Consolidated benchmark data
- `output_*/results_*.csv` - Individual run results
- `output_*/gpu_monitoring.csv` - GPU utilization metrics

## 🛠️ Configuration

Key configuration options in your config file:

```bash
# System Information
SYSTEM_NAME="my_system"
SYSTEM_TYPE="workstation"  # or "gpu"

# Paths
DB_DIR="/path/to/alphafold/databases"
MODEL_DIR="/path/to/alphafold/models"

# Memory Settings
UNIFIED_MEMORY=true  # Enable for large structures on limited GPU memory

# Benchmark Settings
THREAD_COUNTS="1 2 4 6 8"
```

## 🤝 Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [AlphaFold 3 team at Google DeepMind](https://github.com/google-deepmind/alphafold3)
- Contributors and testers

## 📚 Citation

If you use AFSysBench in your research, please cite:

```bibtex
@misc{afsysbench2025,
  title={AFSysBench: Systematic Benchmarking of AlphaFold 3 for Optimized Deployment},
  author={[To be updated]},
  year={2025},
  note={Manuscript in preparation. Citation details will be updated upon publication.}
}
```

*Note: This work is currently under review. Full citation details will be provided upon publication.*

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/stable-lab/AFSysBench/issues)
- **Discussions**: [GitHub Discussions](https://github.com/stable-lab/AFSysBench/discussions)

---
*AFSysBench - Benchmarking AlphaFold 3 for the scientific community*
