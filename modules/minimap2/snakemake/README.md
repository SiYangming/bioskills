# minimap2 / snakemake / local — 自维护 Snakemake rule

从 `snakemake.smk/isoseq.smk/workflow/rules/minimap2.smk` 迁移的实际规则
（去掉对 `workflow/lib/helpers.py` 的全局依赖，`docker_run` 分支删除，路径内联）。

## 文件

| 文件 | 作用 |
|------|------|
| `minimap2_align.smk` | `minimap2 -a <ref> <reads> | samtools sort | samtools view -b -h` 规则 |
| `meta.yaml` | 实现级 Schema（id: `minimap2_snakemake_local`） |

## 使用

在 Snakefile 中：

```python
include: "modules/minimap2/snakemake/minimap2_align.smk"

rule all:
    input:
        "results/minimap2/sample1/sample1.chunk1.bam",
        "results/minimap2/sample1/sample1.chunk1.bam.bai",
```

或直接定义目标：

```bash
snakemake -s Snakefile results/minimap2/sample1/sample1.chunk1.bam --cores 8
```

## 与 isoseq.smk 的差异

- 删除 `docker_run` 分支与 `MINIMAP2_DOCKER_IMAGE` / `SAMTOOLS_DOCKER_IMAGE` 容器配置。
- `get_minimap2_reads`（按 sample 查 mapping_direct_rows 表）内联为直接路径表达式
  `results/gstama/{sample}/{sample}.chunk{n}_gstama.fa.gz`。
- 参数由 `config["minimap2"]` 读取并内联默认值：
  - `minimap2_bin: "minimap2"`、`samtools_bin: "samtools"`
  - `reference` 默认 `config["minimap2"]["fasta"]`
  - `args` 默认空字符串
- 输出带 `.bam.bai`（rule 内 `samtools index`）与 `versions.yml`，与流程原版一致。
