# gstama filelist Snakemake rule（从 isoseq.smk/workflow/rules/gstama.smk 迁移）
#
# 迁移说明：
#   - 原 rule 用 script: "../scripts/gstama_filelist.py" + input: get_all_collapse_beds(...)，
#     此处改为 run: 纯 Python 块，直接 glob 遍历 collapse 目录（无 helper / 无外部脚本依赖）
#   - 去掉 docker_run 分支与容器配置

GSTAMA_COLLAPSE_DIR = config.get("gstama", {}).get("collapse_dir", "results/gstama_collapse")

rule gstama_filelist:
    """由 collapse 产出的 *_collapsed.bed 生成 merge 用 filelist TSV（纯 Python）。"""
    output:
        filelist="results/gstama_filelist/filelist.tsv",
        versions="results/gstama_filelist/versions.yml"
    params:
        cap=config.get("gstama", {}).get("filelist_cap", "no_cap"),
        order=config.get("gstama", {}).get("filelist_order", "1"),
        collapse_dir=GSTAMA_COLLAPSE_DIR
    log:
        "logs/gstama_filelist.log"
    run:
        import glob
        import os
        import re

        outdir = os.path.dirname(output.filelist)
        os.makedirs(outdir, exist_ok=True)

        # 遍历 {collapse_dir}/{aligner}/{sample}/*_collapsed.bed（替代原 get_all_collapse_beds）
        pattern = os.path.join(params.collapse_dir, "*", "*", "*_collapsed.bed")
        beds = sorted(glob.glob(pattern))

        with open(output.filelist, "w") as out_f:
            for bed_path in beds:
                if not os.path.exists(bed_path) or os.path.getsize(bed_path) == 0:
                    continue
                m = re.search(r"chunk(\d+)", os.path.basename(bed_path))
                if m:
                    n = m.group(1)
                    order_str = f"{n},{n},{n}"
                else:
                    o = str(params.order).strip()
                    if "," in o:
                        order_str = o
                    elif o.isdigit():
                        order_str = f"{o},{o},{o}"
                    else:
                        order_str = "1,1,1"
                rel = os.path.relpath(bed_path, params.collapse_dir)
                parts = rel.split("/")
                if len(parts) >= 3:
                    file_tag = os.path.splitext(parts[-1])[0]
                    source_id = f"{parts[0]}:{parts[1]}:{file_tag}"
                else:
                    source_id = f"unknown:unknown:{os.path.basename(bed_path)}"
                out_f.write(f"{bed_path}\t{params.cap}\t{order_str}\t{source_id}\n")

        with open(output.versions, "w") as v:
            v.write("gstama_filelist:\n    python: built-in\n")
