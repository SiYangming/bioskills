# workflow/nanoseq — Nanopore RNA-seq（登记层）

无流程级 `native/main.py` / `run_*.sh`。旧多工具一键脚本已归档（`.archive-backup/`）；请直接串联各模块 CLI。

## 真源与官方流程

- **Nextflow**：官方 [nf-core/nanoseq](https://github.com/nf-core/nanoseq)（bambu 等）—— 不建本地 nextflow/
- **本地路线**：FLAIR → StringTie → TransDecoder/TD2（与官方下游不同，属自定义串联）
- **元数据**：[meta.yaml](nanoseq.yaml)

## 阶段 → 模块

| 阶段 | 软件 | 入口 |
|------|------|------|
| SRA（可选） | sra-tools | `modules/sra-tools/native/main.py`；另有 `batch_prefetch.sh` 等 |
| basecall（可选） | dorado | `modules/dorado/native/main.py` |
| 比对 | minimap2 | `modules/minimap2/native/main.py align`（`-x splice -uf -k14`） |
| 排序/QC | samtools | `modules/samtools/native/main.py`（sort / index / flagstat） |
| consensus | flair | `modules/flair/native/main.py`（bam2Bed12 → annotate → collapse） |
| 组装 | stringtie | `modules/stringtie/native/main.py`（assemble → fix_gtf → merge） |
| ORF | transdecoder / td2 | `modules/transdecoder`、`modules/td2` |

旧 `01_run_alignment_bam.sh` 等为多工具胶水，**不迁入单模块**（避免污染原子边界）；需要并行时在各自模块加 `batch_*.sh`，或 shell 循环调 `main.py`。

## 推荐串联（仓库根）

```bash
OUT=results SAMPLE=s1 READS=reads.fastq.gz REF=ref.fa GTF=annot.gtf

python modules/minimap2/native/main.py align \
  --reads "$READS" --reference "$REF" --outdir "$OUT/01_MINIMAP2_ALIGN/$SAMPLE" \
  --prefix "$SAMPLE" --bam --args "-x splice -uf -k14"

python modules/samtools/native/main.py sort \
  "$OUT/01_MINIMAP2_ALIGN/$SAMPLE/${SAMPLE}.bam" \
  -o "$OUT/01_MINIMAP2_ALIGN/$SAMPLE/${SAMPLE}.sorted.bam"
python modules/samtools/native/main.py index \
  "$OUT/01_MINIMAP2_ALIGN/$SAMPLE/${SAMPLE}.sorted.bam"
python modules/samtools/native/main.py flagstat \
  "$OUT/01_MINIMAP2_ALIGN/$SAMPLE/${SAMPLE}.sorted.bam"

# FLAIR → StringTie → TD2/TransDecoder：见各 modules/<sw>/native/main.py --help
python modules/flair/native/main.py --help
python modules/stringtie/native/main.py --help
python modules/td2/native/main.py --help
```

建议输出根：`01_MINIMAP2_ALIGN` / `02_FLAIR_CONSENSUS` / `03_STRINGTIE` / `04_1_TRANSDECODER` 或 `04_2_TD2`。

## 测试数据

nf-core/test-datasets 分支 `nanoseq` 路径 `modification_fast5_fastq`（不随仓）。冒烟可只下单个 fastq，直接调 `minimap2` 模块。
