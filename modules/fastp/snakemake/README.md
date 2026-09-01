# fastp / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 的 `bio/fastp` 存在（单 wrapper，见 `../snakemake-wrappers/`），
本目录提供自维护规则作为 **离线 / 中央缓存不可用 / 本地定制** 场景的兜底
（`source_type: custom`、`type: snakemake_local`）。

## 规则文件

- `fastp.smk` — `rule fastp`：
  - 输入：`reads/{sample}_R1.fastq.gz` + `reads/{sample}_R2.fastq.gz`（PE）
  - 输出：`results/fastp/{sample}_{R1,R2}.clean.fastq.gz` + `_fastp.html` + `_fastp.json`
  - 日志：`results/fastp/logs/fastp_{sample}.log`
  - 命令：`fastp -i R1 -I R2 -o out1 -O out2 -h html -j json -w <threads>`
  - 文件底部附 `fastp_se` 单端变体（注释状态，按需启用）

> ⚠️ fastp 0.20+ 线程参数为 `-w/--thread`（`-t` 已被 `--trim_tail1` 占用）。

## 用法

```python
# Snakefile 中
include: "modules/fastp/snakemake/fastp.smk"

# 运行
snakemake -j 8 results/fastp/sample1_R1.clean.fastq.gz
```

可选 `config["fastp"]`（缺省自动跳过）：

```yaml
# config.yaml
fastp:
  adapter_sequence: "AGATCGGAAGAGCACACGTCTGA"   # R1 3' 接头（IUPAC）
  detect_adapter_for_pe: true                    # PE 重叠检测
  qualified_quality_phred: 15
  unqualified_percent_limit: 40
  length_required: 15
  extra: "--cut_front --cut_tail --cut_right 1"  # 额外透传
```

## 依赖环境

规则直接调用本地 `fastp` 二进制；如需隔离环境，规则内加
`conda: "envs/fastp.yaml"`：

```yaml
# envs/fastp.yaml
channels: [conda-forge, bioconda]
dependencies:
  - fastp=0.24.0
```

## 与其它实现的关系

- 官方 wrapper 存在：`../snakemake-wrappers/`（tag v3.13.0，pin fastp=1.3.6）；
  联网 / 中央缓存可用时优先 wrapper，本规则兜底
- 非 Snakemake 场景（独立 CLI / Agent Function Calling / fastp_bwa_samtools 编排器）请走 `../../native/`
