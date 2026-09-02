# orfanage 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# orfanage / native — 自包含驱动

ORFanage 按参考模板合并/注释预测 ORF（GFF3 -> GTF），迁移自
flrnaseq.smk/orfrange_archive/orfanage.py（原 Snakemake wrapper）。

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

```bash
docker build -t bioskills/orfanage:1.2.0-v1.0 -f Dockerfile .
# 必须 -u $(id -u):$(id -g)，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/orfanage:1.2.0-v1.0 \
    run --query in.gff3 --output out.gtf --reference ref.fa tpl.fa
```

## 历史留存（legacy/）

`legacy/` 存放迁移自 flrnaseq.smk/orfrange_archive/ 的原始文件
（orfanage.py / orfanage.smk / orfanage.yaml / config 与 samples snippets），
仅供追溯对照，**正式入口为 `main.py`**。


---

## snakemake 实现

# orfanage / snakemake / local

从 `flrnaseq.smk/orfrange_archive/orfanage.smk` 迁移的 `orfanage.smk`：

```bash
include: "modules/orfanage/snakemake/orfanage.smk"
```

规则自动在 `query_dir` 中选取 `*.transdecoder.gff3`（回退 `*.gff3`），
调用 `orfanage --query ... --output ... --threads N [--reference REF] <templates>`。


---

## Conda 环境（原 native/environment.yml）

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
