# minimap2 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# minimap2 / native

自包含的 minimap2 驱动实现（`source_type: custom`）。

## 能力

| 子命令 | 说明 |
|--------|------|
| `align` | reads → 参考基因组比对；`--bam` 输出 BAM（`minimap2 -a | samtools sort | samtools view -b -h`），否则输出 PAF |

支持 `--cigar-paf`（PAF 输出 CIGAR，`-c`）与 `--cigar-bam`（长 CIGAR 写 CG 标签，`-L`）；
不提供 `--reference` 时退化为 reads vs reads 自比对。命令逻辑迁移自 `isoseq.py/minimap2_align.py`，
与 nf-core `minimap2/align` 核心行为一致。

## 快速开始

### 1. 安装环境

```bash
mamba env create -f environment.yml
conda activate minimap2-native
```

### 2. CLI 调用

```bash
# PAF 输出
python main.py align --reads flnc.fa --reference ref.fa --outdir aln --prefix sample --threads 8

# BAM 输出（依赖 samtools）
python main.py align --reads flnc.fa --reference ref.fa --outdir aln --bam --threads 8

# 透传 minimap2 参数（splice 模式示例）
python main.py align --reads flnc.fa --reference ref.fa --outdir aln \
    --args "-x splice -uf -k14" --bam --threads 8
```

### 3. Agent / Schema 自省

```bash
python main.py --schema              # 输出 JSON Schema
python main.py --list-commands       # 列出支持的子命令
python main.py align --reads x.fa --reference r.fa --dry-run   # 只打印构建出的命令
```

### 4. 容器运行

```bash
docker build -t bioskills/minimap2:2.24-v1.0 -f Dockerfile .
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data bioskills/minimap2:2.24-v1.0 \
  align --reads /data/flnc.fa --reference /data/ref.fa --outdir /data/aln --bam --threads 8
```

Apptainer：

```bash
apptainer build minimap2.sif Apptainer.def
apptainer run -B "$PWD":/data minimap2.sif align --reads /data/flnc.fa --reference /data/ref.fa --outdir /data --bam
```

### 5. 测试

```bash
bash test/run_test.sh
```

## 版本说明

- **native 二进制**：`minimap2 2.24`（Debian bookworm 官方 apt `2.24+dfsg-3`）+ `samtools`（apt，BAM 管线）。
- **Conda 兜底**：`environment.yml` 用 bioconda `minimap2=2.24 + samtools=1.21`。
- **与流程原配差异**：isoseq.smk 原配为 bioconda `minimap2=2.28`（`quay.io/biocontainers/minimap2:2.28--h577a1d6_4`）。
  2.24 与 2.28 对本流程（Iso-Seq FLNC 比对）行为一致；若需完全对齐 2.28，
  用 micromamba 装 `bioconda::minimap2=2.28`（Dockerfile 注释已写明替换方式）。
- nf-core / snakemake-wrappers 侧版本见软件级 `meta.yaml` 的 `software_versions`。

## 性能优化约定

- **线程**：`align` 默认 8 线程（CPU 密集），用户显式 `--threads` 永远优先；`-t` 注入 minimap2，
  samtools sort/view 同步使用。
- **临时目录**：`--tmpdir` 覆盖 `$TMPDIR`；中间 SAM 走管道不落盘（`pipefail` 保证失败传导）。
- **内存**：通过 `meta.yaml.optimization.default_mem_mb` 声明，供上层调度器读取。

## 历史留存（legacy/）

`legacy/` 存放迁移自原 isoseq.smk 流程 `isoseq.py/` 的原始实现脚本，仅供追溯对照，**正式入口为 `main.py`**。

- `minimap2_align.py`


---

## snakemake 实现

# minimap2 / snakemake / local — 自维护 Snakemake rule

从 `snakemake.smk/isoseq.smk/workflow/rules/minimap2.smk` 迁移的实际规则
（去掉对 `workflow/lib/helpers.py` 的全局依赖，`docker_run` 分支删除，路径内联）。

## 文件

| 文件 | 作用 |
|------|------|
| `minimap2_align.smk` | `minimap2 -a <ref> <reads> | samtools sort | samtools view -b -h` 规则 |
| `meta.yaml` | 实现级 Schema（id: `minimap2_snakemake_local`） |

## 使用

在 Snakefile 中：

```python
include: "modules/minimap2/snakemake/minimap2_align.smk"

rule all:
    input:
        "results/minimap2/sample1/sample1.chunk1.bam",
        "results/minimap2/sample1/sample1.chunk1.bam.bai",
```

或直接定义目标：

```bash
snakemake -s Snakefile results/minimap2/sample1/sample1.chunk1.bam --cores 8
```

## 与 isoseq.smk 的差异

- 删除 `docker_run` 分支与 `MINIMAP2_DOCKER_IMAGE` / `SAMTOOLS_DOCKER_IMAGE` 容器配置。
- `get_minimap2_reads`（按 sample 查 mapping_direct_rows 表）内联为直接路径表达式
  `results/gstama/{sample}/{sample}.chunk{n}_gstama.fa.gz`。
- 参数由 `config["minimap2"]` 读取并内联默认值：
  - `minimap2_bin: "minimap2"`、`samtools_bin: "samtools"`
  - `reference` 默认 `config["minimap2"]["fasta"]`
  - `args` 默认空字符串
- 输出带 `.bam.bai`（rule 内 `samtools index`）与 `versions.yml`，与流程原版一致。


---

## Conda 环境（原 native/environment.yml）

```yaml
# minimap2 native Conda 环境配方
# 创建：mamba env create -f environment.yml
# 说明：Docker/Apptainer 走 apt 最小化路线（minimap2=2.24+dfsg-3 + samtools），
#      本文件仅作 HPC 无 root 场景 / 非容器场景的 Conda 兜底。
#      如需与 isoseq.smk 流程原配完全对齐，可把 minimap2 pin 改为 2.28。
name: minimap2-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - minimap2=2.24
  - samtools=1.21
  - pyyaml>=6.0
  - pip
```
