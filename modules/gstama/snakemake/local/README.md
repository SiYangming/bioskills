# gstama / snakemake / local — 自维护 Snakemake rule

从 `snakemake.smk/isoseq.smk/workflow/rules/gstama.smk` 迁移的实际规则
（去掉对 `workflow/lib/helpers.py` 的全局依赖，`docker_run` 分支删除，路径内联）。

> 官方 `bio/gstama` 在 snakemake-wrappers 中不存在（404），本目录是 Snakemake 场景的**实际执行路径**。

## 文件

| 文件 | 作用 |
|------|------|
| `gstama_polyacleanup.smk` | polyA 清理 + gzip（tama_flnc_polya_cleanup.py） |
| `gstama_collapse.smk` | 转录本去冗余（tama_collapse.py） |
| `gstama_filelist.smk` | 由 collapse bed 生成 merge TSV（`run:` 纯 Python，无外部依赖） |
| `gstama_merge.smk` | 合并转录本（tama_merge.py，空 filelist 自动跳过） |
| `meta.yaml` | 实现级 Schema（id: `gstama_snakemake_local`） |

## 使用

在 Snakefile 中：

```python
include: "modules/gstama/snakemake/local/gstama_polyacleanup.smk"
include: "modules/gstama/snakemake/local/gstama_collapse.smk"
include: "modules/gstama/snakemake/local/gstama_filelist.smk"
include: "modules/gstama/snakemake/local/gstama_merge.smk"

rule all:
    input:
        "results/gstama_merge/merged.bed",
```

## 与 isoseq.smk 的差异

- 删除 `docker_run` 分支与 `GSTAMA_DOCKER_IMAGE` 容器配置。
- `get_collapse_input_bam`（按 aligner 查 minimap2/ultra 目录）内联为默认 minimap2 路径
  `results/minimap2/{aligner}/{sample}/{sample}.chunk{n}.bam`（ultra 场景需自行改 input）。
- `get_all_collapse_beds`（遍历 sample 表）内联为 `run:` 块内的 glob 遍历。
- 参数由 `config["gstama"]` 读取并内联默认值：
  - `collapse_args: "-x no_cap -a 100 -z 100 -sj sj_priority -sjt 20 -lde 5"`
  - `merge_args: "-a 100 -z 100 -m 20 -d merge_dup"`
  - `filelist_cap: "no_cap"`、`filelist_order: "1"`
- 各规则仍写 `versions.yml`（与 nf-core 模块风格一致）。
