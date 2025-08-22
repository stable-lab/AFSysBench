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
- **RTX 4080 (16GB)** - 6QNR inference in ~8 minutes with unified memory
- **H100 (80GB)** - Full benchmark suite without unified memory
- **AMD Ryzen 9 7900X** - Multi-threaded MSA performance evaluation
- **Intel Xeon** - Server-grade benchmarking

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

### For Large Structures (Unified Memory)

```bash
# Edit your config file
nano benchmark.config
# Set: ENABLE_UNIFIED_MEMORY=true

# Run 6QNR on RTX 4080
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
│   ├── profiling_runner.sh         # Profiling orchestrator
│   └── result_collector.sh         # Results aggregation
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
├── output/                         # MSA results (generated)
├── output_inference/               # Inference results (generated)
├── results/                        # Aggregated benchmark results
├── monitor_realtime.sh             # Real-time monitoring
├── run_inference_perf.sh           # Performance benchmarking
├── run_numa_pcm_profiling.sh       # NUMA/PCM profiling
├── track_progress.py               # Progress tracking
├── docs/                           # Documentation
└── results/                        # Benchmark results (generated)
>>>>>>> c03d9565c7ff2a3ad9ef8a253ace384cbea77ad1
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

# Performance inference benchmarking
./run_inference_perf.sh myenv.config

# Track progress of running jobs
python track_progress.py --config myenv.config --job-id inference_2024
```

### Batch Processing
```bash
# Process multiple samples
for sample in 2PV7 7RCE 1YY9; do
    python runner -c benchmark.config msa -i ${sample}.json -t 4
done
```

### Large Structure Processing
```bash
# Edit config file to enable unified memory
nano benchmark.config
# Set: ENABLE_UNIFIED_MEMORY=true

python runner -c benchmark.config inference -i 6QNR_subset_data.json -t 1
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

- [AlphaFold 3 team at Google DeepMind](https://github.com/google-deepmind/alphafold3)
- NVIDIA for unified memory support
- Contributors and testers

## 📚 Citation

If you use AFSysBench in your research, please cite:

```bibtex
@article{afsysbench2024,
  title={AFSysBench: Systematic Benchmarking of AlphaFold 3 for Production Deployment},
  author={...},
  journal={...},
  year={2024}
}
```

## 📄 AlphaFold 3 Reference

```bibtex
@article{alphafold3_2024,
  title={Accurate structure prediction of biomolecular interactions with AlphaFold 3},
  author={Abramson, Josh and others},
  journal={Nature},
  year={2024},
  doi={10.1038/s41586-024-07487-w}
}
```

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/stable-lab/AFSysBench/issues)
- **Discussions**: [GitHub Discussions](https://github.com/stable-lab/AFSysBench/discussions)

---
*AFSysBench - Benchmarking AlphaFold 3 for the scientific community*
