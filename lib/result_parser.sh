#!/bin/bash

# Result parsing and CSV generation utilities for AlphaFold benchmarking

# Determine run purpose based on profiling configuration
determine_run_purpose() {
    if [ "$PROFILING_ENABLED" = true ] && [ -n "$PROFILING_TOOL" ]; then
        echo "profiling"
    else
        echo "performance"
    fi
}

# Generate experiment ID
generate_experiment_id() {
    local system_name=$1
    local input_name=$2
    local timestamp=$3
    
    echo "${system_name}_${input_name}_${timestamp}"
}

# Create CSV header with metadata
create_csv_header() {
    local csv_file=$1
    local run_type=$2  # "msa" or "inference"
    local metadata_fields=$3  # Additional fields specific to run type
    
    # Add metadata as comments
    {
        echo "# AlphaFold Benchmark Results"
        echo "# Generated: $(date)"
        echo "# System: $SYSTEM_NAME ($SYSTEM_TYPE)"
        echo "# Docker Image: $DOCKER_IMAGE"
        echo "# Run Type: $run_type"
        echo "# Run Purpose: $(determine_run_purpose)"
        [ -n "$PROFILING_TOOL" ] && echo "# Profiling Tool: $PROFILING_TOOL"
        echo "# Config Hash: $(get_config_hash)"
        echo "#"
    } > "$csv_file"
    
    # Standard fields
    local header="experiment_id,system_name,timestamp,input_file,stage,threads,duration_sec,status,run_purpose"
    
    # Add run-type specific fields
    if [ "$run_type" = "msa" ]; then
        header+=",sequences_found,peak_memory_mb"
    elif [ "$run_type" = "inference" ]; then
        header+=",model_name,gpu_utilization,peak_memory_mb"
    fi
    
    # Add custom metadata fields if provided
    if [ -n "$metadata_fields" ]; then
        header+=",$metadata_fields"
    fi
    
    # Add profiling fields
    header+=",config_hash,profiling_flags,run_metadata"
    
    echo "$header" >> "$csv_file"
}

# Build CSV line for results
build_csv_line() {
    local experiment_id=$1
    local system_name=$2
    local timestamp=$3
    local input_file=$4
    local stage=$5
    local threads=$6
    local duration=$7
    local status=$8
    local run_purpose=$9
    shift 9
    local additional_data=$*
    
    local csv_line="$experiment_id,$system_name,$timestamp,$input_file,$stage,$threads,$duration,$status,$run_purpose"
    
    # Add additional data if provided
    if [ -n "$additional_data" ]; then
        csv_line+=",$additional_data"
    fi
    
    # Add metadata
    local config_hash=$(get_config_hash)
    local profiling_flags=""
    if [ "$PROFILING_ENABLED" = true ]; then
        profiling_flags="$PROFILING_TOOL"
    fi
    
    # Create JSON metadata
    local run_metadata=$(create_run_metadata)
    
    csv_line+=",$config_hash,$profiling_flags,$run_metadata"
    
    echo "$csv_line"
}

# Create JSON metadata for run
create_run_metadata() {
    local metadata="{"
    metadata+="\"hostname\":\"$(hostname)\","
    metadata+="\"kernel\":\"$(uname -r)\","
    metadata+="\"cpu_model\":\"$(lscpu | grep "Model name" | cut -d: -f2 | xargs)\","
    metadata+="\"memory_total_gb\":\"$(free -g | awk '/^Mem:/{print $2}')\","
    metadata+="\"docker_version\":\"$(docker --version | awk '{print $3}' | tr -d ',')\""
    
    if [ "$SYSTEM_TYPE" = "gpu" ]; then
        local gpu_info=$(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader | head -1)
        metadata+=",\"gpu_model\":\"$(echo $gpu_info | cut -d, -f1 | xargs)\","
        metadata+="\"gpu_driver\":\"$(echo $gpu_info | cut -d, -f2 | xargs)\""
    fi
    
    metadata+="}"
    
    # Escape for CSV
    echo "$metadata" | sed 's/"/\\"/g'
}

