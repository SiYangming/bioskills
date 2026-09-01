#!/bin/bash

# Usage: ./compare_read_count_speed_multi.sh sorted_bam/
# This script processes all .sorted.bam files in the specified directory.
# Compare speed between samtools view -c and picard CountReads (both count total reads)
# Note: Picard CountReads does NOT require a reference FASTA file
#       Ensure picard (system-wide) and samtools are in your PATH

# ====================== 关键修改：设置Java内存 + 直接调用picard ======================
# 导出Java堆内存（500G，根据服务器实际内存调整，建议不超过物理内存的80%）
export _JAVA_OPTIONS="-Xmx500g -Xms200g"  # -Xms为初始内存，提升性能
# 直接调用picard命令（无需java -jar）
PICARD_CMD="picard"

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <bam_directory>"
    exit 1
fi

bam_dir="$1"
metrics_file_prefix="picard_count_temp_"

# List all .sorted.bam files (sorted by name)
bam_files=$(find "$bam_dir" -name "*.sorted.bam" | sort)

if [ -z "$bam_files" ]; then
    echo "No .sorted.bam files found in $bam_dir"
    exit 1
fi

# 修复：兼容/usr/bin/time %E的所有格式（SS.ss / MM:SS.ss / H:MM:SS.ss）
convert_to_seconds() {
    local time_str="$1"
    # 拆分时间字符串（处理 H:MM:SS.ss / MM:SS.ss / SS.ss）
    if [[ $time_str =~ ^(([0-9]+):)?(([0-9]+):)?([0-9]+\.[0-9]+)$ ]]; then
        local hours=${BASH_REMATCH[2]:-0}
        local minutes=${BASH_REMATCH[4]:-0}
        local seconds=${BASH_REMATCH[5]}
        # 转换为总秒数（保留2位小数，便于后续计算）
        echo "scale=2; $hours * 3600 + $minutes * 60 + $seconds" | bc
    else
        echo 0
    fi
}

echo "=== Comparing speed: samtools vs Picard CountReads ==="
echo "Java memory setting: $_JAVA_OPTIONS"
echo "Processing BAM files in: $bam_dir"
echo "======================================================="

total_samtools_real=0
total_samtools_user=0
total_samtools_sys=0
total_picard_real=0
total_picard_user=0
total_picard_sys=0
file_count=0

# Table header（优化列宽，适配更多场景）
printf "\n%-30s | %-15s | %-12s | %-12s | %-12s | %-15s | %-12s | %-12s | %-12s\n" \
    "File" "Samtools Reads" "Samtools Real(s)" "Samtools User(s)" "Samtools Sys(s)" \
    "Picard Reads" "Picard Real(s)" "Picard User(s)" "Picard Sys(s)"
printf "%s\n" "-------------------------------------------------------------------------------------------------------------------------------------------------------------------------"

