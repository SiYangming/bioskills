# gnu_sort / native

自包含的 GNU sort 驱动实现（`source_type: custom`），命令逻辑迁移自
`snakemake.smk/isoseq.smk/workflow/modules/gnu_sort/snakemake/local/gnu_sort.smk`（`sort [args] <in> > <out>.sorted`）。

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
- 与 isoseq.smk 对应关系：`sort` ← `workflow/modules/gnu_sort/snakemake/local/gnu_sort.smk`（`sort_gtf` 的通用版）。
