# subworkflow/qiime2_pipeline — 扩增子 Moving Pictures 档案

档案脚本：远程下载官方示例数据，跑 EMP → DADA2 → 树 → 多样性 → 分类 → ANCOM。

- 元数据：[qiime2_pipeline.yaml](qiime2_pipeline.yaml)
- 可执行档案：`native/run.sh`（例外封装；默认不维护 Python 驱动）
- 安装资源：[modules/qiime2](../../modules/qiime2/README.md)
- 官方教程：<https://amplicon-docs.qiime2.org/en/latest/tutorials/moving-pictures/>

## 用法

```bash
# 先按 modules/qiime2 装好并 conda activate
mkdir -p /tmp/qiime2_run && cd /tmp/qiime2_run
bash /path/to/bioskills/subworkflow/qiime2_pipeline/native/run.sh

# 可选覆盖（默认对齐官方教程）
TRUNC_LEN=120 SAMPLING_DEPTH=1103 bash .../native/run.sh
```

## Stage

```
远程：metadata + EMP zip + pretrained classifier
  → import → demux
  → dada2 denoise-single
  → mafft → mask → fasttree → midpoint-root
  → core-metrics + alpha/beta + emperor
  → classify-sklearn + taxa barplot
  → filter gut → ancom（+ collapse L6）
```

数据 URL 与列名（`barcode-sequence` / `body-site` / `subject`）以官方最新教程为准；换数据时改 `TRUNC_LEN`、`SAMPLING_DEPTH` 与 metadata 列。
