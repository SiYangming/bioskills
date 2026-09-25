# subworkflow/umi_tools_extract_dedup — UMI extract →（外部比对）→ dedup

无编排 `main.py`、无本地 `.smk`。原子规则在 [modules/umi_tools/snakemake/](../modules/umi_tools/snakemake/)；本文件只登记串联方式。

- 元数据：[umi_tools_extract_dedup.yaml](umi_tools_extract_dedup.yaml)
- 模块：[modules/umi_tools](../modules/umi_tools/README.md)

## CLI 串联

```bash
# 1) extract（SE/PE）
python modules/umi_tools/native/main.py extract -I reads.fq.gz -o out.umi.fq.gz --bc-pattern=NNNN

# 2) 比对：由调用流程完成（如 riboseq bbmap / bowtie2），得到含 UMI 的 BAM

# 3) dedup
python modules/umi_tools/native/main.py dedup -I aligned.bam -o dedup.bam
```

```
umi_tools extract → [caller align] → umi_tools dedup
```

## Snakemake（按需在项目内 include，勿重复 glob）

主 Snakefile 直接 include 模块三规则即可（本组合不再提供聚合 `.smk`）：

```python
include: "modules/umi_tools/snakemake/umi_tools_extract_se.smk"
include: "modules/umi_tools/snakemake/umi_tools_extract_pe.smk"
include: "modules/umi_tools/snakemake/umi_tools_dedup.smk"

# config 示例（顶层键，详见各 .smk 头注）
# config["umi_input_fastq"] = "..."
# config["umi_input_bam"]   = "align/s1.pc.sorted.bam"   # 比对产物
# config["umi_output_bam"]  = "umi/s1.dedup.bam"
# rule all:
#     input: config["umi_output_bam"]
```

若主 Snakefile 已对 `modules/umi_tools/snakemake/*.smk` 做 glob include，不要再手写上述三条，以免规则名冲突。
