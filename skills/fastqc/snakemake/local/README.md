# fastqc snakemake local 自定义实现占位

仅作为占位：当 snakemake-wrappers 的官方 bio/fastqc 不满足特定需求（如强制 -f fastq_bismark、定制 contaminant/adapter 列表等）时使用。

## 启用步骤

1. 打开本目录 `rule.smk.template`，按实际 IO/参数复制到 Snakefile 或打包的 `rules/fastqc.smk`；
2. 在软件级 meta.yaml 中把 `fastqc_snakemake_local.enabled` 设为 `true`；
3. 完成后执行：
   ```
   snakemake -p --cores 4 qc/{sample}_fastqc.html
   ```
