# orfanage 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# orfanage / native — 自包含驱动

ORFanage 按参考模板合并/注释预测 ORF（GFF3 -> GTF）。

## 用法

```bash
# CLI 直跑
python main.py run --query predict/merged.transdecoder.gff3 \
    --output orfanage.gtf --reference ref.fa transcript_templates.fa

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

## 容器

官方镜像（biocontainers，2026-09 核实 tag 存在）直拉即可；galaxyproject 亦有预构建 sif：

```bash
docker pull quay.io/biocontainers/orfanage:1.2.0--heaafb18_2
# 必须 -u $(id -u):$(id -g)，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/orfanage:1.2.0--heaafb18_2 \
    orfanage --help
# Apptainer：depot.galaxyproject.org 预构建 sif 直拉
apptainer pull orfanage.sif docker://depot.galaxyproject.org/singularity/orfanage:1.2.0--heaafb18_2
```

需要本仓库 main.py 统一驱动（自省/Schema/run 子命令）时再本地自建（可选，见 native/Dockerfile）：

```bash
cd native && docker build -t bioskills/orfanage:1.2.0-v1.0 -f Dockerfile . && cd ..
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/orfanage:1.2.0-v1.0 \
    run --query in.gff3 --output out.gtf --reference ref.fa tpl.fa
```

## 历史留存

原始实现文件（orfanage.py / orfanage.smk / orfanage.yaml）即当前 `snakemake/` 本地规则本体（同目录平铺）；独立 CLI 场景正式入口为 `main.py`。


---

## snakemake 实现

# orfanage / snakemake / local

自维护 `orfanage.smk`（td2 式 config 驱动单规则；环境 `orfanage.yaml`、wrapper `orfanage.py` 均同目录）：

```bash
# 独立运行
snakemake -s modules/orfanage/snakemake/orfanage.smk \
    --config orfanage_input_query_dir=predict orfanage_templates=tpl.fa orfanage_outdir=orfanage_out \
    --cores 4 --use-conda

# 流程内使用
include: "modules/orfanage/snakemake/orfanage.smk"
```

规则自动在 `orfanage_input_query_dir` 中选取 `*.transdecoder.gff3`（回退 `*.gff3`），
调用 `orfanage --query ... --output ... --threads N [--reference REF] <templates>`，
产物为 `<orfanage_outdir>/orfanage.gtf`。

config 契约（详见 `orfanage.smk` 头部）：`exec_mode`（conda/docker/native）、
`orfanage_input_query_dir`（必填）、`orfanage_outdir`、`orfanage.{orfanage_bin,docker_image,reference,templates,extra_params,lpi/ilpi/mlpi,minlen,overhang,mode,stats,cleanq,cleant,rescue,use_id,non_aug,keep_all_cds,keep_cds_if_not_found,spliced_overhang}`、`threads`。


---

## Conda 环境（离线 / 非容器兜底备选）

```yaml
name: orfanage-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - orfanage=1.2.0
  - pyyaml>=6.0
```

## 容器与 Conda 链接

- **Bioconda 页面**：https://anaconda.org/channels/bioconda/packages/orfanage/overview
- **Docker**：`docker pull quay.io/biocontainers/orfanage:1.2.0--heaafb18_2`
- **Singularity**：https://depot.galaxyproject.org/singularity/orfanage%3A1.2.0--heaafb18_2
- 安装方式（本地）：`mamba create -n orfanage -c conda-forge -c bioconda orfanage=1.2.0`
