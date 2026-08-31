# ultra / snakemake / local — 自定义 Snakemake 实现

> 本目录为 snakemake-wrappers 官方缺失（bio/ultra 404）时的 **Snakemake 自维护 rule**。
> 规则从 `snakemake.smk/isoseq.smk/workflow/rules/ultra.smk` 迁移，去掉了对
> `workflow/lib/helpers.py` 的全局依赖（get_sample_species / get_ultra_reads /
> get_index_flag / SPECIES_INFO 等），改为 config 驱动 + 内联简化。

## 使用方式

```python
# Snakefile 中引入（可按需 use 重命名避免规则冲突）
include: "skills/ultra/snakemake/local/rule_ultra.smk"
# 或
use rule prepare_genome, prepare_gtf, sort_gtf, ultra_index, ultra_align \
    from rule_ultra as ultra_prepare_genome, ultra_prepare_gtf, ultra_sort_gtf, ultra_index, ultra_align
```

## 规则清单

| 规则 | 作用 | 迁移自 |
|------|------|--------|
| `prepare_genome` | 解压/软链参考基因组到 `resources/{species}/genome.fa` | `ultra.smk:prepare_genome` |
| `prepare_gtf` | 解压 + 去 `#` 注释行到 `resources/{species}/genes.gtf` | `ultra.smk:prepare_gtf` |
| `sort_gtf` | `sort -k1,1 -k4,4n` → `genes.sorted.gtf` | `ultra.smk:sort_gtf` |
| `ultra_index` | `uLTRA index <fa> <gtf> <outdir> [--disable_infer]`，touch `INDEX/{species}/done` | `ultra.smk:ultra_index` |
| `ultra_align` | `uLTRA align ... --index <idx>` + `samtools sort` → BAM | `ultra.smk:ultra_align` |

## 需要的配置（在 Snakefile 中先声明）

```python
config.setdefault("ultra", {})
config["ultra"].setdefault("ultra_bin", "uLTRA")
config["ultra"].setdefault("index_args", "--disable_infer")
config["ultra"].setdefault("align_args", "")
config["samtools"].setdefault("samtools_bin", "samtools")
# 物种 -> 参考路径映射（替代原 helpers.SPECIES_INFO + get_sample_species）
config.setdefault("species_genome", {"hg38": "refs/hg38.fa.gz"})   # 按需改
config.setdefault("species_gtf",   {"hg38": "refs/hg38.gtf"})
config.setdefault("resources_dir", "resources")
config.setdefault("output_dir", "results")
config.setdefault("ultra_dir", "results/ULTRA")
```

## 与原 isoseq.smk 的差异

- 移除 `helpers.get_ultra_reads`：`ultra_align` 的 reads 输入改为显式通配
  `reads/{sample}.fa.gz`（可在 `use rule` 后按项目覆盖 input）。
- 移除 `helpers.get_index_flag`：`ultra_align` 的 `index_flag` 依赖
  `INDEX/{species}/done`，由调用方保证 `{species}` 通配符与 `ultra_index` 一致。
- `threads: 8` 保留（align/index CPU 密集）；容器/conda 由调用方在 rule 外声明。
