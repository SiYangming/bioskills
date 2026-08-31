# custom/isoseq — PacBio Iso-Seq 全长转录组复合流程

从原单体流程 `snakemake.smk/isoseq.smk` 迁移重构而来：原流程被**拆分为原子模块软件技能**，
本目录仅保留「流程编排层」。

## 流程结构

```
subreads ──> [pbccs] ──> HiFi CCS ──> [lima] ──> 去引物/拆分 ──> [isoseq3 refine]
   ──> BAM ──> [bamtools convert] ──> FASTA ──> [gstama polyA 清理]
   ──> clean FASTA ──> 比对（二选一）
        ├── [minimap2 align]  -x splice -uf -k14
        └── [uLTRA align]     index + align（需 GTF 注释）
   ──> 比对 BAM ──> [gstama collapse] ──> *.bed
   ──> [gstama filelist] ──> filelist.tsv ──> [gstama merge] ──> merged.bed
```

## 依赖的原子模块技能

| 阶段 | 软件技能 | 主要入口 |
|------|----------|----------|
| CCS | `skills/pbccs/native/` | `python main.py ccs ...` |
| 去引物 | `skills/lima/native/` | `python main.py lima ...` |
| refine | `skills/isoseq3/native/` | `python main.py refine ...` |
| BAM→FASTA | `skills/bamtools/native/` | `python main.py convert ...` |
| polyA 清理 | `skills/gstama/native/` | `python main.py polyacleanup ...` |
| 比对 A | `skills/minimap2/native/` | `python main.py align --bam ...` |
| 比对 B | `skills/ultra/native/` | `python main.py index/align ...` |
| collapse | `skills/gstama/native/` | `python main.py collapse ...` |
| filelist | `skills/gstama/native/` | `python main.py filelist ...` |
| merge | `skills/gstama/native/` | `python main.py merge ...` |

每个软件技能内同时提供 `nextflow/nf-core/`（官方模块说明层）与
`snakemake/local/rule_*.smk`（迁移自原流程的规则）实现。

## 用法

### 1. Python 编排器（dry-run 默认）

```bash
# 仅打印将执行的命令（不真正运行）
python skills/custom/isoseq/isoseq.py \
    --samplesheet samples.csv --primers primers.fasta \
    --reference genome.fa --aligner minimap2 --outdir results

# 真实执行（需先安装 pbccs/lima/isoseq3/bamtools/gstama/minimap2）
python skills/custom/isoseq/isoseq.py ... --real
```

`samples.csv` 至少含 `sample` 列；可选列：
- `seq_data`：输入路径（subreads.bam / ccs.bam / lima.bam / fasta）
- `start_from`：`ccs|lima|refine|bamtools|gstama|mapping`，支持从中间步骤接入

### 2. Snakemake

参考 `workflow_skeleton/Snakefile.template`，各步骤规则已迁移到
`skills/<sw>/snakemake/local/rule_*.smk`，直接 include 即可。

### 3. Nextflow

参考 `workflow_skeleton/main.nf.template` 与 nf-core/isoseq
（`/Users/siyangming/nextflow_nf_core/isoseq.nf`），用
`nf-core modules install` 安装官方模块后组装。

## 容器运行注意

- native 容器统一走 Debian bookworm-slim + apt/micromamba 最小化路线，
  运行 `docker run` 时**必须加 `-u $(id -u):$(id -g)`** 避免 root 持有输出文件。
- uLTRA 路径需要 `ultra_bioinformatics` 环境（内置 minimap2/namfinder/samtools），
  未安装时请用 `--aligner minimap2`。
