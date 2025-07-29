#!/bin/bash
# Statistical Benchmark Runner - Run each configuration 5 times for deviation analysis

set -e

echo "🧬 Starting Statistical AFSysBench (5 iterations each)"
echo "======================================================"

# Configuration
CONFIG_FILE="myenv.config"
ITERATIONS=5

# Input files
MSA_INPUTS=("2PV7.json" "promo.json" "rcsb_pdb_1YY9.json" "rcsb_pdb_7RCE.json")
INFERENCE_INPUTS=("1yy9_data.json" "2pv7_data.json" "promo_data.json" "rcsb_pdb_7rce_data.json")

# Thread configurations
THREADS=(1 2 4 6 8)

# Create results tracking
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
STATS_DIR="statistical_results_$TIMESTAMP"
mkdir -p "$STATS_DIR"

STATS_FILE="$STATS_DIR/statistical_summary.csv"
echo "stage,input_file,threads,iteration,duration_sec,status" > "$STATS_FILE"

echo "📊 Results will be saved to: $STATS_DIR"
echo ""

# Function to run benchmark and extract timing
run_single_benchmark() {
    local stage=$1
    local input_file=$2
    local thread_count=$3
    local iteration=$4
    
    echo "  🔄 Iteration $iteration: $input_file with $thread_count threads"
    
    start_time=$(date +%s.%N)
    
    if python runner -c "$CONFIG_FILE" "$stage" -i "$input_file" -t "$thread_count" > /dev/null 2>&1; then
        end_time=$(date +%s.%N)
        duration=$(echo "$end_time - $start_time" | bc -l)
        status="SUCCESS"
        echo "    ✅ Completed in ${duration}s"
    else
        end_time=$(date +%s.%N)
        duration=$(echo "$end_time - $start_time" | bc -l)
        status="FAILED"
        echo "    ❌ Failed after ${duration}s"
    fi
    
    # Record to CSV
    echo "$stage,$input_file,$thread_count,$iteration,$duration,$status" >> "$STATS_FILE"
}

# Run MSA benchmarks
echo "🔬 Starting MSA Statistical Benchmarks"
echo "======================================="

for input in "${MSA_INPUTS[@]}"; do
    echo ""
    echo "📁 Processing MSA input: $input"
    
    for threads in "${THREADS[@]}"; do
        echo "  🧵 Testing with $threads threads ($ITERATIONS iterations)"
        
        for i in $(seq 1 $ITERATIONS); do
            run_single_benchmark "msa" "$input" "$threads" "$i"
        done
    done
done

echo ""
echo "🔬 Starting Inference Statistical Benchmarks" 
echo "============================================="

for input in "${INFERENCE_INPUTS[@]}"; do
    echo ""
    echo "📁 Processing Inference input: $input"
    
    for threads in "${THREADS[@]}"; do
        echo "  🧵 Testing with $threads threads ($ITERATIONS iterations)"
        
        for i in $(seq 1 $ITERATIONS); do
            run_single_benchmark "inference" "$input" "$threads" "$i"
        done
    done
done

echo ""
echo "📊 Statistical Analysis Complete!"
echo "================================="
echo "Raw data saved to: $STATS_FILE"
echo ""
echo "🔍 Quick summary of collected data:"
total_runs=$(tail -n +2 "$STATS_FILE" | wc -l)
successful_runs=$(tail -n +2 "$STATS_FILE" | grep "SUCCESS" | wc -l)
failed_runs=$(tail -n +2 "$STATS_FILE" | grep "FAILED" | wc -l)

echo "  Total runs: $total_runs"
echo "  Successful: $successful_runs"
echo "  Failed: $failed_runs"
echo ""
echo "Next step: Run the statistical analysis script to calculate deviations"
echo "  python analyze_statistical_data.py $STATS_FILE"