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
echo "🔍 Running Built-in Statistical Analysis..."
echo "============================================="

# Create analysis output directory
ANALYSIS_DIR="$STATS_DIR/analysis_results"
mkdir -p "$ANALYSIS_DIR"

# Function to calculate basic statistics using awk
calculate_stats() {
    local stage="$1"
    local input_file="$2"
    local threads="$3"
    
    # Extract successful runs for this configuration
    local values=$(grep "^$stage,$input_file,$threads," "$STATS_FILE" | grep "SUCCESS" | cut -d',' -f5)
    
    if [ -z "$values" ]; then
        echo "N/A N/A N/A N/A 0 N/A"
        return
    fi
    
    # Calculate statistics using awk
    echo "$values" | awk '
    {
        sum += $1
        values[NR] = $1
        count = NR
    }
    END {
        if (count == 0) {
            print "N/A N/A N/A N/A 0 N/A"
            exit
        }
        
        mean = sum / count
        
        # Calculate standard deviation
        sumsq = 0
        for (i = 1; i <= count; i++) {
            sumsq += (values[i] - mean)^2
        }
        std = sqrt(sumsq / count)
        
        # Find min and max
        min = values[1]
        max = values[1]
        for (i = 1; i <= count; i++) {
            if (values[i] < min) min = values[i]
            if (values[i] > max) max = values[i]
        }
        
        # Calculate coefficient of variation
        cv = (mean > 0) ? (std / mean) * 100 : 0
        
        printf "%.2f %.3f %.2f %.2f %d %.1f\n", mean, std, min, max, count, cv
    }'
}

# Generate detailed statistics report
STATS_REPORT="$ANALYSIS_DIR/detailed_statistics.txt"
echo "Generating detailed statistics report..."

cat > "$STATS_REPORT" << 'EOF'
AFSysBench Basic Statistical Analysis Report
===========================================

EOF

echo "Analysis Date: $(date)" >> "$STATS_REPORT"
echo "" >> "$STATS_REPORT"

# Get unique stages, input files, and thread counts
STAGES=$(tail -n +2 "$STATS_FILE" | cut -d',' -f1 | sort -u)
INPUT_FILES=$(tail -n +2 "$STATS_FILE" | cut -d',' -f2 | sort -u)
THREAD_COUNTS=$(tail -n +2 "$STATS_FILE" | cut -d',' -f3 | sort -nu)

echo "Summary of Test Configurations:" >> "$STATS_REPORT"
echo "  Stages: $(echo $STAGES | tr '\n' ' ')" >> "$STATS_REPORT"
echo "  Input Files: $(echo $INPUT_FILES | tr '\n' ' ')" >> "$STATS_REPORT"
echo "  Thread Counts: $(echo $THREAD_COUNTS | tr '\n' ' ')" >> "$STATS_REPORT"
echo "" >> "$STATS_REPORT"
echo "" >> "$STATS_REPORT"

# Analyze each stage
for stage in $STAGES; do
    echo "${stage^^} STAGE ANALYSIS" >> "$STATS_REPORT"
    echo "================================================" >> "$STATS_REPORT"
    echo "" >> "$STATS_REPORT"
    
    printf "%-25s %-8s %-10s %-10s %-10s %-10s %-6s %-7s \n" \
           "Input File" "Threads" "Mean(s)" "Std(s)" "Min(s)" "Max(s)" "Runs" "CV(%)" >> "$STATS_REPORT"
    echo "-----------------------------------------------------------------------------------------------" >> "$STATS_REPORT"
    
    # Collect CV values for stability analysis
    cv_values=()
    best_cv=999999
    worst_cv=0
    best_config=""
    worst_config=""
    
    for input_file in $INPUT_FILES; do
        for threads in $THREAD_COUNTS; do
            # Check if this combination exists in the data
            if grep -q "^$stage,$input_file,$threads," "$STATS_FILE"; then
                stats_result=$(calculate_stats "$stage" "$input_file" "$threads")
                read mean std min max count cv <<< "$stats_result"
                
                if [ "$cv" != "N/A" ]; then
                    cv_values+=($cv)
                    
                    # Track best and worst CV
                    if (( $(echo "$cv < $best_cv" | bc -l) )); then
                        best_cv=$cv
                        best_config="$input_file ($threads threads)"
                    fi
                    
                    if (( $(echo "$cv > $worst_cv" | bc -l) )); then
                        worst_cv=$cv
                        worst_config="$input_file ($threads threads)"
                    fi
                fi
                
                printf "%-25s %-8s %-10s %-10s %-10s %-10s %-6s %-7s \n" \
                       "$input_file" "$threads" "$mean" "$std" "$min" "$max" "$count" "$cv" >> "$STATS_REPORT"
            fi
        done
    done
    
    echo "" >> "$STATS_REPORT"
    echo "Stability Analysis:" >> "$STATS_REPORT"
    
    # Calculate average CV
    if [ ${#cv_values[@]} -gt 0 ]; then
        avg_cv=$(printf '%s\n' "${cv_values[@]}" | awk '{sum+=$1} END {print sum/NR}')
        printf "  Average CV: %.1f%%\n" "$avg_cv" >> "$STATS_REPORT"
        
        if [ "$best_config" != "" ]; then
            printf "  Most Stable: %s (CV: %.1f%%)\n" "$best_config" "$best_cv" >> "$STATS_REPORT"
        fi
        
        if [ "$worst_config" != "" ]; then
            printf "  Least Stable: %s (CV: %.1f%%)\n" "$worst_config" "$worst_cv" >> "$STATS_REPORT"
        fi
    fi
    
    echo "" >> "$STATS_REPORT"
done

echo ""
echo "✅ Statistical Analysis Complete!"
echo "================================="
echo "📁 Raw data: $STATS_FILE"
echo "📊 Analysis report: $STATS_REPORT"
echo ""
echo "🔍 Quick Performance Summary:"

# Display brief summary to console
echo "  Total runs: $total_runs"
echo "  Successful: $successful_runs"
echo "  Failed: $failed_runs"

if [ $successful_runs -gt 0 ]; then
    echo ""
    echo "📋 Analysis files generated:"
    echo "  • $STATS_REPORT"
    echo ""
    echo "To view the full analysis:"
    echo "  cat $STATS_REPORT"
else
    echo ""
    echo "⚠️  No successful runs found for analysis"
fi