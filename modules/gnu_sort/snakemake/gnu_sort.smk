# gnu_sort / snakemake / local — gnu_sort.smk
# ---------------------------------------------------------------------------
# 迁移自 snakemake.smk/isoseq.smk/workflow/modules/gnu_sort/snakemake/gnu_sort.smk，去掉了对
# workflow/lib/helpers.py 的全局依赖（get_gnu_sort_args 的后缀 override 逻辑
# 简化为 config["gnu_sort"]["args"] 单一透传；如需要按后缀 override，
# 可在调用方用 use rule 覆盖 params.args）。
# ---------------------------------------------------------------------------

SORT_BIN = config.get("gnu_sort", {}).get("sort_bin", "sort")
SORT_ARGS = config.get("gnu_sort", {}).get("args", "")

rule gnu_sort:
    input:
        "{filepath}"
    output:
        "{filepath}.sorted"
    params:
        sort_bin=SORT_BIN,
        args=SORT_ARGS
    shell:
        "{params.sort_bin} {params.args} {input} > {output}"


# 使用前在 Snakefile 声明（可选，默认 sort 无额外参数）：
#   config.setdefault("gnu_sort", {})
#   config["gnu_sort"].setdefault("sort_bin", "sort")
#   config["gnu_sort"].setdefault("args", "")   # 例如 "-k1,1 -k4,4n"
