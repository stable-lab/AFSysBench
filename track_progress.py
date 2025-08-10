#!/usr/bin/env python3
"""
Track progress of statistical benchmarks and provide real-time status
"""

import time
import os
import subprocess
import csv
from datetime import datetime
import re

def get_latest_stats_dir():
    """Find the latest statistical results directory"""
    dirs = [d for d in os.listdir('.') if d.startswith('statistical_results_')]
    if not dirs:
        return None
    return max(dirs)

def check_docker_activity():
    """Check if AlphaFold Docker containers are running"""
    try:
        result = subprocess.run(['docker', 'ps'], capture_output=True, text=True)
        alphafold_containers = [line for line in result.stdout.split('\n') if 'alphafold' in line]
        return len(alphafold_containers)
    except:
        return 0

def parse_log_file(log_file):
    """Parse the statistical run log to extract current progress"""
    if not os.path.exists(log_file):
        return {"status": "Not started", "current_test": "N/A", "progress": "0/0"}
    
    with open(log_file, 'r') as f:
        content = f.read()
    
    # Extract current test information
    lines = content.split('\n')
    current_test = "N/A"
    stage = "Unknown"
    
    for line in reversed(lines):
        if "🔄 Iteration" in line and "threads" in line:
            # Extract test details from line like: "🔄 Iteration 2: 2PV7.json with 4 threads"
            match = re.search(r'Iteration (\d+): (\w+\.json) with (\d+) threads', line)
            if match:
                iteration, sample, threads = match.groups()
                current_test = f"{sample} ({threads}t, iter {iteration})"
                break
        elif "Processing MSA input:" in line:
            stage = "MSA"
        elif "Processing Inference input:" in line:
            stage = "Inference"
    
    # Count completed vs total
    completed_lines = content.count("✅ Completed in")
    failed_lines = content.count("❌ Failed after")
    
    return {
        "status": "Running" if "🔄 Iteration" in content else "Completed",
        "stage": stage,
        "current_test": current_test,
        "completed": completed_lines,
        "failed": failed_lines,
        "total_lines": len(lines)
    }

def parse_csv_results(stats_dir):
    """Parse the CSV results to get timing statistics"""
    if not stats_dir:
        return {}
    
    csv_file = os.path.join(stats_dir, 'statistical_summary.csv')
    if not os.path.exists(csv_file):
        return {}
    
    results = {}
    try:
        with open(csv_file, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                key = f"{row['stage']}_{row['input_file']}_{row['threads']}t"
                if key not in results:
                    results[key] = []
                if row['status'] == 'SUCCESS':
                    results[key].append(float(row['duration_sec']))
    except:
        pass
    
    return results

def calculate_statistics(timings):
    """Calculate basic statistics for timing data"""
    if not timings:
        return {}
    
    import statistics
    return {
        'count': len(timings),
        'mean': statistics.mean(timings),
        'median': statistics.median(timings),
        'stdev': statistics.stdev(timings) if len(timings) > 1 else 0,
        'min': min(timings),
        'max': max(timings),
        'cv_percent': (statistics.stdev(timings) / statistics.mean(timings) * 100) if len(timings) > 1 else 0
    }

def format_duration(seconds):
    """Format duration in human readable format"""
    if seconds < 60:
        return f"{seconds:.1f}s"
    elif seconds < 3600:
        return f"{seconds/60:.1f}m"
    else:
        return f"{seconds/3600:.1f}h"

def print_status():
    """Print current status of statistical benchmarks"""
    print(f"\n🔍 AFSysBench Statistical Tracking - {datetime.now().strftime('%H:%M:%S')}")
    print("=" * 70)
    
    # Check process status
    try:
        result = subprocess.run(['pgrep', '-f', 'run_statistical_benchmarks'], 
                              capture_output=True, text=True)
        process_running = bool(result.stdout.strip())
    except:
        process_running = False
    
    print(f"📊 Process Status: {'🟢 RUNNING' if process_running else '🔴 STOPPED'}")
    
    # Check Docker activity
    docker_count = check_docker_activity()
    print(f"🐳 Docker Containers: {docker_count} AlphaFold containers running")
    
    # Parse log progress
    log_progress = parse_log_file('statistical_run_full.log')
    print(f"📈 Stage: {log_progress['stage']}")
    print(f"🔄 Current Test: {log_progress['current_test']}")
    print(f"✅ Completed: {log_progress['completed']} | ❌ Failed: {log_progress['failed']}")
    
    # Parse CSV results
    stats_dir = get_latest_stats_dir()
    if stats_dir:
        print(f"📁 Results Directory: {stats_dir}")
        csv_results = parse_csv_results(stats_dir)
        
        if csv_results:
            print(f"\n📊 CURRENT TIMING STATISTICS:")
            print("-" * 70)
            print(f"{'Test Configuration':<25} {'Count':<6} {'Mean':<12} {'StdDev':<10} {'CV%':<8}")
            print("-" * 70)
            
            for config, timings in csv_results.items():
                stats = calculate_statistics(timings)
                if stats:
                    mean_str = format_duration(stats['mean'])
                    stdev_str = format_duration(stats['stdev'])
                    
                    print(f"{config:<25} {stats['count']:<6} {mean_str:<12} {stdev_str:<10} {stats['cv_percent']:<8.1f}")
                    
                    # Flag if timing suggests real computation vs validation
                    if stats['mean'] > 60:  # More than 1 minute suggests real computation
                        status_icon = "🎯"
                    elif stats['mean'] > 10:  # 10+ seconds might be partial
                        status_icon = "⚠️"
                    else:  # <10 seconds likely just validation
                        status_icon = "❌"
                    
                    print(f"    {status_icon} {'Real computation' if stats['mean'] > 60 else 'Validation only' if stats['mean'] < 10 else 'Partial run'}")
    
    print("\n" + "=" * 70)

if __name__ == "__main__":
    print_status()