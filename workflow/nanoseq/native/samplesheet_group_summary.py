import csv
import os
import sys

def main():
    if "snakemake" not in globals():
        sys.exit(1)
    input_csv = snakemake.input[0]
    out_per_group = snakemake.output.per_group
    out_combined = snakemake.output.combined
    report_file = snakemake.output.report
    log_file = snakemake.log[0]
    groups = {}
    with open(input_csv, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            g = row.get("group", "").strip()
            r = str(row.get("replicate", "")).strip()
            sample_id = f"{g}-rep{r}"
            if g not in groups:
                groups[g] = {"samples": [], "rows": []}
            groups[g]["samples"].append(sample_id)
            groups[g]["rows"].append(row)
    os.makedirs(os.path.dirname(out_per_group), exist_ok=True)
    os.makedirs(os.path.dirname(out_combined), exist_ok=True)
    with open(log_file, "w") as log:
        log.write("开始读取样本表并进行分组统计\n")
        with open(out_per_group, "w", newline="") as pg:
            w = csv.writer(pg)
            w.writerow(["group", "count", "samples"])
            for g, info in groups.items():
                w.writerow([g, len(info["samples"]), ";".join(info["samples"])])
                log.write(f"组 {g} 样本数 {len(info['samples'])}\n")
        all_samples = []
        for g in groups:
            all_samples.extend(groups[g]["samples"])
        with open(out_combined, "w", newline="") as cb:
            w = csv.writer(cb)
            w.writerow(["total_groups", "total_samples", "groups", "samples"])
            w.writerow([len(groups), len(all_samples), ";".join(groups.keys()), ";".join(all_samples)])
            log.write(f"合并结果 组数 {len(groups)} 样本总数 {len(all_samples)}\n")
        with open(report_file, "w") as rep:
            rep.write("样本分组与合并计算报告\n")
            rep.write(f"总组数: {len(groups)}\n")
            for g, info in groups.items():
                rep.write(f"组 {g}: 样本数 {len(info['samples'])} 样本 {','.join(info['samples'])}\n")
            rep.write(f"合并样本总数: {len(all_samples)}\n")

if __name__ == "__main__":
    main()
