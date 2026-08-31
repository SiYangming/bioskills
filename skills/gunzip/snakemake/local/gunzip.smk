# gunzip / snakemake / local — gunzip.smk
# ---------------------------------------------------------------------------
# 迁移自 snakemake.smk/isoseq.smk/workflow/skills/gunzip/snakemake/local/gunzip.smk，去掉了对
# workflow/lib/helpers.py 的全局依赖（docker_run / GUNZIP_DOCKER_IMAGE），
# 简化为 gzip -cd <in.gz> > <out> 核心语义。
# 使用前请在 Snakefile 声明 config（可选）。
# ---------------------------------------------------------------------------

GZIP_BIN = config.get("gunzip", {}).get("gzip_bin", "gzip")

rule gunzip:
    wildcard_constraints:
        filepath=".*(?<!\.gz)"
    input:
        "{filepath}.gz"
    output:
        "{filepath}"
    params:
        gzip_bin=GZIP_BIN
    shell:
        "{params.gzip_bin} -cd {input} > {output}"


# 使用前在 Snakefile 声明（可选，默认 gzip）：
#   config.setdefault("gunzip", {})
#   config["gunzip"].setdefault("gzip_bin", "gzip")
