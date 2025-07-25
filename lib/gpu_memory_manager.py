#!/usr/bin/env python3
"""
GPU Memory Manager for intelligent unified memory handling
"""

import subprocess
import json
import os
import logging
from pathlib import Path
from typing import Dict, Tuple, Optional

class GPUMemoryManager:
    """Manages GPU memory detection and unified memory decisions"""
    
    # Known memory requirements in MB (can be loaded from config)
    MEMORY_REQUIREMENTS = {
        '6QNR_subset_data': 24000,      # 24GB
        'promo_data': 8000,              # 8GB
        'promo_data_seed1': 8000,        # 8GB
        '2pv7_data': 4000,               # 4GB
        '1yy9_data': 6000,               # 6GB
        'rcsb_pdb_7rce_data': 6000,      # 6GB
    }
    
    def __init__(self, safety_factor: float = 1.2):
        self.safety_factor = safety_factor
        self.logger = logging.getLogger(__name__)
        self._gpu_memory_cache = None
        
    def get_gpu_memory_mb(self) -> int:
        """Get GPU memory capacity in MB"""
        if self._gpu_memory_cache is not None:
            return self._gpu_memory_cache
            
        try:
            # Try nvidia-smi
            result = subprocess.run(
                ['nvidia-smi', '--query-gpu=memory.total', '--format=csv,noheader,nounits'],
                capture_output=True, text=True
            )
            if result.returncode == 0:
                self._gpu_memory_cache = int(result.stdout.strip().split('\n')[0])
                return self._gpu_memory_cache
        except (subprocess.SubprocessError, ValueError):
            pass
            
        # Try docker if nvidia-smi failed
        try:
            result = subprocess.run(
                ['docker', 'run', '--rm', '--gpus', 'all', 
                 'nvidia/cuda:11.8.0-base-ubuntu20.04',
                 'nvidia-smi', '--query-gpu=memory.total', '--format=csv,noheader,nounits'],
                capture_output=True, text=True
            )
            if result.returncode == 0:
                self._gpu_memory_cache = int(result.stdout.strip().split('\n')[0])
                return self._gpu_memory_cache
        except (subprocess.SubprocessError, ValueError):
            pass
            
        self.logger.warning("Unable to detect GPU memory")
        return 0
        
    def estimate_memory_requirement(self, input_file: str) -> int:
        """Estimate memory requirement for input file in MB"""
        base_name = Path(input_file).stem
        
        # Check known requirements
        if base_name in self.MEMORY_REQUIREMENTS:
            return self.MEMORY_REQUIREMENTS[base_name]
            
        # Estimate based on file size
        try:
            file_size_mb = os.path.getsize(input_file) / (1024 * 1024)
            # Rough estimate: 1000x file size
            return int(file_size_mb * 1000)
        except OSError:
            return 8000  # Default 8GB
            
    def needs_unified_memory(self, input_file: str) -> Tuple[bool, Dict[str, int]]:
        """
        Check if unified memory is needed
        Returns: (needs_unified, {gpu_mem, required_mem, required_with_safety})
        """
        gpu_mem = self.get_gpu_memory_mb()
        required_mem = self.estimate_memory_requirement(input_file)
        required_with_safety = int(required_mem * self.safety_factor)
        
        info = {
            'gpu_memory_mb': gpu_mem,
            'required_memory_mb': required_mem,
            'required_with_safety_mb': required_with_safety,
            'safety_factor': self.safety_factor
        }
        
        if gpu_mem == 0:
            # Can't detect GPU memory, don't use unified memory
            return False, info
            
        needs_unified = required_with_safety > gpu_mem
        
        if needs_unified:
            self.logger.info(
                f"Unified memory required: {required_with_safety}MB > {gpu_mem}MB GPU"
            )
        else:
            self.logger.info(
                f"Unified memory not needed: {required_with_safety}MB <= {gpu_mem}MB GPU"
            )
            
        return needs_unified, info
        
    def get_unified_memory_env(self) -> Dict[str, str]:
        """Get environment variables for unified memory"""
        return {
            'XLA_PYTHON_CLIENT_PREALLOCATE': 'false',
            'TF_FORCE_UNIFIED_MEMORY': 'true',
            'XLA_CLIENT_MEM_FRACTION': '3.2'
        }
        
    def check_oom_error(self, log_file: str) -> bool:
        """Check if log file contains OOM errors"""
        oom_patterns = [
            'CUDA_ERROR_OUT_OF_MEMORY',
            'CUDA out of memory',
            'OOM when allocating tensor',
            'ResourceExhaustedError',
            'failed to allocate.*memory',
            'GPU memory allocation failed',
        ]
        
        try:
            with open(log_file, 'r') as f:
                content = f.read()
                for pattern in oom_patterns:
                    if pattern in content:
                        return True
        except IOError:
            pass
            
        return False


# Configuration file for memory requirements
MEMORY_CONFIG_TEMPLATE = """# GPU Memory Requirements Configuration
# Memory requirements in MB for different input files
# Can be updated based on empirical testing

memory_requirements:
  # RNA structures (large)
  6QNR_subset_data: 24000      # 24GB - requires unified memory on most GPUs
  7k00_subset_data: 28000      # 28GB - requires unified memory
  
  # Protein structures (medium)
  promo_data: 8000             # 8GB
  promo_data_seed1: 8000       # 8GB
  1yy9_data: 6000              # 6GB
  rcsb_pdb_7rce_data: 6000     # 6GB
  
  # Protein structures (small)
  2pv7_data: 4000              # 4GB
  2PV7: 3000                   # 3GB (MSA stage)
  
# Safety factor for memory estimation (1.2 = 20% buffer)
safety_factor: 1.2

# Retry configuration
retry_on_oom: true
max_retry_attempts: 2
"""