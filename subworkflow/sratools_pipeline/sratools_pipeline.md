# subworkflow/sratools\_pipeline — SRA 批量获取（prefetch → FASTQ 转换 + 状态管理）

可复用的 **NCBI SRA 数据获取组合**：按 accession 列表**并行下载**（`prefetch`）→ **转 FASTQ**（`fasterq-dump` / `fastq-dump`，`--split-3 --gzip`），并附带一体化状态管理（`download | convert | status | stop | clean`）。参照 [subworkflow/fastp\_bwa\_samtools](../fastp_bwa_samtools/fastp_bwa_samtools.md) 与 [subworkflow/umi\_tools\_extract\_dedup](../umi_tools_extract_dedup/umi_tools_extract_dedup.md) 的 subworkflow 目录形态（md + meta.yaml + native/）。

* 元数据：同级 [meta.yaml](meta.yaml)（stages / inputs / outputs / execution）。

* **依赖**：单一原子技能 `modules/sra-tools`（[meta.yaml](../../modules/sra-tools/meta.yaml)）；两 stage 均委托其 **native** 实现（`sra-tools_native`，prefetch / fasterq-dump / fastq-dump 三子命令）。

* **为什么固化成组合**：SRA 下载 + 转 FASTQ 是 RNA-seq / WGS / 变异检测等流程的**公共前置数据获取环节**（nanoseq 原 batch\_prefetch.sh + batch\_sra\_to\_fastq*.sh），跨样本并行、失败记录、断点管理（停/续/清理）是反复出现的固定套路。

## Stage 图（DAG）

```
SRR_Acc_List.txt（每行一个 accession，# 注释 / 空行忽略）
        │
        ▼
   prefetch（并行；-f yes -t http；-O <download_dir>）
        │  每个 accession：<download_dir>/<srr_id>/<srr_id>.sra
        ▼
 fasterq-dump（默认，-e 线程 / -t 临时目录）或 fastq-dump（兼容旧版）
        │  --split-3 --gzip -O <fastq_dir>
        ▼
 fastq_files/<srr_id>_*.fastq[.gz]（PE 时 *_1/*_2 + 未配对）
```

stages 声明见 [meta.yaml](meta.yaml)：`sra_prefetch`（并行下载 .sra）→ `sra_to_fastq`（转 FASTQ）。

## 路线 A：经典一体化脚本 native/sra\_pipeline.sh

自包含批处理（合并自 `modules/sra-tools/native/` 的 batch\_prefetch.sh、batch\_prefetch 2.sh、batch\_sra\_to\_fastq.sh、batch\_sra\_to\_fastq\_parallel.sh），内置**锁 / PID / 主日志 / 失败记录**：

```bash
cd subworkflow/sratools_pipeline/native

./sra_pipeline.sh download                    # 并行 prefetch（默认 SRR_Acc_List.txt，--threads 4）
./sra_pipeline.sh convert                     # 并行 fastq-dump --split-3 --gzip
./sra_pipeline.sh convert --docker            # 走官方容器 quay.io/biocontainers/sra-tools
./sra_pipeline.sh status                      # 查看运行状态（PID + 实时日志）
./sra_pipeline.sh stop | clean                # 停止任务 / 强制清理并重跑
```

| 子命令 | 说明 | 关键选项 |
| --- | --- | --- |
| `download` | 并行 prefetch 下载 .sra | `--threads N` / `--srr-list FILE` |
| `convert` | 并行 fastq-dump 转 FASTQ | `--threads N` / `--docker` / `--docker-image IMG` |
| `status` / `stop` / `clean` | 状态管理：查看 / 正常停止 / 强停并清理 | — |
| `--help` | 帮助 | — |

输出（相对脚本目录 `native/`）：`sra_downloads/<srr>/<srr>.sra`、`fastq_files/`、`sra_downloads/sra_pipeline.log`、`sra_downloads/failed.txt`。脚本默认用 `SCRIPT_DIR/bin/` 下自带 binary（sratoolkit + parallel）或 Docker 模式，运行前按脚本头注释准备依赖。

## 路线 B：编排入口 native/main.py（逐 accession 委托模块）

入口：`python subworkflow/sratools_pipeline/native/main.py --list-stages | --dry-run（默认）| --real`（仓库根执行）。逐 accession **委托 `modules/sra-tools/native/main.py`**（等价能力先 CLI/main.py，后经典脚本，见 modules/sra-tools/README.md）：

