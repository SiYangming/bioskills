#!/bin/bash
OUTPUT_DIR="alignment_results_bam"
awk -F ' ' '{
    if ($0 ~ /in total/ || $0 ~ /mapped \(/ && $1 ~ /^[0-9]+$/) {
        sample = FILENAME;
        gsub(/.*\//, "", sample);
        gsub(/\.flagstat\.txt/, "", sample);
        if ($5 == "total") total[sample] = $1;
        if ($4 == "mapped") {
            mapped[sample] = $1;
            mapped_rate[sample] = $5;  # 关键修正：比对率在 $5，不是 $6
            gsub(/\(/, "", mapped_rate[sample]);  # 去掉左括号（$5 是 (96.50%）
        }
    }
}
END {
    printf "%-15s %-12s %-12s %-8s\n", "样本名", "总序列数", "比对数", "比对率";
    printf "%-15s %-12s %-12s %-8s\n", "-----------", "--------", "--------", "------";
    for (s in total) {
        printf "%-15s %-12d %-12d %-8s\n", s, total[s], mapped[s], mapped_rate[s];
    }
}' "$OUTPUT_DIR/flagstat/"*.flagstat.txt
