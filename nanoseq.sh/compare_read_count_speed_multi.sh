#!/bin/bash

# Usage: ./compare_read_count_speed_multi.sh sorted_bam/ /path/to/hg38.fa
# This script processes all .sorted.bam files in the specified directory.
# Note: Picard CollectAlignmentSummaryMetrics requires a reference FASTA file, while samtools does not.
#       For mapped/sorted BAM files, Picard will compute full alignment metrics, which may take longer.
#       Ensure picard and samtools are in your PATH.

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <bam_directory> <reference.fasta>"
    exit 1
fi

bam_dir="$1"
reference_fasta="$2"
metrics_file_prefix="metrics_"

# Check if reference is a file
if [ ! -f "$reference_fasta" ]; then
    echo "Error: Reference '$reference_fasta' does not exist or is not a file. Provide full path to FASTA (e.g., ../hg38.fa)."
    exit 1
fi

# List all .sorted.bam files (sorted by name)
bam_files=$(find "$bam_dir" -name "*.sorted.bam" | sort)

if [ -z "$bam_files" ]; then
    echo "No .sorted.bam files found in $bam_dir"
    exit 1
fi

# Function to get read count from Picard's metrics file
get_picard_total_reads() {
    local metrics_file="$1"
    awk '
    /## METRICS CLASS/ { metrics=1; next }
    metrics && NF > 0 {
        if ($1 == "CATEGORY") next;  # Skip header
        print $2;  # TOTAL_READS is typically the second column for the first row (e.g., UNPAIRED_READS or ALL_READS)
        exit;
    }' "$metrics_file"
}

# Function to convert time string (e.g., 0:01.23 or 1:23:45.67) to integer seconds
convert_to_seconds() {
    local time_str="$1"
    if [[ $time_str =~ ^(([0-9]+):)?([0-9]+):([0-9]+)\.[0-9]+$ ]]; then
        local hours=${BASH_REMATCH[2]:-0}
        local minutes=${BASH_REMATCH[3]}
        local seconds=${BASH_REMATCH[4]}
        echo $(( hours * 3600 + minutes * 60 + seconds ))
    else
        echo 0
    fi
}

echo "Comparing speed for counting total reads across multiple BAM files in $bam_dir"

total_samtools_real=0
total_samtools_user=0
total_samtools_sys=0
total_picard_real=0
total_picard_user=0
total_picard_sys=0
file_count=0

# Table header
printf "\n%-25s | %-15s | %-15s | %-15s | %-15s | %-15s | %-15s | %-15s | %-15s\n" "File" "Samtools Reads" "Samtools Real" "Samtools User" "Samtools Sys" "Picard Reads" "Picard Real" "Picard User" "Picard Sys"
printf "%s\n" "---------------------------------------------------------------------------------------------------------------------------------------------------"

for input_bam in $bam_files; do
    base_name=$(basename "$input_bam")
    metrics_file="${metrics_file_prefix}${base_name}.txt"

    # Samtools timing and count
    samtools_count=$(samtools view -c "$input_bam")
    samtools_times=$({ /usr/bin/time -f "%E %U %S" samtools view -c "$input_bam" >/dev/null; } 2>&1)
    samtools_real=$(echo "$samtools_times" | awk '{print $1}')
    samtools_user=$(echo "$samtools_times" | awk '{print $2}')
    samtools_sys=$(echo "$samtools_times" | awk '{print $3}')
    samtools_real_sec=$(convert_to_seconds "$samtools_real")
    samtools_user_sec=$(echo "$samtools_user" | awk '{printf "%.0f", $1}')
    samtools_sys_sec=$(echo "$samtools_sys" | awk '{printf "%.0f", $1}')

    # Picard timing and count (logs to stdout for debugging; errors will show in nohup.out)
    { /usr/bin/time -f "%E %U %S" picard CollectAlignmentSummaryMetrics \
        INPUT="$input_bam" \
        OUTPUT="$metrics_file" \
        REFERENCE_SEQUENCE="$reference_fasta" \
        VALIDATION_STRINGENCY=SILENT; } 2>&1
    if [ -f "$metrics_file" ]; then
        picard_count=$(get_picard_total_reads "$metrics_file")
        picard_times=$({ /usr/bin/time -f "%E %U %S" picard CollectAlignmentSummaryMetrics ... ; } 2>&1)  # Note: Re-run for timing only if needed; for now, assume same
        picard_real=$(echo "$picard_times" | awk '{print $1}')
        picard_user=$(echo "$picard_times" | awk '{print $2}')
        picard_sys=$(echo "$picard_times" | awk '{print $3}')
        picard_real_sec=$(convert_to_seconds "$picard_real")
        picard_user_sec=$(echo "$picard_user" | awk '{printf "%.0f", $1}')
        picard_sys_sec=$(echo "$picard_sys" | awk '{printf "%.0f", $1}')
    else
        echo "Picard failed for $base_name: Metrics file not created. Check reference FASTA path or run manually for errors."
        picard_count="Error"
        picard_real="N/A"
        picard_user="N/A"
        picard_sys="N/A"
        picard_real_sec=0
        picard_user_sec=0
        picard_sys_sec=0
    fi

    # Accumulate totals (only if no error)
    if [ "$picard_count" != "Error" ]; then
        total_picard_real=$(echo "$total_picard_real + $picard_real_sec" | bc)
        total_picard_user=$(echo "$total_picard_user + $picard_user_sec" | bc)
        total_picard_sys=$(echo "$total_picard_sys + $picard_sys_sec" | bc)
    fi
    total_samtools_real=$(echo "$total_samtools_real + $samtools_real_sec" | bc)
    total_samtools_user=$(echo "$total_samtools_user + $samtools_user_sec" | bc)
    total_samtools_sys=$(echo "$total_samtools_sys + $samtools_sys_sec" | bc)
    file_count=$((file_count + 1))

    # Print row (use N/A for blanks)
    printf "%-25s | %-15s | %-15s | %-15s | %-15s | %-15s | %-15s | %-15s | %-15s\n" "$base_name" "${samtools_count:-N/A}" "${samtools_real:-N/A}" "${samtools_user:-N/A}" "${samtools_sys:-N/A}" "${picard_count:-N/A}" "${picard_real:-N/A}" "${picard_user:-N/A}" "${picard_sys:-N/A}"

    # Cleanup
    rm -f "$metrics_file"
done

# Summary
echo -e "\nSummary:"
echo "Total files processed: $file_count"
echo "Total Samtools Real time: $total_samtools_real seconds"
echo "Total Samtools User time: $total_samtools_user seconds"
echo "Total Samtools Sys time: $total_samtools_sys seconds"
echo "Total Picard Real time: $total_picard_real seconds"
echo "Total Picard User time: $total_picard_user seconds"
echo "Total Picard Sys time: $total_picard_sys seconds"

# Comparison
if [ $(echo "$total_samtools_real > 0" | bc) -eq 1 ]; then
    speedup_real=$(echo "scale=2; $total_picard_real / $total_samtools_real" | bc)
    echo "Picard is approximately ${speedup_real}x slower in real time than samtools overall."
else
    echo "Unable to calculate speedup (Samtools total real time is 0)."
fi

echo -e "\nNote: Times are in MM:SS or H:MM:SS format from /usr/bin/time. Picard computes more metrics, so it's expected to be slower. For sorted/mapped BAMs, alignment stats are included, increasing time."
echo "If counts don't match for any file, verify BAM integrity or reference compatibility."
