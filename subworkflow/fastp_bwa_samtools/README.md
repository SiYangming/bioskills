# custom / fastp_bwa_samtools

最小的短读 DNA 复合流程示例骨架，用来演示 **subworkflow/<组合名>/ 目录如何存档一个常见组合工作流**。

> 本目录提供的是 **存档 + 模板 + 编排骨架**，不是生产级可直接跑的 pipeline；
> 实际落地时仍需根据样本数、集群资源、队列参数去扩展。

## 组成

```
subworkflow/fastp_bwa_samtools/
├── meta.yaml                    # 流程级元数据（stages / inputs / outputs）
├── fastp_bwa_samtools.py          # 编排骨架：调用 skills/<sw>/native/main.py
└── workflow_skeleton/
    ├── Snakefile.template       # Snakemake 规则模板
    └── main.nf.template         # Nextflow DSL2 模板
```

## stage 图（DAG）

```
reads_R1,R2 ──► fastp (trim + QC)
                   │
                   ▼ clean_fq
               bwa-mem2 mem (reference.idx)
                   │
                   ▼ BAM
              samtools sort + index
                   │
                   ▼ sorted.bam + .bai
             (可选) multiqc 汇总
```

## 快速体验（dry-run，无外部依赖）

```bash
python subworkflow/fastp_bwa_samtools/fastp_bwa_samtools.py \
    --sample-id s001 \
    --reads-r1 /tmp/s001_R1.fq.gz \
    --reads-r2 /tmp/s001_R2.fq.gz \
    --reference /tmp/ref.fa \
    --outdir /tmp/out --dry-run
```

打印每个 stage 对应 skills 原生实现的命令（若 fastp / bwa-mem2 软件还未在 skills/ 中构建，会显示 `<MISSING>` 路径）。

## 如何把 subworkflow/<组合名> 变成“真正能跑”的流程

1. 在 `skills/fastp/`、`skills/bwa-mem2/`、`skills/multiqc/` 补齐 native 三件套；
2. 把 `--dry-run` 换成 `--real`，或直接改造 `workflow_skeleton/Snakefile.template`；
3. 根据 HPC / LSF / Slurm / Kubernetes，加 Snakemake `--profile` 或 Nextflow 配置文件。
