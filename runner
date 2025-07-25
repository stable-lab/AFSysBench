#!/usr/bin/env python3
"""
AFSysBench Runner - Python integration for AlphaFold benchmarking
Updated to work with the new modular architecture
"""

import argparse
import subprocess
import json
import os
import sys
import time
import csv
import shutil
import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any
from dataclasses import dataclass, field
from concurrent.futures import ThreadPoolExecutor, as_completed


@dataclass
class BenchmarkConfig:
    """Configuration for AlphaFold benchmarking"""
    # System information
    system_name: str = "my_system"
    system_type: str = "workstation"
    cpu_architecture: str = "amd"
    
    # Paths
    db_dir: str = ""
    model_dir: str = ""
    docker_image: str = "alphafold3"
    
    # Input/Output directories
    msa_input_dir: str = "input_msa"
    inference_input_dir: str = "input_inference"
    msa_output_base: str = "output_msa"
    inference_output_base: str = "output_inference"
    
    # Benchmark settings
    thread_counts: List[int] = field(default_factory=lambda: [4, 8, 16])
    profiling_mode: bool = False
    profiling_tool: str = ""
    run_purpose: str = "performance"
    
    # Docker resources
    docker_memory: str = "32g"
    docker_shm_size: str = "8g"
    docker_cpus: Optional[int] = None
    
    # Performance settings
    system_monitor: bool = True
    gpu_monitor: bool = True
    memory_monitor: bool = True
    
    # Model generation
    num_models: int = 5
    
    @classmethod
    def from_file(cls, config_path: str) -> 'BenchmarkConfig':
        """Load configuration from shell config file"""
        config = cls()
        
        if not os.path.exists(config_path):
            raise FileNotFoundError(f"Config file not found: {config_path}")
            
        # Parse shell-style config file
        with open(config_path, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    key = key.strip()
                    # Remove comments first
                    if '#' in value:
                        value = value.split('#')[0]
                    value = value.strip().strip('"').strip("'")
                    
                    # Map config keys to dataclass attributes
                    if key == 'SYSTEM_NAME':
                        config.system_name = value
                    elif key == 'SYSTEM_TYPE':
                        config.system_type = value
                    elif key == 'CPU_ARCHITECTURE':
                        config.cpu_architecture = value
                    elif key == 'DB_DIR':
                        config.db_dir = value
                    elif key == 'MODEL_DIR':
                        config.model_dir = value
                    elif key == 'DOCKER_IMAGE':
                        config.docker_image = value
                    elif key == 'MSA_INPUT_DIR':
                        config.msa_input_dir = value
                    elif key == 'INFERENCE_INPUT_DIR':
                        config.inference_input_dir = value
                    elif key == 'MSA_OUTPUT_BASE':
                        config.msa_output_base = value
                    elif key == 'INFERENCE_OUTPUT_BASE':
                        config.inference_output_base = value
                    elif key == 'THREAD_COUNTS':
                        # Value should already be cleaned by the main parser
                        config.thread_counts = [int(x.strip()) for x in value.split()]
                    elif key == 'PROFILING_TOOL':
                        if value:
                            config.profiling_tool = value
                            config.profiling_mode = True
                            config.run_purpose = "profiling"
                    elif key == 'SYSTEM_MONITOR':
                        config.system_monitor = value.lower() == 'true'
                    elif key == 'GPU_MONITOR':
                        config.gpu_monitor = value.lower() == 'true'
                    elif key == 'MEMORY_MONITOR':
                        config.memory_monitor = value.lower() == 'true'
                    elif key == 'DOCKER_MEMORY':
                        config.docker_memory = value
                    elif key == 'DOCKER_SHM_SIZE':
                        config.docker_shm_size = value
                    elif key == 'DOCKER_CPUS':
                        config.docker_cpus = int(value) if value else None
                    elif key == 'NUM_MODELS':
                        config.num_models = int(value)
                        
        return config


class AFBenchRunner:
    """Main benchmark runner class that uses the new modular scripts"""
    
    def __init__(self, config: BenchmarkConfig):
        self.config = config
        self.logger = self._setup_logging()
        self.base_dir = os.path.dirname(os.path.abspath(__file__))
        self.scripts_dir = os.path.join(self.base_dir, 'scripts')
        
        # Check if scripts directory exists
        if not os.path.exists(self.scripts_dir):
            self.logger.warning(f"Scripts directory not found at {self.scripts_dir}, using base directory")
            self.scripts_dir = self.base_dir
        
    def _setup_logging(self) -> logging.Logger:
        """Setup logging configuration"""
        logger = logging.getLogger('AFBenchRunner')
        logger.setLevel(logging.INFO)
        
        # Console handler
        ch = logging.StreamHandler()
        ch.setLevel(logging.INFO)
        formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
        ch.setFormatter(formatter)
        logger.addHandler(ch)
        
        return logger
        
    def _get_script_path(self, script_name: str) -> str:
        """Get the full path to a script"""
        # Map to modular script names
        script_mapping = {
            'benchmark_msa.sh': 'benchmark_msa_modular.sh',
            'benchmark_inference.sh': 'benchmark_inference_modular.sh'
        }
        
        # Use modular version if available
        if script_name in script_mapping:
            modular_name = script_mapping[script_name]
            script_path = os.path.join(self.scripts_dir, modular_name)
            if os.path.exists(script_path):
                return script_path
        
        # First try scripts directory
        script_path = os.path.join(self.scripts_dir, script_name)
        if os.path.exists(script_path):
            return script_path
            
        # Fall back to base directory
        script_path = os.path.join(self.base_dir, script_name)
        if os.path.exists(script_path):
            return script_path
            
        raise FileNotFoundError(f"Script not found: {script_name}")
        
    def _run_command(self, cmd: List[str], cwd: Optional[str] = None, 
                     capture_output: bool = True, env: Optional[Dict] = None) -> subprocess.CompletedProcess:
        """Run a shell command and return the result"""
        self.logger.debug(f"Running command: {' '.join(cmd)}")
        
        # Merge environment variables
        cmd_env = os.environ.copy()
        if env:
            cmd_env.update(env)
            
        # Add profiling configuration to environment
        if self.config.profiling_mode:
            cmd_env['PROFILING_ENABLED'] = 'true'
            cmd_env['PROFILING_TOOL'] = self.config.profiling_tool
        
        # Set timeout based on the command type - longer for inference
        timeout_seconds = 3600  # 1 hour default
        if any("inference" in str(arg) for arg in cmd):
            timeout_seconds = 7200  # 2 hours for inference
            
        result = subprocess.run(
            cmd,
            cwd=cwd or self.base_dir,
            capture_output=capture_output,
            text=True,
            shell=False,
            env=cmd_env,
            timeout=timeout_seconds
        )
        
        if result.returncode != 0:
            self.logger.error(f"Command failed: {' '.join(cmd)}")
            if capture_output:
                self.logger.error(f"STDOUT: {result.stdout}")
                self.logger.error(f"STDERR: {result.stderr}")
                
        return result
        
    def run_msa_benchmark(self, input_file: str, thread_counts: Optional[List[int]] = None,
                         output_dir: Optional[str] = None) -> Dict[str, Any]:
        """Run MSA benchmark using the new modular script"""
        self.logger.info(f"Running MSA benchmark for {input_file}")
        
        # Auto-determine input path if not already prefixed
        if not input_file.startswith('input_msa/') and not os.path.isabs(input_file):
            full_input_path = f"input_msa/{input_file}"
        else:
            full_input_path = input_file
        
        # Build command
        script_path = self._get_script_path('benchmark_msa.sh')
        cmd = [script_path, "-c", self.config.__dict__.get('config_file', 'myenv.config')]
        
        # Add thread counts if specified
        if thread_counts:
            cmd.extend(["-t", " ".join(map(str, thread_counts))])
            
        # Add output directory if specified
        if output_dir:
            cmd.extend(["-o", output_dir])
            
        # Add input file
        cmd.append(full_input_path)
        
        # Run the benchmark
        start_time = time.time()
        result = self._run_command(cmd)
        duration = time.time() - start_time
        
        return {
            'input_file': input_file,
            'command': ' '.join(cmd),
            'duration': duration,
            'success': result.returncode == 0,
            'stdout': result.stdout if result.returncode == 0 else None,
            'stderr': result.stderr if result.returncode != 0 else None,
            'run_purpose': self.config.run_purpose
        }
        
    def run_inference_benchmark(self, input_file: str, thread_counts: Optional[List[int]] = None,
                               enable_nsys: bool = False, num_models: Optional[int] = None,
                               output_dir: Optional[str] = None) -> Dict[str, Any]:
        """Run inference benchmark using the new modular script"""
        self.logger.info(f"Running inference benchmark for {input_file}")
        
        # Auto-determine input path if not already prefixed
        if not input_file.startswith('input_inference/') and not os.path.isabs(input_file):
            full_input_path = f"input_inference/{input_file}"
        else:
            full_input_path = input_file
        
        # Build command
        script_path = self._get_script_path('benchmark_inference.sh')
        cmd = [script_path, "-c", self.config.__dict__.get('config_file', 'myenv.config')]
        
        # Add thread counts if specified
        if thread_counts:
            cmd.extend(["-t", " ".join(map(str, thread_counts))])
            
        # Add NSYS profiling
        if enable_nsys:
            cmd.append("-n")
            
        # Add model count
        if num_models:
            cmd.extend(["-m", str(num_models)])
            
        # Add output directory if specified
        if output_dir:
            cmd.extend(["-o", output_dir])
            
        # Add input file
        cmd.append(full_input_path)
        
        # Run the benchmark
        start_time = time.time()
        result = self._run_command(cmd)
        duration = time.time() - start_time
        
        return {
            'input_file': input_file,
            'command': ' '.join(cmd),
            'duration': duration,
            'success': result.returncode == 0,
            'stdout': result.stdout if result.returncode == 0 else None,
            'stderr': result.stderr if result.returncode != 0 else None,
            'run_purpose': self.config.run_purpose
        }
        
    def run_batch(self, input_dir: str, stage: str = 'msa',
                  thread_counts: Optional[List[int]] = None,
                  batch_name: Optional[str] = None) -> Dict[str, Any]:
        """Run batch benchmarks using the new batch_runner.sh script"""
        self.logger.info(f"Running batch {stage} benchmarks from {input_dir}")
        
        # Build command
        script_path = self._get_script_path('batch_runner.sh')
        cmd = [script_path, "-c", self.config.__dict__.get('config_file', 'myenv.config')]
        
        # Add input directory and stage
        cmd.extend(["-i", input_dir, "-s", stage])
        
        # Add thread counts if specified
        if thread_counts:
            cmd.extend(["-t", " ".join(map(str, thread_counts))])
            
        # Add batch name if specified
        if batch_name:
            cmd.extend(["-n", batch_name])
        
        # Run the batch
        start_time = time.time()
        result = self._run_command(cmd)
        duration = time.time() - start_time
        
        return {
            'input_dir': input_dir,
            'stage': stage,
            'command': ' '.join(cmd),
            'duration': duration,
            'success': result.returncode == 0,
            'stdout': result.stdout if result.returncode == 0 else None,
            'stderr': result.stderr if result.returncode != 0 else None
        }
        
    def run_profiling(self, input_file: str, profiling_tool: str, stage: str,
                      threads: Optional[int] = None, output_dir: Optional[str] = None) -> Dict[str, Any]:
        """Run profiling using the new profiling_runner.sh script"""
        self.logger.info(f"Running {profiling_tool} profiling for {input_file}")
        
        # Auto-determine input path based on stage
        if not os.path.isabs(input_file):
            if stage == 'msa' and not input_file.startswith('input_msa/'):
                full_input_path = f"input_msa/{input_file}"
            elif stage == 'inference' and not input_file.startswith('input_inference/'):
                full_input_path = f"input_inference/{input_file}"
            else:
                full_input_path = input_file
        else:
            full_input_path = input_file
        
        # Build command
        script_path = self._get_script_path('profiling_runner.sh')
        cmd = [script_path, "-c", self.config.__dict__.get('config_file', 'myenv.config')]
        
        # Add profiling tool and stage
        cmd.extend(["-p", profiling_tool, "-s", stage])
        
        # Add thread count if specified
        if threads:
            cmd.extend(["-t", str(threads)])
            
        # Add output directory if specified
        if output_dir:
            cmd.extend(["-o", output_dir])
            
        # Add input file
        cmd.append(full_input_path)
        
        # Run the profiling
        start_time = time.time()
        result = self._run_command(cmd)
        duration = time.time() - start_time
        
        return {
            'input_file': input_file,
            'profiling_tool': profiling_tool,
            'stage': stage,
            'command': ' '.join(cmd),
            'duration': duration,
            'success': result.returncode == 0,
            'stdout': result.stdout if result.returncode == 0 else None,
            'stderr': result.stderr if result.returncode != 0 else None
        }
        
    def collect_results(self, input_dir: str, result_type: str = 'all',
                       output_format: str = 'csv') -> Dict[str, Any]:
        """Collect and aggregate results using result_collector.sh"""
        self.logger.info(f"Collecting {result_type} results from {input_dir}")
        
        # Build command
        script_path = self._get_script_path('result_collector.sh')
        cmd = [script_path, "-i", input_dir]
        
        # Add result type and format
        cmd.extend(["-t", result_type, "-f", output_format])
        
        # Run the collection
        start_time = time.time()
        result = self._run_command(cmd)
        duration = time.time() - start_time
        
        return {
            'input_dir': input_dir,
            'result_type': result_type,
            'format': output_format,
            'command': ' '.join(cmd),
            'duration': duration,
            'success': result.returncode == 0,
            'stdout': result.stdout if result.returncode == 0 else None,
            'stderr': result.stderr if result.returncode != 0 else None
        }
        
    def get_master_results(self) -> List[Dict[str, Any]]:
        """Read results from the master CSV file"""
        master_csv = os.path.join(self.base_dir, 'results', 'master_results.csv')
        
        if not os.path.exists(master_csv):
            return []
            
        results = []
        with open(master_csv, 'r') as f:
            # Skip comment lines
            lines = [line for line in f if not line.startswith('#')]
            
            if lines:
                reader = csv.DictReader(lines)
                for row in reader:
                    results.append(row)
                    
        return results
        
    def get_profiling_metadata(self) -> List[Dict[str, Any]]:
        """Read profiling metadata from CSV"""
        profiling_csv = os.path.join(self.base_dir, 'results', 'profiling_metadata.csv')
        
        if not os.path.exists(profiling_csv):
            return []
            
        results = []
        with open(profiling_csv, 'r') as f:
            # Skip comment lines
            lines = [line for line in f if not line.startswith('#')]
            
            if lines:
                reader = csv.DictReader(lines)
                for row in reader:
                    results.append(row)
                    
        return results


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description='AFSysBench Runner - Python integration for AlphaFold benchmarking (Updated for modular architecture)',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    # Global options
    parser.add_argument('-c', '--config', 
                       help='Configuration file path')
    parser.add_argument('-v', '--verbose', action='store_true',
                       help='Enable verbose logging')
    
    # Subcommands
    subparsers = parser.add_subparsers(dest='command', help='Command to run')
    
    # MSA command
    msa_parser = subparsers.add_parser('msa', help='Run MSA benchmark')
    msa_parser.add_argument('-i', '--input', required=True,
                           help='Input JSON/FASTA file')
    msa_parser.add_argument('-t', '--threads', nargs='+', type=int,
                           help='Thread counts to test')
    msa_parser.add_argument('-o', '--output', help='Output directory')
    
    # Inference command
    inf_parser = subparsers.add_parser('inference', help='Run inference benchmark')
    inf_parser.add_argument('-i', '--input', required=True,
                           help='Input JSON file with MSA data')
    inf_parser.add_argument('-t', '--threads', nargs='+', type=int,
                           help='Thread counts to test')
    inf_parser.add_argument('--nsys', action='store_true',
                           help='Enable NSYS profiling')
    inf_parser.add_argument('-m', '--models', type=int,
                           help='Number of models to generate')
    inf_parser.add_argument('-o', '--output', help='Output directory')
    
    # Batch command
    batch_parser = subparsers.add_parser('batch', help='Run batch benchmarks')
    batch_parser.add_argument('-i', '--input', required=True,
                             help='Input directory')
    batch_parser.add_argument('-s', '--stage', choices=['msa', 'inference'],
                             default='msa', help='Stage to run')
    batch_parser.add_argument('-t', '--threads', nargs='+', type=int,
                             help='Thread counts to test')
    batch_parser.add_argument('-n', '--name', help='Batch name')
    
    # Profiling command
    prof_parser = subparsers.add_parser('profile', help='Run with profiling')
    prof_parser.add_argument('-i', '--input', required=True,
                            help='Input file to profile')
    prof_parser.add_argument('-p', '--tool', required=True,
                            choices=['perf_stat', 'perf_record', 'nsys', 'uprof', 'memory_peak'],
                            help='Profiling tool to use')
    prof_parser.add_argument('-s', '--stage', required=True,
                            choices=['msa', 'inference'],
                            help='Stage to profile')
    prof_parser.add_argument('-t', '--threads', type=int,
                            help='Thread count')
    prof_parser.add_argument('-o', '--output', help='Output directory')
    
    # Collect results command
    collect_parser = subparsers.add_parser('collect', help='Collect and aggregate results')
    collect_parser.add_argument('-i', '--input', required=True,
                               help='Input directory with results')
    collect_parser.add_argument('-t', '--type', 
                               choices=['all', 'performance', 'profiling'],
                               default='all', help='Result type to collect')
    collect_parser.add_argument('-f', '--format',
                               choices=['csv', 'json', 'summary'],
                               default='csv', help='Output format')
    
    # Show results command
    show_parser = subparsers.add_parser('show', help='Show collected results')
    show_parser.add_argument('-t', '--type',
                            choices=['master', 'profiling'],
                            default='master',
                            help='Type of results to show')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
        
    # Some commands don't need configuration
    if args.command == 'show':
        # Create a minimal runner for show command
        class ShowRunner:
            def __init__(self):
                self.base_dir = os.path.dirname(os.path.abspath(__file__))
                
            def get_master_results(self):
                master_csv = os.path.join(self.base_dir, 'results', 'master_results.csv')
                if not os.path.exists(master_csv):
                    return []
                results = []
                with open(master_csv, 'r') as f:
                    lines = [line for line in f if not line.startswith('#')]
                    if lines:
                        reader = csv.DictReader(lines)
                        for row in reader:
                            results.append(row)
                return results
                
            def get_profiling_metadata(self):
                profiling_csv = os.path.join(self.base_dir, 'results', 'profiling_metadata.csv')
                if not os.path.exists(profiling_csv):
                    return []
                results = []
                with open(profiling_csv, 'r') as f:
                    lines = [line for line in f if not line.startswith('#')]
                    if lines:
                        reader = csv.DictReader(lines)
                        for row in reader:
                            results.append(row)
                return results
        
        runner = ShowRunner()
    else:
        # Load configuration for other commands
        if not args.config:
            print("Error: Configuration file (-c/--config) is required for this command")
            sys.exit(1)
            
        try:
            config = BenchmarkConfig.from_file(args.config)
            config.config_file = args.config  # Store config file path
        except Exception as e:
            print(f"Error loading config: {e}")
            sys.exit(1)
            
        # Create runner
        runner = AFBenchRunner(config)
    
    # Set logging level
    if args.verbose:
        runner.logger.setLevel(logging.DEBUG)
        
    # Execute command
    try:
        if args.command == 'msa':
            result = runner.run_msa_benchmark(
                args.input,
                args.threads,
                args.output
            )
            
            if result['success']:
                print(f"✓ MSA benchmark completed in {result['duration']:.2f}s")
            else:
                print(f"✗ MSA benchmark failed")
                if result['stderr']:
                    print(f"Error: {result['stderr']}")
                    
        elif args.command == 'inference':
            result = runner.run_inference_benchmark(
                args.input,
                args.threads,
                args.nsys,
                args.models,
                args.output
            )
            
            if result['success']:
                print(f"✓ Inference benchmark completed in {result['duration']:.2f}s")
            else:
                print(f"✗ Inference benchmark failed")
                if result['stderr']:
                    print(f"Error: {result['stderr']}")
                    
        elif args.command == 'batch':
            result = runner.run_batch(
                args.input,
                args.stage,
                args.threads,
                args.name
            )
            
            if result['success']:
                print(f"✓ Batch {args.stage} completed in {result['duration']:.2f}s")
            else:
                print(f"✗ Batch {args.stage} failed")
                if result['stderr']:
                    print(f"Error: {result['stderr']}")
                    
        elif args.command == 'profile':
            result = runner.run_profiling(
                args.input,
                args.tool,
                args.stage,
                args.threads,
                args.output
            )
            
            if result['success']:
                print(f"✓ {args.tool} profiling completed in {result['duration']:.2f}s")
            else:
                print(f"✗ {args.tool} profiling failed")
                if result['stderr']:
                    print(f"Error: {result['stderr']}")
                    
        elif args.command == 'collect':
            result = runner.collect_results(
                args.input,
                args.type,
                args.format
            )
            
            if result['success']:
                print(f"✓ Results collected in {result['duration']:.2f}s")
            else:
                print(f"✗ Result collection failed")
                if result['stderr']:
                    print(f"Error: {result['stderr']}")
                    
        elif args.command == 'show':
            if args.type == 'master':
                results = runner.get_master_results()
                print(f"Found {len(results)} entries in master results")
                
                # Show recent results
                if results:
                    recent = sorted(results, key=lambda x: x.get('timestamp', ''), reverse=True)[:10]
                    print("\nRecent results:")
                    for r in recent:
                        print(f"  - {r.get('timestamp')}: {r.get('input_file')} "
                              f"({r.get('stage')}, {r.get('threads')} threads) - "
                              f"{r.get('status')} in {r.get('duration_sec')}s")
                              
            elif args.type == 'profiling':
                results = runner.get_profiling_metadata()
                print(f"Found {len(results)} profiling runs")
                
                if results:
                    print("\nProfiling runs:")
                    for r in results:
                        print(f"  - {r.get('timestamp')}: {r.get('input_file')} "
                              f"({r.get('profiling_tool')}, {r.get('threads')} threads) - "
                              f"{r.get('status')}")
                    
    except KeyboardInterrupt:
        print("\nBenchmark interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()