```bash
# SRR 列表（占位）：
printf 'SRR12345678\nSRR23456789\n' > SRR_Acc_List.txt

# dry-run 预览（默认；不需要安装 sra-tools、不产生下载）
python subworkflow/sratools_pipeline/native/main.py --srr-list SRR_Acc_List.txt

# fastq-dump（兼容旧版）+ 自定义目录
python subworkflow/sratools_pipeline/native/main.py --srr-list SRR_Acc_List.txt \
    --dump-method fastq-dump --download-dir sra_downloads --fastq-dir fastq_files --threads 8

# 真实执行（需先装好 sra-tools；prefetch 先行、dump 随后）
python subworkflow/sratools_pipeline/native/main.py --srr-list SRR_Acc_List.txt --real
```

* 委托命令形态：`python modules/sra-tools/native/main.py prefetch <srr> -O <download_dir> --threads N`、`… fasterq-dump|fastq-dump <download_dir>/<srr>/<srr>.sra --split-3 --gzip -O <fastq_dir>`；
* `--list-stages` / `--dry-run` 无任何外部依赖可跑；`--real` 前请确认网络可达、磁盘充足并完成 prefetch；
* 模块未构建时打印 `<MISSING> <path>` 提示（不阻断 dry-run）。

## 引擎集成（执行方式 B/C：Snakemake / Nextflow）

本目录不内置引擎规则；按仓库「官方已有不重复建目录 + 流程集成层并入文档」规则，落地时在真实项目内接线：

* **Snakemake**：工具规则复用 `modules/sra-tools/snakemake/` 三个单规则 smk（每 rule 一文件、config 驱动）：

```python
include: "modules/sra-tools/snakemake/sra_prefetch.smk"
include: "modules/sra-tools/snakemake/sra_fasterq_dump.smk"   # 或 sra_fastq_dump.smk
```

* config 契约见各 smk 头注（顶层键 `sra_srr_id` / `sra_outdir` / `sra_input_sra` / `sra_dump_dir` / `sra_tmpdir` / `threads`）；配 `--use-conda`（环境 `modules/sra-tools/snakemake/sra-tools.yaml`，pin bioconda sra-tools=3.4.1）。

* **Nextflow**：官方 nf-core 已有 `sratools` 模块（注意**模块目录名为 sratools、无连字符**，与 canonical `sra-tools` 不同；子模块 `fasterqdump` + `prefetch`）：

```bash
nf modules install nf-core/sratools/fasterqdump
nf modules install nf-core/sratools/prefetch
```

```groovy
include { SRA_TOOLS_PREFETCH    } from './modules/nf-core/sratools/prefetch/main'
include { SRA_TOOLS_FASTERQDUMP } from './modules/nf-core/sratools/fasterqdump/main'
```

* 版本差异：nf-core sratools pin `sra-tools=3.2.1`（见 modules/sra-tools meta.yaml `software_versions`），与 native 的 3.4.1 不同——跨引擎迁移时按实际环境核对。

## 环境安装与版本

* 本组合依赖 **sra-tools=3.4.1**（native / bioconda 当前），安装方式（conda / Docker / Apptainer / 官方二进制）见 `modules/sra-tools/README.md`「环境安装（官方镜像优先，不维护本地配方）」；
* 官方镜像：`quay.io/biocontainers/sra-tools`（tag 以 quay / depot.galaxyproject.org 为准）；Docker run 一律加 `-u $(id -u):$(id -g)` 避免产物归 root；
* 经典脚本 `sra_pipeline.sh` 内置 Docker 模式默认 tag 为 `quay.io/biocontainers/sra-tools:3.2.1--h4304569_1`（与 meta 登记 3.4.1 略有差异，以 quay tag 为准）。

## 启用条件 / 注意事项

1. **网络与磁盘**：NCBI 可达（HTTP 默认），`.sra` 通常远大于最终 FASTQ，先估算磁盘；
2. **accession 列表**：每行一个（支持 `#` 注释 / 空行），PE 数据由 `--split-3` 自动拆 `*_1/*_2` + 未配对；
3. **断点管理**：大批量建议用路线 A（failed.txt 记录失败 accession，可续跑）；路线 B `--real` 按列表顺序 prefetch → dump 全量执行；
4. **临时目录**：`fasterq-dump -t <tmpdir>` 默认 `/tmp`，大样本建议指向大容量磁盘（meta `optimization` 已登记 TMPDIR 语义）。
