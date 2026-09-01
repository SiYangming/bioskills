# dorado / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 无 `bio/dorado`（抓取 404），因此本目录提供自维护 rule，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`）。

## 规则文件

- `dorado.smk` — 两个 rule，对应 nanoseq 的 dorado 环节 + dorado 官方用法：
  - `dorado_basecall`：`dorado basecaller <model> <pod5> --estimate-poly-a > <fastq>`（迁移自 nanoseq Snakefile 的 `DORADO_FAST5_TO_FASTQ`）
  - `dorado_demux`：`dorado demux <fastq> --kit-name <kit> --output-dir <dir>`（barcode 拆分，可选）

规则迁移自 `snakemake.smk/nanoseq.smk/workflow/Snakefile`，保留 `enable_dorado` 开关语义
（`config["enable_dorado"]` 为 false 时 rule all 不收集输出，整条链路跳过）；`model` /
`docker_image` 走 `config.get("dorado", {...})` 内联默认值（`rna004_130bps_sup@v5.1.0` /
`docker.1ms.run/nanoporetech/dorado:latest`）。

## 用法

```python
# Snakefile 中（需先定义 SAMPLES 与 config）
include: "modules/dorado/snakemake/local/dorado.smk"

# 运行（enable_dorado: true 时）
snakemake -j 8 01_DORADO_BASECALL/sample1.fastq
```

## 依赖环境

dorado **不在 bioconda**，rule 内用 `container` 而非 `conda`：

```yaml
# config.yaml 建议
enable_dorado: true
dorado:
  docker_image: "docker.1ms.run/nanoporetech/dorado:latest"
  model: "rna004_130bps_sup@v5.1.0"
  exec_mode: "docker"
```

首次运行 dorado 会自动下载模型（体积较大），建议挂载 `~/.cache/dorado` 复用。

## 与其它实现的关系

- 官方 wrapper 若未来出现（重新抓取 bio/dorado 有目录），可切换回 `../snakemake-wrappers/` 登记层
- 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `../../native/`