# Parse MSA results from output
parse_msa_results() {
    local output_dir=$1
    local log_file=$2
    
    local sequences_found=0
    local status="failed"
    
    # Check for AlphaFold 3 MSA outputs (JSON format)
    if find "$output_dir" -name "*data.json" -type f 2>/dev/null | grep -q .; then
        status="success"
        
        # Try to extract sequence count from log (AlphaFold 3 format)
        if [ -f "$log_file" ]; then
            # Look for "found X unpaired sequences, Y paired sequences" pattern
            local unpaired=$(grep -i "found [0-9]* unpaired sequences" "$log_file" | grep -oE '[0-9]+' | tail -1)
            local paired=$(grep -i "[0-9]* paired sequences" "$log_file" | grep -oE '[0-9]+' | tail -1)
            
            if [ -n "$unpaired" ] && [ -n "$paired" ]; then
                sequences_found=$((unpaired + paired))
            elif [ -n "$unpaired" ]; then
                sequences_found=$unpaired
            else
                # Fallback: look for general "sequences found" pattern
                local seq_count=$(grep -i "sequences found" "$log_file" | grep -oE '[0-9]+' | tail -1)
                if [ -n "$seq_count" ]; then
                    sequences_found=$seq_count
                fi
            fi
        fi
    # Check for legacy AlphaFold 2 format
    elif [ -f "$output_dir/msas/bfd_uniclust_hits.pkl" ] || [ -f "$output_dir/msas/msa.pkl" ]; then
        status="success"
        
        # Try to extract sequence count from log (legacy format)
        if [ -f "$log_file" ]; then
            local seq_count=$(grep -i "sequences found" "$log_file" | grep -oE '[0-9]+' | tail -1)
            if [ -n "$seq_count" ]; then
                sequences_found=$seq_count
            fi
        fi
    fi
    
    echo "status=$status,sequences_found=$sequences_found"
}

