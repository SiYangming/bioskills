# nanoseq — Nanopore RNA-seq 复合流程

从原 `snakemake.smk/nanoseq.smk` 迁移重构而来：工具拆分为**原子模块软件技能**，
本目录仅保留「流程编排层」。原流程的 shell 脚本实现（nanoseq.sh/）已留存到
各模块 `native/legacy/`。

## 流程结构

```
[SRA prep: prefetch + fasterq-dump]（可选）
[dorado basecall: fast5 -> fastq]（可选）
fastq ──> [minimap2 align] -x splice -uf -k14 ──> BAM
   ──> [samtools sort/index + flagstat] ──> QC
   ──> [FLAIR consensus: bam2Bed12 -> identify_gene_isoform -> flair collapse]
   ──> [StringTie assemble + fix_gtf + merge]
   ──> [ORF 预测: TransDecoder 或 TD2]
```

## 依赖的原子模块技能

| 阶段 | 软件技能 | 主要入口 |
|------|----------|----------|
| SRA 下载（可选） | `modules/sra-tools/native/` | `python main.py prefetch / fasterq-dump ...` |
| 碱基识别（可选） | `modules/dorado/native/` | `python main.py basecall ...` |
| 比对 | `modules/minimap2/native/` | `python main.py align --bam ...` |
| 排序/QC | `modules/samtools/native/` | `python main.py sort/index/flagstat ...` |
| consensus | `modules/flair/native/` | `python main.py bam2bed12/annotate/collapse ...` |
| 组装 | `modules/stringtie/native/` | `python main.py assemble/fix_gtf/merge ...` |
| ORF 预测 | `modules/transdecoder|td2/native/` | `python main.py longorfs/predict ...` |

## 用法

### 1. Python 编排器（dry-run 默认）

```bash
python nanoseq/nanoseq.py \
    --samplesheet samples.csv --reference ref.fa --gtf ref.gtf \
    --outdir results --orf-tool transdecoder

python nanoseq/nanoseq.py ... --real            # 真实执行
python nanoseq/nanoseq.py ... --with-prep       # 启用 SRA 下载
python nanoseq/nanoseq.py ... --with-dorado     # 启用碱基识别
```

`samples.csv` 至少含 `sample` 与 `input_file`（fastq 路径或目录；SRA 模式需 `srr_id` 列）。

### 2. Snakemake

参考 `workflow_skeleton/Snakefile.template`，流程级示例 config 在 `workflow_skeleton/config/`。

### 3. Nextflow

原流程为 shell/Snakemake 实现；可用各模块 `nextflow/local` 组装。

## 历史留存资产（来自原 nanoseq.smk）

| 资产 | 位置 | 说明 |
|------|------|------|
| FLAIR 批处理脚本 | `modules/flair/native/legacy/run_flair_consensus.sh` | 原 nanoseq.sh 脚本 |
| FLAIR 辅助脚本 | `modules/flair/native/legacy/bed12_add_trailing_commas.py` | 原 workflow/scripts/ |
| StringTie 脚本 | `modules/stringtie/native/legacy/run_stringtie.sh` | 原 nanoseq.sh 脚本 |
| StringTie 修复脚本 | `modules/stringtie/native/legacy/fix_gtf.awk` | 原 workflow/scripts/ |
| SRA 批处理脚本 | `modules/sra-tools/native/legacy/batch_*.sh` | prefetch/sra_to_fastq（含并行版） |
| 比对脚本 | `modules/minimap2/native/legacy/run_alignment_bam.sh` | minimap2\|samtools 管线 |
| QC 脚本 | `modules/samtools/native/legacy/alignment_stats.sh` | flagstat 汇总 |
| 原 workflow 快照（去重后） | `workflow_skeleton/LEGACY_WORKFLOW/` | Snakefile + common.smk（唯一流程公共件）；软件规则已归位到各模块 snakemake/local/ |
| Docker 包装脚本 | `workflow_skeleton/scripts/docker_wrapper.py` | 原 workflow/scripts/docker_wrapper.py |
| 汇总脚本 | `modules/samtools/native/legacy/alignment_summary.py` | 原 workflow/scripts/alignment_summary.py（flagstat 汇总，归位 samtools） |
| 辅助脚本 | `workflow_skeleton/scripts/samplesheet_group_summary.py` | 原 workflow/scripts/ |
| 单元测试 | `LEGACY_tests/test_docker_wrapper.py` | 原 tests/ |
| 流程文档 | `LEGACY_README.md` + `LEGACY_run_workflow.sh` | 原 README.md / run_workflow.sh |
| 流程 config + schema | `workflow_skeleton/config/` | 原 config/config.yaml + samples.schema.yaml |

> 容器运行注意：各模块容器为 Debian bookworm-slim + micromamba 最小化，`docker run` 必须加
> `-u $(id -u):$(id -g)` 避免 root 持有输出文件。

## 测试数据（testdata/）

`testdata/` 提供 nf-core/test-datasets `nanoseq` 分支的官方精简子集（HEK293T-METTL3-KO-rep1 / HEK293T-WT-rep1 的 fast5 与 fastq.gz），来源与完整数据下载方式见 `testdata/README.md`。
