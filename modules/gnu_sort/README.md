# gnu_sort 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# gnu_sort / native

自包含的 GNU sort 驱动实现（`source_type: custom`），命令逻辑迁移自
`snakemake.smk/isoseq.smk/workflow/modules/gnu_sort/snakemake/gnu_sort.smk`（`sort [args] <in> > <out>.sorted`）。

## 能力

| 子命令 | 说明 | 线程 |
|--------|------|------|
| `sort` | 文本行排序（`sort [args] <in> > <out>.sorted`，支持 `--args` 透传） | GNU 自动注入 `--parallel` |

## 快速开始

### 1. 安装环境

```bash
mamba env create -f environment.yml
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
- 与 isoseq.smk 对应关系：`sort` ← `workflow/modules/gnu_sort/snakemake/gnu_sort.smk`（`sort_gtf` 的通用版）。


---

## snakemake 实现

# gnu_sort / snakemake / local — 自定义 Snakemake 实现

> 本目录为 snakemake-wrappers 官方缺失（bio/gnu 404）时的 **Snakemake 自维护 rule**。
> 规则从 `snakemake.smk/isoseq.smk/workflow/modules/gnu_sort/snakemake/gnu_sort.smk` 迁移，去掉了对
> `workflow/lib/helpers.py` 的全局依赖（`get_gnu_sort_args` 的后缀 override 逻辑）。

## 使用方式

```python
# Snakefile 中引入（可按需 use 重命名避免规则冲突）
include: "modules/gnu_sort/snakemake/gnu_sort.smk"
# 或
use rule gnu_sort from rule_gnu_sort as gnu_sort
```

## 规则清单

| 规则 | 作用 | 迁移自 |
|------|------|--------|
| `gnu_sort` | `sort <args> <in> > <out>.sorted`（args 由 config 透传） | `gnu_sort.smk:gnu_sort` |

## 示例

```python
# 目标：把 results/xxx.gtf 排序为 results/xxx.gtf.sorted
config["gnu_sort"] = {"args": "-k1,1 -k4,4n"}

rule gnu_sort_demo:
    input:  "results/{filepath}.gtf"
    output: "results/{filepath}.gtf.sorted"
```

## 与原 isoseq.smk 的差异

- 移除 `helpers.get_gnu_sort_args`（按后缀 override）：简化为 `config["gnu_sort"]["args"]`
  单一透传；如需按文件后缀切换参数，在调用方用 `use rule ... from ...` 覆盖 `params.args`。
- 移除 `docker_run` / `GNU_SORT_DOCKER_IMAGE`（容器由调用方在 rule 上声明）。
- `sort_bin` 保留 config 可覆盖（默认 `sort`）。


---

## Conda 环境（原 native/environment.yml）

```yaml
# gnu_sort native Conda 环境配方（兜底：离线 / 非容器场景）
# 创建：mamba env create -f environment.yml
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
