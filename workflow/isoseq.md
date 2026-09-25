# workflow/isoseq — PacBio Iso-Seq 全长转录组（登记层）

无流程级 `native/`。编排 = 按序调用各 `modules/<sw>/native/`；批处理为模块内通用 `batch_*.sh`（必填路径环境变量，无项目硬编码）。

## 真源与官方流程

- **Nextflow**：官方 [nf-core/isoseq](https://github.com/nf-core/isoseq) —— 不建本地 nextflow/
- **本地路线**：原子模块串联（下表）；gstama Python3 fork：<https://github.com/SiYangming/gs-tama>
- **元数据**：[isoseq.yaml](isoseq.yaml)

## 阶段 → 模块

| 阶段 | 软件 | 单样本入口 | 目录批处理 |
|------|------|------------|------------|
| CCS | pbccs | `main.py ccs` | `batch_ccs.sh` |
| 去引物 | lima | `main.py lima` | `batch_lima.sh` |
| refine | isoseq3 | `main.py refine` | `batch_refine.sh` |
| BAM→FASTA | bamtools | `main.py convert` | `batch_convert.sh` |
| polyA | gstama | `main.py polyacleanup` | `batch_polyacleanup.sh` |
| 比对 A | minimap2 | `main.py align` | `batch_align.sh` |
| 比对 B | ultra | `ULTRA_align.py` / `main.py` | `batch_align.sh` |
| collapse/filelist/merge | gstama | `gs_tama.py` | `batch_collapse_merge.sh` |

共享并发：`scripts/batch_parallel.sh`（ParaFly → parallel → xargs；默认 `PARA_CPU≤4`）。

## 推荐串联（仓库根；路径自定）

```bash
DATA=/path/to/subreads_samples
PRIMERS=/path/to/primers.fa
REF=/path/to/genome.fa
GTF=/path/to/annot.gtf   # 仅 ultra 需要
OUT=/path/to/results

DATA_DIR=$DATA OUT_BASE=$OUT/01_ccs CHUNK_TOTAL=10 \
  bash modules/pbccs/native/batch_ccs.sh

DATA_DIR=$OUT/01_ccs OUT_BASE=$OUT/02_lima PRIMERS=$PRIMERS \
  bash modules/lima/native/batch_lima.sh

DATA_DIR=$OUT/02_lima OUT_BASE=$OUT/03_refine PRIMERS=$PRIMERS \
  bash modules/isoseq3/native/batch_refine.sh

DATA_DIR=$OUT/03_refine OUT_BASE=$OUT/04_fasta \
  bash modules/bamtools/native/batch_convert.sh

DATA_DIR=$OUT/04_fasta OUT_BASE=$OUT/05_polya \
  bash modules/gstama/native/batch_polyacleanup.sh

# 路径 A：minimap2
DATA_DIR=$OUT/05_polya OUT_BASE=$OUT/06_minimap2 REFERENCE=$REF \
  bash modules/minimap2/native/batch_align.sh

# 或路径 B：ultra
# DATA_DIR=$OUT/05_polya OUT_BASE=$OUT/06_ultra REFERENCE_FA=$REF GTF=$GTF \
#   bash modules/ultra/native/batch_align.sh

GENOME_FA=$REF \
COLLAPSE_BAM_DIRS="$OUT/06_minimap2" COLLAPSE_LABELS="minimap2" \
COLLAPSE_OUT_BASE=$OUT/07_collapse FILELIST_OUT_BASE=$OUT/08_filelist MERGE_OUT_BASE=$OUT/09_merge \
  bash modules/gstama/native/batch_collapse_merge.sh
```

各 `batch_*.sh` 无参运行会打印 Usage；二进制路径可用 `CCS_BIN` / `LIMA_BIN` / `MINIMAP2_BIN` 等覆盖。
