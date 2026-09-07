# gnu_sort 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# gnu_sort / native

自包含的 GNU sort 驱动实现（`source_type: custom`），命令逻辑：`sort [args] <in> > <out>.sorted`。

## 能力

| 子命令 | 说明 | 线程 |
|--------|------|------|
| `sort` | 文本行排序（`sort [args] <in> > <out>.sorted`，支持 `--args` 透传） | GNU 自动注入 `--parallel` |

## 快速开始

### 1. 安装环境

```bash
mamba create -n gnu-sort-native -c conda-forge coreutils=9.1
conda activate gnu-sort-native
```

### 2. CLI 调用

```bash
python main.py sort genes.gtf --args "-k1,1 -k4,4n" -o genes.sorted.gtf
python main.py sort reads.sam                 # 默认输出 reads.sam.sorted
python main.py sort counts.txt --args "-n -k1" --threads 8
```

### 3. Agent / Schema 自省

```bash
python main.py --schema              # 输出 JSON Schema
python main.py --list-commands       # 列出支持的子命令
```

### 4. 容器运行

```bash
docker build -t bioskills/gnu-sort:9.1-v1.0 -f Dockerfile .
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data bioskills/gnu-sort:9.1-v1.0 \
  sort /data/genes.gtf --args "-k1,1 -k4,4n" -o /data/genes.sorted.gtf
```

### 5. 测试

```bash
bash test/run_test.sh
```

## 性能优化约定

- **线程**：检测到 **GNU coreutils**（`sort --version` 含 "GNU coreutils"）时自动注入
  `--parallel=N`（默认 8）；macOS/BSD sort 不支持该选项，自动跳过。用户显式
  `--threads` 永远优先；`--args` 中已含 `--parallel` 时不再重复注入。
- **参数透传**：`--args` 原样传给 sort（如 `-k1,1 -k4,4n`、`-n`、`-S 2G`）。
- **临时目录**：`--tmpdir` 可覆盖 `$TMPDIR`（sort 大文件可用 `--args "-T <dir>"` 进一步控制）。

## 说明

- 成功后会在输出文件同目录写 `versions.yml`（与 nf-core/gnu/sort 对齐）。
- 说明：`sort` 子命令是历史 `sort_gtf` 规则（GTF 按染色体+起始位点排序）的通用版。


---

## snakemake 实现

# gnu_sort / snakemake / local — 自定义 Snakemake 实现

> 本目录为 snakemake-wrappers 官方缺失（bio/gnu 404）时的 **Snakemake 自维护 rule**
> （`source_type: custom`、`type: snakemake_local`）。td2 式：单规则文件 `gnu_sort.smk`
> config 驱动 + 同目录 script wrapper `gnu_sort.py`；`sort` 为系统基础工具，规则无同目录
> conda env（docker/native/conda 三模式分派）。

## 使用方式（config 契约见 gnu_sort.smk 头注与软件级 meta.yaml `snakemake_include_hint`）

```python
# Snakefile 中引入（可按需 use 重命名避免规则冲突）
include: "modules/gnu_sort/snakemake/gnu_sort.smk"

config.setdefault("gnu_sort", {}).setdefault("args", "-k1,1 -k4,4n")   # 示例：GTF 键排序

rule all:
    input: config["gnu_sort_output"]
```

```bash
# 独立运行（输出默认 = <输入>.sorted）
snakemake -s modules/gnu_sort/snakemake/gnu_sort.smk \
    --config gnu_sort_input=transcripts.gtf --cores 4
```

## 规则清单

| 规则 | 作用 | config 键 |
|------|------|-----------|
| `gnu_sort` | `sort <args> <in> > <out>.sorted`（args 由 config 透传） | `exec_mode` / `gnu_sort_input`(必填) / `gnu_sort_output` / `gnu_sort.{docker_image,sort_bin,args}` |

## 规则设计说明

- 参数统一经 `config["gnu_sort"]["args"]` 透传（如需按文件后缀切换参数，调用方可用
  `use rule ... from ...` 覆盖 `params.args`）。
- 规则 config 驱动：输入输出为显式 config 键（`gnu_sort_input` / `gnu_sort_output`，每任务一规则），无
  `{filepath}` 通配；不依赖流程级 `docker_run` / `GNU_SORT_DOCKER_IMAGE` 与 `workflow/lib/helpers.py`。
- 执行用同目录 `script:` wrapper `gnu_sort.py`（两级注入共享 `modules/docker_wrapper.py`）：docker 用
  `gnu_sort.docker_image`、native 用 `gnu_sort.sort_bin`、conda 走 PATH。
- 规则内声明 `log:`（stderr 重定向到 `gnu_sort.log`；stdout=排序结果进输出文件）。
- `sort_bin` 可用 config 覆盖（默认 `sort`，走系统 PATH）。


---

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# gnu_sort native Conda 环境配方（兜底：离线 / 非容器场景）
# 离线兜底：可另存为 gnu-sort-native.yml 后 mamba env create -f gnu-sort-native.yml；在线推荐上方 mamba create 直装命令
# 注意：coreutils 在 conda-forge（非 bioconda）。
name: gnu-sort-native
channels:
  - conda-forge
dependencies:
  - python=3.11
  - coreutils=9.1
  - pyyaml>=6.0
  - pip
  - pip:
      - -e .  # 若把 native/ 打包为可安装包（可选）
```

## 容器与 Conda 链接

- **Bioconda 页面**：https://anaconda.org/channels/bioconda/packages/gnu_sort/overview
- **Docker**：`docker pull quay.io/biocontainers/coreutils:9.11`
- **Singularity**：https://depot.galaxyproject.org/singularity/coreutils%3A9.11
- 安装方式（本地）：`mamba create -n gnu_sort -c conda-forge -c bioconda gnu_sort=9.11`
