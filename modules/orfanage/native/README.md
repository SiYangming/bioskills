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
