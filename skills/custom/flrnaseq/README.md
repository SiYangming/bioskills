# custom/flrnaseq — 全长 RNA-seq ORF 预测复合流程

从原 `snakemake.smk/flrnaseq.smk` 迁移重构而来：工具拆分为**原子模块软件技能**，
本目录仅保留「流程编排层」。

## 流程结构

```
全长转录本 FASTA
├──> [transdecoder]  LongOrfs -> Predict   -> {sample}.pep/.cds/.gff3/.bed
├──> [td2]           TD2.LongOrfs -> TD2.Predict -> {sample}.pep/.cds/.gff3/.bed
└──> [orffinder]     ORFfinder（outfmt=2）  -> {sample}.asn1
```

## 依赖的原子模块技能

| 阶段           | 软件技能                          | 主要入口                                  |
| ------------ | ----------------------------- | ------------------------------------- |
| TransDecoder | `skills/transdecoder/native/` | `python main.py longorfs/predict ...` |
| TD2          | `skills/td2/native/`          | `python main.py longorfs/predict ...` |
| ORFfinder    | `skills/orffinder/native/`    | `python main.py run ...`              |

每个软件技能内同时提供 `nextflow/nf-core/`（说明层）、`snakemake/local/*.smk`（迁移规则）
与 `native/legacy/`（原始 scripts 留存）。

## 用法

### 1. Python 编排器（dry-run 默认）

```bash
python skills/custom/flrnaseq/flrnaseq.py \
    --samplesheet samples.csv --outdir results

python skills/custom/flrnaseq/flrnaseq.py ... --real   # 真实执行
```

`samples.csv` 至少含 `sample` 与 `long_read_fasta`（全长转录本 FASTA 路径）。

### 2. Snakemake

参考 `workflow_skeleton/Snakefile.template`，各步骤规则已迁移到
`skills/{transdecoder,td2,orffinder}/snakemake/local/*.smk`，直接 include 即可。

### 3. Nextflow

原流程为 Snakemake 实现，无 nf-core 官方流程；可用各模块
`nextflow/local` 自行组装（模板见 `workflow_skeleton/main.nf.template`）。

## Docker 执行支持

原 flrnaseq.smk 通过 `workflow/scripts/docker_wrapper.py` 支持 docker 执行；
各原子模块容器已按 Debian bookworm-slim + micromamba 最小化构建，
`docker run` 时必须加 `-u $(id -u):$(id -g)`。

## 历史留存资产（来自原 flrnaseq.smk）

| 资产                  | 位置                                                                         | 说明                                                                                |
| ------------------- | -------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| 原生 Python 实现        | 各模块 `native/legacy/*.py`                                                   | transdecoder\_longorfs/transdecoder\_predict/td2\_longorfs/td2\_predict/orffinder |
| Snakemake 规则        | 各模块 `snakemake/local/*.smk`                                                | 迁移自原 workflow/rules/                                                              |
| 单元测试                | `skills/transdecoder\|td2/native/test/unit/`                               | 原 .tests/unit（transdecoder\_longorfs/predict、td2\_predict 用例 + common/conftest）   |
| 原流程骨架               | `workflow_skeleton/LEGACY_Snakefile`                                       | 原 workflow/Snakefile                                                              |
| 流程 config + schemas | `workflow_skeleton/config/`                                                | 原 config/config.yaml + schemas/{config,samples}\_schema.yaml                      |
| ORFanage 实现         | `skills/orfanage/`（独立模块）                                                   | 原 orfrange\_archive/ 已归位为 orfanage 技能（native/legacy 存原始文件）                        |
| 批处理脚本               | `skills/td2/native/legacy/run_td2_orf_prediction.sh` + `LEGACY_run_smk.sh` | 原 flrnaseq.sh/run\_td2\_orf\_prediction.sh / run\_smk.sh                          |
| Docker 包装脚本         | `workflow_skeleton/scripts/docker_wrapper.py`                              | 原 workflow/scripts/docker\_wrapper.py（docker/native/conda 三模式）                    |
| 原始 envs             | `workflow_skeleton/envs/`                                                  | 原 workflow/envs/{orffinder,python,td2,transdecoder}.yaml                          |
| 原始规则                | `workflow_skeleton/LEGACY_RULES/`                                          | 原 workflow/rules/{common,orffinder,td2,transdecoder}.smk（完整原始版）                   |