for input_bam in $bam_files; do
    base_name=$(basename "$input_bam")
    temp_picard_log="${metrics_file_prefix}${base_name}.log"

    # ====================== 1. Samtools 统计 + 计时 ======================
    # 一次运行同时捕获count和时间（避免重复运行BAM）
    samtools_output=$({ 
        /usr/bin/time -f "real:%E user:%U sys:%S" samtools view -c "$input_bam" 2>&1; 
    })
    # 提取count和时间
    samtools_count=$(echo "$samtools_output" | grep -v "^real:" | tail -1)
    samtools_real=$(echo "$samtools_output" | grep "^real:" | awk -F: '{print $2":"$3":"$4}' | sed 's/ //g')
    samtools_user=$(echo "$samtools_output" | grep "^user:" | awk -F: '{print $2}' | sed 's/ //g')
    samtools_sys=$(echo "$samtools_output" | grep "^sys:" | awk -F: '{print $2}' | sed 's/ //g')
    # 转换为秒数
    samtools_real_sec=$(convert_to_seconds "$samtools_real")
    samtools_user_sec=$(convert_to_seconds "$samtools_user")
    samtools_sys_sec=$(convert_to_seconds "$samtools_sys")

    # ====================== 2. Picard CountReads 统计 + 计时 ======================
    picard_count="Error"
    picard_real="N/A"
    picard_user="N/A"
    picard_sys="N/A"
    picard_real_sec=0
    picard_user_sec=0
    picard_sys_sec=0

    # 一次运行同时捕获count和时间（直接调用picard，带内存参数）
    picard_output=$({ 
        /usr/bin/time -f "real:%E user:%U sys:%S" $PICARD_CMD CountReads \
            INPUT="$input_bam" \
            VALIDATION_STRINGENCY=SILENT \
            2>&1; 
    })

    # 检查Picard是否运行成功
    if echo "$picard_output" | grep -q "Reads counted:"; then
        # 提取count数（Picard CountReads输出格式：Reads counted: X）
        picard_count=$(echo "$picard_output" | grep "Reads counted:" | awk '{print $3}')
        # 提取时间
        picard_real=$(echo "$picard_output" | grep "^real:" | awk -F: '{print $2":"$3":"$4}' | sed 's/ //g')
        picard_user=$(echo "$picard_output" | grep "^user:" | awk -F: '{print $2}' | sed 's/ //g')
        picard_sys=$(echo "$picard_output" | grep "^sys:" | awk -F: '{print $2}' | sed 's/ //g')
        # 转换为秒数
        picard_real_sec=$(convert_to_seconds "$picard_real")
        picard_user_sec=$(convert_to_seconds "$picard_user")
        picard_sys_sec=$(convert_to_seconds "$picard_sys")
    else
        echo "Warning: Picard CountReads failed for $base_name (check BAM integrity or picard path)"
        echo "Picard error output: $picard_output" > "${temp_picard_log}.err"
    fi

    # ====================== 3. 累计总时间 ======================
    # 累加时保留2位小数
    total_samtools_real=$(echo "scale=2; $total_samtools_real + $samtools_real_sec" | bc)
    total_samtools_user=$(echo "scale=2; $total_samtools_user + $samtools_user_sec" | bc)
    total_samtools_sys=$(echo "scale=2; $total_samtools_sys + $samtools_sys_sec" | bc)
    
    if [ "$picard_count" != "Error" ]; then
        total_picard_real=$(echo "scale=2; $total_picard_real + $picard_real_sec" | bc)
        total_picard_user=$(echo "scale=2; $total_picard_user + $picard_user_sec" | bc)
        total_picard_sys=$(echo "scale=2; $total_picard_sys + $picard_sys_sec" | bc)
    fi
    file_count=$((file_count + 1))

    # ====================== 4. 打印单行结果 ======================
    printf "%-30s | %-15s | %-12.2f | %-12.2f | %-12.2f | %-15s | %-12.2f | %-12.2f | %-12.2f\n" \
        "$base_name" \
        "${samtools_count:-N/A}" "$samtools_real_sec" "$samtools_user_sec" "$samtools_sys_sec" \
        "${picard_count:-N/A}" "$picard_real_sec" "$picard_user_sec" "$picard_sys_sec"

    # 清理临时文件
    rm -f "$temp_picard_log" "${temp_picard_log}.err"
done

# ====================== 汇总与对比 ======================
echo -e "\n===================== Summary ====================="
echo "Total files processed: $file_count"
echo "Samtools total time (real): $total_samtools_real seconds"
echo "Samtools total time (user): $total_samtools_user seconds"
echo "Samtools total time (sys): $total_samtools_sys seconds"
echo "Picard CountReads total time (real): $total_picard_real seconds"
echo "Picard CountReads total time (user): $total_picard_user seconds"
echo "Picard CountReads total time (sys): $total_picard_sys seconds"

# 计算速度比（Picard / Samtools，值越大Picard越慢）
if (( $(echo "$total_samtools_real > 0.01" | bc -l) )); then  # 避免除以0
    speedup_real=$(echo "scale=2; $total_picard_real / $total_samtools_real" | bc)
    echo -e "\nPicard CountReads is approximately ${speedup_real}x slower than samtools (real time) overall."
else
    echo -e "\nUnable to calculate speedup (Samtools real time is too small)."
fi

echo -e "\nNote: "
echo "1. Samtools uses 'samtools view -c' (counts all reads in BAM)";
echo "2. Picard uses 'picard CountReads' (pure read count, with Java memory: $_JAVA_OPTIONS)";
echo "3. Times are in seconds (real = wall-clock time, user = CPU user time, sys = CPU system time)";
echo "4. If counts don't match, check BAM integrity (samtools quickcheck $input_bam)";
# 取消导出的Java变量（可选）
unset _JAVA_OPTIONS
