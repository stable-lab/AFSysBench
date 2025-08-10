# AFSysBench - AlphaFold 3 System Benchmarking

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.8+](https://img.shields.io/badge/python-3.8+-blue.svg)](https://www.python.org/downloads/)
[![Docker](https://img.shields.io/badge/docker-required-blue.svg)](https://www.docker.com/)

A modular, production-ready benchmarking system for evaluating AlphaFold 3 performance across different hardware configurations.

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
- **RTX 4080 (16GB)** - 6QNR inference in ~8 minutes with unified memory
- **H100 (80GB)** - Full benchmark suite without unified memory
- **AMD Ryzen 9 7900X** - Multi-threaded MSA performance evaluation
- **Intel Xeon** - Server-grade benchmarking

## 🏃 Quick Start

### Prerequisites

- Docker with GPU support
- NVIDIA drivers (550.54+ recommended)
- Python 3.8+
- AlphaFold 3 Docker image
- 32GB+ system RAM (for unified memory)

### Installation

1. Clone the repository:
```bash
git clone https://github.com/stable-lab/AFSysBench.git
cd AFSysBench
```

2. Configure your system:
```bash
cp benchmark.config.template myenv.config
# Edit myenv.config with your paths
```

3. Run your first benchmark:
```bash
# MSA benchmark
python ./runner -c myenv.config msa -i 2PV7.json -t 4

# Inference benchmark
python ./runner -c myenv.config inference -i 2pv7_data.json -t 4
```

### For Large Structures (Unified Memory)

```bash
# Edit your config file
nano myenv.config
# Change: UNIFIED_MEMORY=false
# To:     UNIFIED_MEMORY=true

# Run 6QNR on RTX 4080
python ./runner -c myenv.config inference -i 6QNR_subset_data.json -t 1
```

## 📖 Documentation

- [Installation Guide](docs/guides/installation.md)
- [Configuration Reference](docs/guides/configuration.md)
- [Unified Memory Guide](docs/guides/unified_memory.md)
- [Benchmarking Guide](docs/guides/benchmarking.md)
- [API Reference](docs/api/README.md)
- [Examples](docs/examples/README.md)

## 🏗️ Architecture

```
AFSysBench/
├── af_bench_runner_updated.py      # Main orchestrator
├── scripts/
│   ├── benchmark_msa_modular.sh    # MSA benchmarking logic
│   ├── benchmark_inference_modular.sh # Inference benchmarking
│   ├── profiling_runner.sh         # Profiling orchestrator
│   └── result_collector.sh         # Results aggregation
├── lib/
│   ├── docker_utils.sh             # Docker management
│   ├── logging.sh                  # Logging utilities
│   ├── gpu_memory_manager.py       # Memory management
│   ├── monitoring.sh               # System monitoring
│   └── result_parser.sh            # Results parsing
├── monitor_realtime.sh             # Real-time monitoring
├── run_inference_perf.sh           # Performance benchmarking
├── run_numa_pcm_profiling.sh       # NUMA/PCM profiling
├── track_progress.py               # Progress tracking
├── docs/                           # Documentation
└── results/                        # Benchmark results (generated)
```

## 🔬 Usage Examples

### Basic Benchmarking
```bash
# Run MSA benchmark with 8 threads
python ./runner -c myenv.config msa -i rcsb_pdb_7RCE.json -t 8

# Run inference with profiling
python ./runner -c myenv.config inference -i 1yy9_data.json -t 4 -p nsys
```

### Monitoring and Profiling
```bash
# Real-time system monitoring
./monitor_realtime.sh

# NUMA and PCM profiling
./run_numa_pcm_profiling.sh myenv.config 2pv7_data.json

# Performance inference benchmarking
./run_inference_perf.sh myenv.config

# Track progress of running jobs
python track_progress.py --config myenv.config --job-id inference_2024
```

### Batch Processing
```bash
# Process multiple samples
for sample in 2PV7 7RCE 1YY9; do
    python af_bench_runner_updated.py -c myenv.config msa -i ${sample}.json -t 4
done
```

### Large Structure Processing
```bash
# Edit config file to enable unified memory
nano my_system.config
# Set: UNIFIED_MEMORY=true

python af_bench_runner_updated.py -c my_system.config inference -i 6QNR_subset_data.json -t 1
```

## 📈 Results

Results are automatically saved in CSV format:
- `results/master_results.csv` - Consolidated benchmark data
- `output_*/inference_results_*.csv` - Individual run results
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

- AlphaFold 3 team at DeepMind
- NVIDIA for unified memory support
- Contributors and testers

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/stable-lab/AFSysBench/issues)
- **Discussions**: [GitHub Discussions](https://github.com/stable-lab/AFSysBench/discussions)

---
*AFSysBench - Benchmarking AlphaFold 3 for the scientific community*
