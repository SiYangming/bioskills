import csv
import os
import subprocess
import shutil
import sys
import argparse

def main():
    parser = argparse.ArgumentParser(description="Prepare data for Ribo-seq pipeline")
    parser.add_argument("--input-csv", required=True, help="Path to input info.csv")
    parser.add_argument("--output-dir", required=True, help="Base output directory (e.g. ./results)")
    
    args = parser.parse_args()

    # Config
    input_csv = args.input_csv
    base_output_dir = args.output_dir
    
    # Derived paths
    fastq_output_dir = os.path.join(base_output_dir, "fastq_files")
    env_output_file = os.path.join(base_output_dir, "samples.env")
    
    project_root = os.getcwd()

    print(f"Input CSV: {input_csv}")
    print(f"Output Directory: {fastq_output_dir}")
    print(f"Env Output File: {env_output_file}")

    # Ensure output dir exists
    os.makedirs(fastq_output_dir, exist_ok=True)
    
    # Ensure base output dir exists (for env file)
    os.makedirs(base_output_dir, exist_ok=True)

    rpf_samples = []
    totals_samples = []

    rpf_count = 0
    totals_count = 0

    print("Parsing info.csv and processing files...")

    try:
        with open(input_csv, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                sample_type = row['type']
                fastq_1 = row['fastq_1']
                fastq_2 = row.get('fastq_2', '').strip()
                
                if not fastq_1:
                    continue
                    
                source_path_1 = os.path.join(project_root, fastq_1)
                
                target_name = ""
                if sample_type == 'riboseq':
                    rpf_count += 1
                    target_name = f"RPF_{rpf_count}"
                    rpf_samples.append(target_name)
                elif sample_type == 'rnaseq':
                    totals_count += 1
                    target_name = f"Totals_{totals_count}"
                    totals_samples.append(target_name)
                else:
                    print(f"Skipping unknown type: {sample_type}")
                    continue

                # Process FASTQ 1
                if fastq_2:
                    target_file_1 = f"{target_name}_1.fastq"
                else:
                    target_file_1 = f"{target_name}.fastq"

                target_path_1 = os.path.join(fastq_output_dir, target_file_1)
                
                print(f"Processing {target_name} R1: {source_path_1} -> {target_path_1}")
                
                if os.path.exists(target_path_1):
                     print(f"  Target R1 exists, skipping.")
                else:
                     # Check if source is .gz
                     if source_path_1.endswith('.gz'):
                        cmd = f"gunzip -c {source_path_1} > {target_path_1}"
                     else:
                        cmd = f"cat {source_path_1} > {target_path_1}"
                        
                     try:
                        subprocess.run(cmd, shell=True, check=True)
                     except subprocess.CalledProcessError as e:
                        print(f"Error processing {source_path_1}: {e}")

                # Process FASTQ 2 (if exists)
                if fastq_2:
                    source_path_2 = os.path.join(project_root, fastq_2)
                    target_file_2 = f"{target_name}_2.fastq"
                    target_path_2 = os.path.join(fastq_output_dir, target_file_2)
                    
                    print(f"Processing {target_name} R2: {source_path_2} -> {target_path_2}")

                    if os.path.exists(target_path_2):
                        print(f"  Target R2 exists, skipping.")
                    else:
                        if source_path_2.endswith('.gz'):
                            cmd = f"gunzip -c {source_path_2} > {target_path_2}"
                        else:
                            cmd = f"cat {source_path_2} > {target_path_2}"

                        try:
                            subprocess.run(cmd, shell=True, check=True)
                        except subprocess.CalledProcessError as e:
                            print(f"Error processing {source_path_2}: {e}")

    except FileNotFoundError:
        print(f"Error: {input_csv} not found.")
        sys.exit(1)

    # Generate env file
    print(f"\nGenerating {env_output_file}...")

    rpf_str = ' '.join(rpf_samples)
    totals_str = ' '.join(totals_samples)

    with open(env_output_file, 'w') as f:
        f.write(f"export RPF_filenames='{rpf_str}'\n")
        f.write(f"export Totals_filenames='{totals_str}'\n")

    print(f"Exported RPF_filenames='{rpf_str}'")
    print(f"Exported Totals_filenames='{totals_str}'")
    print("Done.")

if __name__ == "__main__":
    main()
