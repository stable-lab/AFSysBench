#!/usr/bin/env python3
"""
Statistical Analysis Script for AFSysBench
Analyzes execution time deviations from multiple benchmark runs
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
import sys
import os
from pathlib import Path

def load_data(csv_file):
    """Load benchmark data from CSV file"""
    try:
        df = pd.read_csv(csv_file)
        print(f"✅ Loaded {len(df)} benchmark records from {csv_file}")
        return df
    except Exception as e:
        print(f"❌ Error loading data: {e}")
        sys.exit(1)

def calculate_statistics(df):
    """Calculate statistical metrics for each configuration"""
    # Filter only successful runs
    success_df = df[df['status'] == 'SUCCESS'].copy()
    
    if len(success_df) == 0:
        print("❌ No successful runs found!")
        return None
    
    # Group by stage, input_file, and threads
    stats = success_df.groupby(['stage', 'input_file', 'threads'])['duration_sec'].agg([
        'count',      # Number of successful runs
        'mean',       # Average execution time
        'std',        # Standard deviation
        'min',        # Minimum time
        'max',        # Maximum time
        'median',     # Median time
    ]).reset_index()
    
    # Calculate coefficient of variation (CV)
    stats['cv_percent'] = (stats['std'] / stats['mean']) * 100
    
    # Calculate 95% confidence interval
    stats['ci_95_lower'] = stats['mean'] - 1.96 * (stats['std'] / np.sqrt(stats['count']))
    stats['ci_95_upper'] = stats['mean'] + 1.96 * (stats['std'] / np.sqrt(stats['count']))
    
    # Calculate range (max - min)
    stats['range_sec'] = stats['max'] - stats['min']
    
    return stats

def create_deviation_plots(df, stats, output_dir):
    """Create various plots showing execution time deviations"""
    
    # Set style
    plt.style.use('default')
    sns.set_palette("husl")
    
    # Create output directory
    plots_dir = Path(output_dir) / "deviation_plots"
    plots_dir.mkdir(exist_ok=True)
    
    success_df = df[df['status'] == 'SUCCESS'].copy()
    
    # 1. Box plots for each stage
    for stage in success_df['stage'].unique():
        stage_data = success_df[success_df['stage'] == stage]
        
        plt.figure(figsize=(15, 8))
        
        # Create box plot
        sns.boxplot(data=stage_data, x='threads', y='duration_sec', hue='input_file')
        plt.title(f'{stage.upper()} Execution Time Distribution by Thread Count')
        plt.xlabel('Thread Count')
        plt.ylabel('Execution Time (seconds)')
        plt.legend(title='Input File', bbox_to_anchor=(1.05, 1), loc='upper left')
        plt.tight_layout()
        
        plot_file = plots_dir / f'{stage}_boxplot_distribution.png'
        plt.savefig(plot_file, dpi=300, bbox_inches='tight')
        plt.close()
        print(f"📊 Created box plot: {plot_file}")
    
    # 2. Error bar plots with standard deviation
    for stage in success_df['stage'].unique():
        stage_stats = stats[stats['stage'] == stage]
        
        plt.figure(figsize=(15, 8))
        
        # Plot for each input file
        for input_file in stage_stats['input_file'].unique():
            file_stats = stage_stats[stage_stats['input_file'] == input_file]
            
            plt.errorbar(file_stats['threads'], file_stats['mean'], 
                        yerr=file_stats['std'], 
                        marker='o', markersize=8, capsize=5, capthick=2,
                        label=input_file.replace('.json', '').replace('_data', ''))
        
        plt.title(f'{stage.upper()} Mean Execution Time with Standard Deviation')
        plt.xlabel('Thread Count')
        plt.ylabel('Execution Time (seconds)')
        plt.legend(title='Input File')
        plt.grid(True, alpha=0.3)
        plt.tight_layout()
        
        plot_file = plots_dir / f'{stage}_errorbar_mean_std.png'
        plt.savefig(plot_file, dpi=300, bbox_inches='tight')
        plt.close()
        print(f"📊 Created error bar plot: {plot_file}")
    
    # 3. Coefficient of Variation heatmap
    for stage in stats['stage'].unique():
        stage_stats = stats[stats['stage'] == stage]
        
        # Pivot data for heatmap
        cv_pivot = stage_stats.pivot(index='input_file', columns='threads', values='cv_percent')
        
        plt.figure(figsize=(10, 6))
        sns.heatmap(cv_pivot, annot=True, fmt='.1f', cmap='YlOrRd', 
                   cbar_kws={'label': 'Coefficient of Variation (%)'})
        plt.title(f'{stage.upper()} Coefficient of Variation (%) - Lower is Better')
        plt.xlabel('Thread Count')
        plt.ylabel('Input File')
        plt.tight_layout()
        
        plot_file = plots_dir / f'{stage}_cv_heatmap.png'
        plt.savefig(plot_file, dpi=300, bbox_inches='tight')
        plt.close()
        print(f"📊 Created CV heatmap: {plot_file}")
    
    # 4. Individual run scatter plots
    for stage in success_df['stage'].unique():
        stage_data = success_df[success_df['stage'] == stage]
        
        plt.figure(figsize=(15, 10))
        
        # Create subplot for each input file
        inputs = stage_data['input_file'].unique()
        n_inputs = len(inputs)
        
        for i, input_file in enumerate(inputs, 1):
            plt.subplot(2, (n_inputs + 1) // 2, i)
            
            file_data = stage_data[stage_data['input_file'] == input_file]
            
            # Scatter plot with jitter
            for thread in file_data['threads'].unique():
                thread_data = file_data[file_data['threads'] == thread]
                x_jitter = np.random.normal(thread, 0.1, len(thread_data))
                plt.scatter(x_jitter, thread_data['duration_sec'], 
                          alpha=0.7, s=60, label=f'{thread} threads')
            
            plt.title(f'{input_file.replace(".json", "").replace("_data", "")}')
            plt.xlabel('Thread Count')
            plt.ylabel('Execution Time (s)')
            plt.grid(True, alpha=0.3)
        
        plt.suptitle(f'{stage.upper()} Individual Run Scatter Plot')
        plt.tight_layout()
        
        plot_file = plots_dir / f'{stage}_scatter_individual_runs.png'
        plt.savefig(plot_file, dpi=300, bbox_inches='tight')
        plt.close()
        print(f"📊 Created scatter plot: {plot_file}")

def generate_statistical_report(stats, output_dir):
    """Generate detailed statistical report"""
    
    report_file = Path(output_dir) / "statistical_report.txt"
    
    with open(report_file, 'w') as f:
        f.write("AFSysBench Statistical Analysis Report\n")
        f.write("=====================================\n\n")
        
        f.write(f"Analysis Date: {pd.Timestamp.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"Total Configurations Analyzed: {len(stats)}\n\n")
        
        # Summary by stage
        for stage in stats['stage'].unique():
            stage_stats = stats[stats['stage'] == stage]
            
            f.write(f"\n{stage.upper()} STAGE ANALYSIS\n")
            f.write("=" * 50 + "\n\n")
            
            # Overall statistics
            f.write("Overall Statistics:\n")
            f.write(f"  Configurations tested: {len(stage_stats)}\n")
            f.write(f"  Average CV: {stage_stats['cv_percent'].mean():.1f}%\n")
            f.write(f"  Best stability (lowest CV): {stage_stats['cv_percent'].min():.1f}%\n")
            f.write(f"  Worst stability (highest CV): {stage_stats['cv_percent'].max():.1f}%\n\n")
            
            # Detailed breakdown
            f.write("Detailed Results:\n")
            f.write("-" * 100 + "\n")
            f.write(f"{'Input File':<25} {'Threads':<8} {'Mean(s)':<10} {'Std(s)':<10} {'CV(%)':<8} {'Range(s)':<10} {'Runs':<5}\n")
            f.write("-" * 100 + "\n")
            
            for _, row in stage_stats.iterrows():
                f.write(f"{row['input_file']:<25} {row['threads']:<8} {row['mean']:<10.2f} "
                       f"{row['std']:<10.3f} {row['cv_percent']:<8.1f} {row['range_sec']:<10.2f} {row['count']:<5}\n")
            
            f.write("\n")
            
            # Best and worst performers
            best_stable = stage_stats.loc[stage_stats['cv_percent'].idxmin()]
            worst_stable = stage_stats.loc[stage_stats['cv_percent'].idxmax()]
            
            f.write("Stability Analysis:\n")
            f.write(f"  Most Stable: {best_stable['input_file']} with {best_stable['threads']} threads (CV: {best_stable['cv_percent']:.1f}%)\n")
            f.write(f"  Least Stable: {worst_stable['input_file']} with {worst_stable['threads']} threads (CV: {worst_stable['cv_percent']:.1f}%)\n\n")
    
    print(f"📋 Statistical report saved to: {report_file}")

def main():
    if len(sys.argv) != 2:
        print("Usage: python analyze_statistical_data.py <csv_file>")
        sys.exit(1)
    
    csv_file = sys.argv[1]
    
    if not os.path.exists(csv_file):
        print(f"❌ File not found: {csv_file}")
        sys.exit(1)
    
    # Create output directory based on input file
    output_dir = Path(csv_file).parent / "analysis_results"
    output_dir.mkdir(exist_ok=True)
    
    print(f"🔍 Analyzing statistical data from: {csv_file}")
    print(f"📁 Output directory: {output_dir}")
    print("")
    
    # Load and analyze data
    df = load_data(csv_file)
    stats = calculate_statistics(df)
    
    if stats is None:
        return
    
    # Save detailed statistics
    stats_file = output_dir / "detailed_statistics.csv"
    stats.to_csv(stats_file, index=False)
    print(f"💾 Detailed statistics saved to: {stats_file}")
    
    # Create plots
    print("\n📊 Creating deviation plots...")
    create_deviation_plots(df, stats, output_dir)
    
    # Generate report
    print("\n📋 Generating statistical report...")
    generate_statistical_report(stats, output_dir)
    
    print(f"\n✅ Statistical analysis complete!")
    print(f"📁 All results saved to: {output_dir}")
    
    # Print quick summary
    print(f"\n🔍 Quick Summary:")
    total_configs = len(stats)
    avg_cv = stats['cv_percent'].mean()
    print(f"  Total configurations: {total_configs}")
    print(f"  Average CV: {avg_cv:.1f}%")
    
    # Identify most/least stable
    most_stable = stats.loc[stats['cv_percent'].idxmin()]
    least_stable = stats.loc[stats['cv_percent'].idxmax()]
    
    print(f"  Most stable: {most_stable['input_file']} ({most_stable['threads']} threads, CV: {most_stable['cv_percent']:.1f}%)")
    print(f"  Least stable: {least_stable['input_file']} ({least_stable['threads']} threads, CV: {least_stable['cv_percent']:.1f}%)")

if __name__ == "__main__":
    main()