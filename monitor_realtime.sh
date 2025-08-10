#!/bin/bash
# Real-time monitoring script for statistical benchmarks

echo "🔍 Real-time AFSysBench Statistical Monitor"
echo "=========================================="

# Function to check timing patterns
check_timing_pattern() {
    if [ -f "statistical_run_full.log" ]; then
        echo ""
        echo "⏱️  Recent Completion Times:"
        grep "✅ Completed in" statistical_run_full.log | tail -5 | while read line; do
            time=$(echo "$line" | grep -o '[0-9.]*s')
            test_info=$(echo "$line" | cut -d':' -f2- | cut -d'✅' -f1)
            echo "   $test_info: $time"
        done
    fi
}

# Function to monitor Docker resource usage  
monitor_docker() {
    if docker ps | grep -q alphafold; then
        echo ""
        echo "🐳 Docker Resource Usage:"
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep alphafold
    fi
}

# Function to check expected vs actual runtime
analyze_runtime() {
    if [ -f "statistical_results_20250729_052507/statistical_summary.csv" ]; then
        echo ""
        echo "📊 Runtime Analysis:"
        python3 -c "
import csv
import statistics

try:
    with open('statistical_results_20250729_052507/statistical_summary.csv', 'r') as f:
        reader = csv.DictReader(f)
        data = list(reader)
    
    if data:
        successful = [float(row['duration_sec']) for row in data if row['status'] == 'SUCCESS']
        if successful:
            mean_time = statistics.mean(successful)
            print(f'   Completed runs: {len(successful)}')
            print(f'   Average time: {mean_time:.1f}s ({mean_time/60:.1f}m)')
            if mean_time > 300:  # 5+ minutes
                print('   ✅ Real computation detected (>5min per run)')
            elif mean_time > 60:  # 1+ minute
                print('   ⚠️  Partial computation (1-5min per run)')
            else:
                print('   ❌ Only validation detected (<1min per run)')
except:
    print('   No data available yet')
"
    fi
}

# Main monitoring loop
while true; do
    clear
    echo "🔍 AFSysBench Statistical Monitor - $(date '+%H:%M:%S')"
    echo "=================================================="
    
    # Check if process is running
    if pgrep -f "run_statistical_benchmarks" > /dev/null; then
        echo "📊 Status: 🟢 RUNNING"
    else
        echo "📊 Status: 🔴 STOPPED"
        break
    fi
    
    # Check Docker containers
    docker_count=$(docker ps | grep -c alphafold)
    echo "🐳 AlphaFold Containers: $docker_count running"
    
    # Show current progress
    if [ -f "statistical_run_full.log" ]; then
        current_test=$(tail -20 statistical_run_full.log | grep "🔄 Iteration" | tail -1)
        if [ -n "$current_test" ]; then
            echo "🔄 Current: $current_test"
        fi
        
        completed=$(grep -c "✅ Completed in" statistical_run_full.log)
        failed=$(grep -c "❌ Failed after" statistical_run_full.log)
        echo "✅ Completed: $completed | ❌ Failed: $failed"
    fi
    
    check_timing_pattern
    monitor_docker
    analyze_runtime
    
    echo ""
    echo "Press Ctrl+C to stop monitoring..."
    sleep 30
done