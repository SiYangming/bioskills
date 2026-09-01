# fastqc

bioskills 软件级存档：[FastQC](https://www.bioinformatics.babraham.ac.uk/projects/fastqc/) 质控工具。
官方 / 自定义 / 自包含实现共存，路由规则详见根目录 [AGENT.md](/Users/siyangming/GitHub/bioskills/AGENT.md)。

## 实现总览（5 种）

| id | 路径 | source | 优先级 | 说明 |
|---|---|---|---|---|
| `fastqc_native`              | `native/`                     | custom  | High | AI Agent / CLI 首选（自包含三件套） |
| `fastqc_nextflow_nfcore`     | `nextflow/nf-core/`           | official| Medium | 标准 Nextflow 流程用官方模块 |
| `fastqc_nextflow_local`      | `nextflow/local/`             | custom  | Low    | 官方模块不满足时占位 |
| `fastqc_snakemake_wrappers`  | `snakemake/snakemake-wrappers/`| official| Medium | 标准 Snakemake 流程用官方 wrapper |
| `fastqc_snakemake_local`     | `snakemake/`            | custom  | Low    | 官方 wrapper 不满足时占位 |

## 快速使用

```bash
# Native（Agent/CLI）
python modules/fastqc/native/main.py run sample_R1.fq.gz -o qc_out --threads 8 --java-mem-mb 16384

# validate + schema + scan（用 project skill-cli）
python3 modules/bin/skill-cli validate modules/fastqc/native
python3 modules/bin/skill-cli scan
```
