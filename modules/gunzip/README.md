# gunzip 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# gunzip / native

自包含的 gunzip 驱动实现（`source_type: custom`），命令逻辑：`gzip -cd <in.gz> > <out>`。

## 能力

| 子命令 | 说明 | 线程 |
|--------|------|------|
| `gunzip` | 解压 .gz 文件（`gzip -cd <in.gz> > <out>`） | —（单线程） |

## 快速开始

### 1. 安装环境

```bash
mamba create -n gunzip-native -c conda-forge gzip=1.12
conda activate gunzip-native
```

### 2. CLI 调用

```bash
python main.py gunzip genome.fa.gz -o genome.fa
python main.py gunzip reads.fq.gz          # 默认输出 reads.fq
```

### 3. Agent / Schema 自省

```bash
python main.py --schema              # 输出 JSON Schema
python main.py --list-commands       # 列出支持的子命令
```

### 4. 容器运行

```bash
docker build -t bioskills/gunzip:1.12-v1.0 -f Dockerfile .
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data bioskills/gunzip:1.12-v1.0 \
  gunzip /data/genome.fa.gz -o /data/genome.fa
```

### 5. 测试

```bash
bash test/run_test.sh
```

## 说明

- 二进制为 `gzip`（`gunzip` 是其硬链接前端）；`gzip -cd` 同时兼容 GNU gzip 与 macOS 系统 gzip。
- 成功后会在输出文件同目录写 `versions.yml`（与 nf-core/gunzip 对齐）。
- 临时目录/线程参数（`--tmpdir` / `--threads`）按 skill 统一契约保留；`gzip -cd` 本身单线程。


---

## snakemake 实现

# gunzip / snakemake / local — 自定义 Snakemake 实现

> 本目录为 snakemake-wrappers 官方缺失（bio/gunzip 404）时的 **Snakemake 自维护 rule**
> （`source_type: custom`、`type: snakemake_local`）。td2 式：单规则文件 `gunzip.smk`
> config 驱动 + 同目录 script wrapper `gunzip.py`；`gzip` 为系统基础工具，规则无同目录
> conda env（docker/native/conda 三模式分派）。

## 使用方式（config 契约见 gunzip.smk 头注与软件级 meta.yaml `snakemake_include_hint`）

```python
# Snakefile 中引入（可按需 use 重命名避免规则冲突）
include: "modules/gunzip/snakemake/gunzip.smk"

rule all:
    input: config["gunzip_output"]
```

```bash
# 独立运行（输出默认 = 输入去 .gz）
snakemake -s modules/gunzip/snakemake/gunzip.smk \
    --config gunzip_input=ref.fa.gz --cores 1
```

## 规则清单

| 规则 | 作用 | config 键 |
|------|------|-----------|
| `gunzip` | `gzip -cd <in.gz> > <out>`（stdout=解压内容进输出文件，stderr 进 log） | `exec_mode` / `gunzip_input`(必填) / `gunzip_output` / `gunzip.{docker_image,gzip_bin}` |

## 规则设计说明

- 规则 config 驱动：输入输出为显式 config 键（`gunzip_input` / `gunzip_output`，每任务一规则），无
  `{filepath}` 通配；不依赖流程级 `docker_run` / `GUNZIP_DOCKER_IMAGE` 与 `workflow/lib/helpers.py`。
- 执行用同目录 `script:` wrapper `gunzip.py`（两级注入共享 `modules/docker_wrapper.py`）：docker 用
  `gunzip.docker_image`、native 用 `gunzip.gzip_bin`、conda 走 PATH。
- 规则内声明 `log:`（stderr 重定向到 `gunzip.log`；stdout=解压内容进输出文件）。
- `gzip_bin` 可用 config 覆盖（默认 `gzip`，走系统 PATH）。


---

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# gunzip native Conda 环境配方（兜底：离线 / 非容器场景）
# 离线兜底：可另存为 gunzip-native.yml 后 mamba env create -f gunzip-native.yml；在线推荐上方 mamba create 直装命令
# 注意：gzip 在 conda-forge（非 bioconda）。
name: gunzip-native
channels:
  - conda-forge
dependencies:
  - python=3.11
  - gzip=1.12
  - pyyaml>=6.0
  - pip
  - pip:
      - -e .  # 若把 native/ 打包为可安装包（可选）
```

## 容器与 Conda 链接

- **Bioconda 页面**：https://anaconda.org/channels/bioconda/packages/gunzip/overview
- **Docker**：`docker pull quay.io/biocontainers/gzip:1.11`
- **Singularity**：https://depot.galaxyproject.org/singularity/gzip%3A1.11
- 安装方式（本地）：`mamba create -n gunzip -c conda-forge -c bioconda gunzip=1.11`