# Parse inference results from output
parse_inference_results() {
    local output_dir=$1
    local log_file=$2
    local model_name=$3
    
    local status="failed"
    local confidence_score=0
    
    # Check if structure PDB exists
    if ls "$output_dir"/*_model_*.pdb &>/dev/null; then
        status="success"
        
        # Try to extract confidence score
        if [ -f "$log_file" ]; then
            local score=$(grep -i "confidence" "$log_file" | grep -oE '[0-9]+\.[0-9]+' | tail -1)
            if [ -n "$score" ]; then
                confidence_score=$score
            fi
        fi
    fi
    
    echo "status=$status,confidence_score=$confidence_score"
}

# Extract timing information from logs
extract_timing() {
    local start_time=$1
    local end_time=$2
    
    if [ -z "$start_time" ] || [ -z "$end_time" ]; then
        echo "0"
        return
    fi
    
    echo "$end_time - $start_time" | bc
}

# Generate summary report
generate_summary() {
    local result_dir=$1
    local run_type=$2
    local csv_file=$3
    local summary_file=$4
    
    {
        echo "=== AlphaFold Benchmark Summary ==="
        echo "Generated: $(date)"
        echo "System: $SYSTEM_NAME ($SYSTEM_TYPE)"
        echo "Run Type: $run_type"
        echo "Run Purpose: $(determine_run_purpose)"
        echo ""
        
        # Performance summary
        echo "Performance Results:"
        if [ -f "$csv_file" ]; then
            # Find best result
            local best_result=$(tail -n +2 "$csv_file" | grep ",success," | sort -t',' -k7 -n | head -1)
            if [ -n "$best_result" ]; then
                local best_threads=$(echo "$best_result" | cut -d',' -f6)
                local best_time=$(echo "$best_result" | cut -d',' -f7)
                echo "  Best Performance: ${best_time}s with $best_threads threads"
            fi
            
            # Count successful/failed runs
            local total_runs=$(tail -n +2 "$csv_file" | wc -l)
            local successful_runs=$(tail -n +2 "$csv_file" | grep -c ",success,")
            local failed_runs=$((total_runs - successful_runs))
            echo "  Total Runs: $total_runs"
            echo "  Successful: $successful_runs"
            echo "  Failed: $failed_runs"
        fi
        
        echo ""
        
        # System monitoring summary
        if [ -d "$result_dir/logs" ]; then
            create_monitoring_summary "$result_dir/logs" /dev/stdout
        fi
        
    } > "$summary_file"
}

# Find best performance result
find_best_result() {
    local csv_file=$1
    local metric_column=${2:-7}  # Default to duration column
    
    if [ ! -f "$csv_file" ]; then
        echo "No results found"
        return
    fi
    
    # Skip header and find minimum duration for successful runs
    tail -n +2 "$csv_file" | grep ",success," | sort -t',' -k${metric_column} -n | head -1
}

# Validate results directory structure
validate_results() {
    local output_dir=$1
    local run_type=$2
    
    local errors=0
    
    if [ "$run_type" = "msa" ]; then
        # Simple check: MSA succeeds if *_data.json file exists anywhere in output
        if find "$output_dir" -name "*_data.json" -type f 2>/dev/null | grep -q .; then
            echo "✓ MSA Success: Found data JSON file" >&2
        else
            echo "Error: MSA data JSON file not found" >&2
            ((errors++))
        fi
        
    elif [ "$run_type" = "inference" ]; then
        # Check for inference outputs
        local pdb_count=$(find "$output_dir" -name "*.pdb" 2>/dev/null | wc -l)
        if [ $pdb_count -eq 0 ]; then
            echo "Error: No PDB files found" >&2
            ((errors++))
        fi
    fi
    
    return $errors
}

# Aggregate results from multiple CSVs
aggregate_results() {
    local output_csv=$1
    shift
    local input_csvs=$*
    
    # Create header from first file
    local first_file=""
    for csv in $input_csvs; do
        if [ -f "$csv" ]; then
            first_file=$csv
            break
        fi
    done
    
    if [ -z "$first_file" ]; then
        echo "Error: No input CSV files found" >&2
        return 1
    fi
    
    # Copy header
    grep "^#\|^[a-zA-Z]" "$first_file" > "$output_csv"
    
    # Append data from all files
    for csv in $input_csvs; do
        if [ -f "$csv" ]; then
            tail -n +2 "$csv" | grep -v "^#\|^[a-zA-Z]" >> "$output_csv"
        fi
    done
    
    echo "Aggregated $(tail -n +2 "$output_csv" | wc -l) results into $output_csv"
}

# Create profiling results CSV entry
create_profiling_csv_entry() {
    local experiment_id=$1
    local profiling_type=$2
    local metric_name=$3
    local metric_value=$4
    local metric_unit=$5
    local profiling_metadata=$6
    
    local csv_line="$experiment_id,$SYSTEM_NAME,$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    csv_line+=",$profiling_type,$metric_name,$metric_value,$metric_unit"
    csv_line+=",$profiling_metadata"
    
    echo "$csv_line"
}

# Parse profiling tool output
parse_profiling_output() {
    local profiling_tool=$1
    local output_file=$2
    local experiment_id=$3
    local profiling_csv=$4
    
    case "$profiling_tool" in
        perf_stat)
            parse_perf_stat_output "$output_file" "$experiment_id" "$profiling_csv"
            ;;
        perf_record)
            parse_perf_record_output "$output_file" "$experiment_id" "$profiling_csv"
            ;;
        memory_peak)
            parse_memory_peak_output "$output_file" "$experiment_id" "$profiling_csv"
            ;;
        uprof)
            parse_uprof_output "$output_file" "$experiment_id" "$profiling_csv"
            ;;
        nsys)
            # NSYS outputs are file-based, just record metadata
            echo "$experiment_id,nsys,output_file,$output_file,path,{}" >> "$profiling_csv"
            ;;
    esac
}

# Helper function to escape CSV fields
escape_csv_field() {
    local field=$1
    # If field contains comma, quote, or newline, wrap in quotes and escape quotes
    if [[ "$field" =~ [,\"\n] ]]; then
        field="\"$(echo "$field" | sed 's/"/\\"/g')\""
    fi
    echo "$field"
}

# Initialize master CSV file
init_master_csv() {
    local csv_file=$1
    
    if [ ! -f "$csv_file" ]; then
        mkdir -p "$(dirname "$csv_file")"
        {
            echo "# AlphaFold Master Results Database"
            echo "# Created: $(date)"
            echo "experiment_id,system_name,timestamp,input_file,stage,threads,duration_sec,status,run_purpose,config_hash,profiling_flags,run_metadata"
        } > "$csv_file"
    fi
}

# Initialize profiling metadata CSV
init_profiling_csv() {
    local csv_file=$1
    
    if [ ! -f "$csv_file" ]; then
        mkdir -p "$(dirname "$csv_file")"
        {
            echo "# AlphaFold Profiling Metadata"
            echo "# Created: $(date)"
            echo "experiment_id,system_name,timestamp,input_file,stage,threads,profiling_tool,status,output_path"
        } > "$csv_file"
    fi
}

# Update master CSV with new result
update_master_csv() {
    local csv_file=$1
    local experiment_id=$2
    local system_name=$3
    local timestamp=$4
    local input_file=$5
    local stage=$6
    local threads=$7
    local duration=$8
    local status=$9
    local run_purpose=${10}
    local config_hash=${11}
    local profiling_flags=${12}
    local run_metadata=${13}
    
    echo "$experiment_id,$system_name,$timestamp,$input_file,$stage,$threads,$duration,$status,$run_purpose,$config_hash,$profiling_flags,$(escape_csv_field "$run_metadata")" >> "$csv_file"
}

# Update profiling metadata CSV
update_profiling_metadata() {
    local csv_file=$1
    local experiment_id=$2
    local system_name=$3
    local timestamp=$4
    local input_file=$5
    local stage=$6
    local threads=$7
    local profiling_tool=$8
    local status=$9
    local output_path=${10}
    
    echo "$experiment_id,$system_name,$timestamp,$input_file,$stage,$threads,$profiling_tool,$status,$output_path" >> "$csv_file"
}

# Calculate config hash
calculate_config_hash() {
    local config_file=$1
    
    if [ -f "$config_file" ]; then
        md5sum "$config_file" | cut -d' ' -f1
    else
        echo "no_config"
    fi
}

# Validate inference output
validate_inference_output() {
    local output_dir=$1
    
    # Check for ranking_scores.csv file (primary indicator of completion)
    if find "$output_dir" -name "*ranking_scores.csv" -type f | grep -q .; then
        return 0
    else
        return 1
    fi
}

# Handle NSYS output files
handle_nsys_output() {
    local nsys_file=$1
    local system_name=$2
    local input_name=$3
    local threads=$4
    local status=$5
    
    local nsys_reports_dir="${SCRIPT_DIR}/results/nsys_reports"
    mkdir -p "$nsys_reports_dir"
    
    local target_name="${system_name}_${input_name}_${threads}_${status}.nsys-rep"
    
    if [ -f "$nsys_file" ]; then
        cp "$nsys_file" "$nsys_reports_dir/$target_name"
        log_info "NSYS report copied to: $nsys_reports_dir/$target_name"
    fi
}

# Generate inference analysis report
generate_inference_analysis() {
    local analysis_file=$1
    local system_name=$2
    local system_type=$3
    local config_file=$4
    local json_file=$5
    local models_count=$6
    local use_gpu=$7
    local results_csv=$8
    local result_dir=$9
    local nsys_profiling=${10}
    
    {
        echo "=== AlphaFold Inference Analysis ==="
        echo "System: $system_name ($system_type)"
        echo "Date: $(date)"
        echo "Config: $config_file"
        echo "Input: $json_file"
        echo "Models per run: $models_count"
        echo "GPU enabled: $use_gpu"
        echo ""
        echo "Performance Results:"
        cat "$results_csv" | grep -v "^#" | column -t -s ','
        echo ""
        
        # Find best performance
        best_line=$(grep -v "^#" "$results_csv" | grep -v "FAILED" | sort -t',' -k2 -n | head -1)
        if [ -n "$best_line" ]; then
            best_threads=$(echo "$best_line" | cut -d',' -f1)
            best_time=$(echo "$best_line" | cut -d',' -f2)
            echo "Best performance: $best_threads threads in ${best_time}s"
        fi
        
        echo ""
        echo "Generated Files:"
        if [ "$nsys_profiling" = true ]; then
            echo "NSYS Profiles:"
            find "$result_dir" -name "*.nsys-rep" | sed 's/^/  /'
            echo ""
            echo "Analysis Commands:"
            find "$result_dir" -name "*.nsys-rep" | while read profile; do
                echo "  nsys stats $profile"
            done
        fi
        
        echo ""
        echo "Ranking Files:"
        find "$result_dir" -name "ranking_scores.csv" | head -10 | sed 's/^/  /'
        
        echo ""
        echo "PDB Models (if any):"
        find "$result_dir" -name "*.pdb" | head -10 | sed 's/^/  /'
        
        if [ "$use_gpu" = true ]; then
            echo ""
            echo "GPU Monitoring Logs:"
            find "$result_dir" -name "gpu_monitoring.csv" | sed 's/^/  /'
        fi
        
    } > "$analysis_file"
}