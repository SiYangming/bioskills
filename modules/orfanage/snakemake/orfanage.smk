# orfanage Snakemake 规则（迁移自 flrnaseq.smk/orfrange_archive/orfanage.smk）
#
# 迁移说明：
#   - 去掉 common.smk 全局依赖（SAMPLES lambda -> 路径模板、container 引用移除）
#   - query_dir 内自动选取 *.transdecoder.gff3（回退 *.gff3）
#   - 输出 <sample>/ 目录下的 orfanage.gtf
#   - 参考与模板通过 config["orfanage"] 可覆盖

ORFANAGE_DIR = config.get("orfanage_dir", "results/ORFANAGE")

rule orfanage:
    """ORFanage：按参考模板合并/注释预测 ORF（GFF3 -> GTF）。"""
    input:
        query_dir="results/01_1_TRANSDECODER/{sample}/predict",
        reference=config.get("orfanage", {}).get("reference", "ref/ref.fa"),
        templates=config.get("orfanage", {}).get("templates", ["ref/tpl.fa"])
    output:
        gtf="results/ORFANAGE/{sample}/orfanage.gtf"
    params:
        extra=config.get("orfanage", {}).get("extra_params", ""),
        mode=config.get("orfanage", {}).get("mode", ""),
        version=config.get("orfanage", {}).get("version", "1.2.0")
    threads: 4
    log:
        "logs/orfanage_{sample}.log"
    run:
        import glob, os
        os.makedirs(os.path.dirname(str(output.gtf)), exist_ok=True)
        gff = glob.glob(os.path.join(str(input.query_dir), "*.transdecoder.gff3"))
        if not gff:
            gff = glob.glob(os.path.join(str(input.query_dir), "*.gff3"))
        if not gff:
            raise FileNotFoundError(f"query_dir 中未找到 GFF3: {input.query_dir}")
        tpls = [input.templates] if isinstance(input.templates, str) else list(input.templates)
        cmd = [
            "orfanage", "--query", gff[0], "--output", str(output.gtf),
            "--threads", str(threads),
        ]
        if input.reference:
            cmd += ["--reference", str(input.reference)]
        cmd += tpls
        shell(" ".join(cmd) + " >> {log} 2>&1")
