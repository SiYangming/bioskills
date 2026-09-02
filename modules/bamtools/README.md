# bamtools 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# bamtools / native

自包含的 bamtools 驱动实现（`source_type: custom`）。

## 能力

覆盖 bamtools 高频子命令，Iso-Seq 场景下 BAM → FASTA/FASTQ 转换首选：

| 子命令 | 说明 |
|--------|------|
| `convert` | BAM → fasta/fastq/sam/bed/json/pileup/yaml（核心，迁移自 isoseq.py/bamtools_convert.py） |
| `count` | 统计 BAM 比对数量 |
| `stats` | 输出 BAM 基本统计 |
| `header` | 打印 BAM header |
| `index` | 建立 .bai 索引 |
| `sort` | 按 region/name/size 排序 BAM |

## 快速开始

### 1. 安装环境

```bash
mamba env create -f environment.yml
conda activate bamtools-native
```

### 2. CLI 调用

```bash
python main.py convert --bam refine.bam --outdir flnc --format fasta --prefix sample
python main.py stats --bam refine.bam
python main.py sort --bam in.bam --out sorted.bam --threads 8
python main.py index --bam sorted.bam
```

### 3. Agent / Schema 自省

```bash
python main.py --schema              # 输出 JSON Schema
python main.py --list-commands       # 列出支持的子命令
python main.py convert --bam x.bam --dry-run   # 只打印构建出的命令
```

### 4. 容器运行

```bash
docker build -t bioskills/bamtools:2.5.2-v1.0 -f Dockerfile .
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data bioskills/bamtools:2.5.2-v1.0 \
  convert --bam /data/refine.bam --outdir /data/flnc --format fasta
```

Apptainer：

```bash
apptainer build bamtools.sif Apptainer.def
apptainer run -B "$PWD":/data bamtools.sif convert --bam /data/refine.bam --outdir /data
```

### 5. 测试

```bash
bash test/run_test.sh
```

测试数据由 `test/generate_data.py` 用纯 Python 标准库动态生成合法 BGZF/BAM，
不依赖 samtools/pysam。

## 版本说明

- **native 二进制**：`bamtools 2.5.2`（Debian bookworm 官方 apt `2.5.2+dfsg-4`）。
- **Conda 兜底**：`environment.yml` 用 bioconda `bamtools=2.5.2`（HPC 无 root 场景）。
- 与流程原配（isoseq.smk 的 `quay.io/biocontainers/bamtools:2.5.2--hdcf5f25_2`）版本一致；
  snakemake-wrappers 侧已 bump 到 2.5.3，2.5.x API 兼容。

## 性能优化约定

- **线程**：bamtools CLI 无通用 `-@` 参数，`--threads` 作为契约字段接收，
  并在 `optimization.per_subcommand_threads` 中给出 sort 8 线程的调度建议。
- **临时目录**：`--tmpdir` 可覆盖 `TMPDIR`；`sort` 中间文件写入 `$TMPDIR`。
- **内存**：通过 `meta.yaml.optimization.default_mem_mb` 声明，供上层调度器读取。

## 历史留存（legacy/）

`legacy/` 存放迁移自原 isoseq.smk 流程 `isoseq.py/` 的原始实现脚本，仅供追溯对照，**正式入口为 `main.py`**。

- `bamtools_convert.py`


---

## snakemake 实现

# bamtools / snakemake / local — 自维护 Snakemake rule

从 `snakemake.smk/isoseq.smk/workflow/rules/bamtools.smk` 迁移的实际规则
（去掉对 `workflow/lib/helpers.py` 的全局依赖，`docker_run` 分支删除，路径内联）。

## 文件

| 文件 | 作用 |
|------|------|
| `bamtools_convert.smk` | `bamtools convert -format <fmt> -in <bam> -out <out>` 规则 |
| `meta.yaml` | 实现级 Schema（id: `bamtools_snakemake_local`） |

## 使用

在 Snakefile 中：

```python
include: "modules/bamtools/snakemake/bamtools_convert.smk"

rule all:
    input:
        "results/bamtools/sample1/sample1.chunk1.fasta",
```

或直接定义目标：

```python
python3 -m snakemake -s Snakefile results/bamtools/sample1/sample1.chunk1.fasta --cores 1
```

## 与 isoseq.smk 的差异

- 删除 `docker_run` 分支与 `BAMTOOLS_DOCKER_IMAGE` 容器配置（默认直接调用 `bamtools` 二进制）。
- `BAMTOOLS_BIN_PATH` / `BAMTOOLS_FORMAT` 由 `config["bamtools"]` 读取并内联默认值：
  - `bamtools_bin: "bamtools"`
  - `format: "fasta"`
- 仍写 `versions.yml`（与 nf-core 模块风格一致）。


---

## Conda 环境（原 native/environment.yml）

```yaml
# bamtools native Conda 环境配方
# 创建：mamba env create -f environment.yml
# 说明：Docker/Apptainer 走 apt 最小化路线（bamtools=2.5.2+dfsg-4），
#      本文件仅作 HPC 无 root 场景 / 非容器场景的 Conda 兜底。
name: bamtools-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - bamtools=2.5.2
  - pyyaml>=6.0
  - pip
```
