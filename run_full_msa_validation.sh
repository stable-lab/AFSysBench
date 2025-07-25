#!/bin/bash
# Full MSA Benchmark Validation Script for AFSysBench

set -e

echo "🧬 Starting Full MSA Benchmark Validation"
echo "=========================================="

# MSA inputs to test
MSA_INPUTS=("2PV7.json" "6QNR_subset.json" "promo.json" "rcsb_pdb_1YY9.json" "rcsb_pdb_7RCE.json")

# Create results tracking
RESULTS_FILE="validation_msa_results.txt"
echo "MSA Validation Results - $(date)" > $RESULTS_FILE
echo "=================================" >> $RESULTS_FILE

for input in "${MSA_INPUTS[@]}"; do
    echo ""
    echo "🔬 Running MSA benchmark for $input..."
    
    start_time=$(date +%s)
    
    if python runner -c validation_system.config msa -i "$input" -t 4; then
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        echo "✅ $input: SUCCESS ($duration seconds)" | tee -a $RESULTS_FILE
    else
        echo "❌ $input: FAILED" | tee -a $RESULTS_FILE
    fi
done

echo ""
echo "📊 MSA Validation Summary:"
cat $RESULTS_FILE

echo ""
echo "✅ Full MSA validation completed!"