# ultra / native

自包含的 uLTRA 驱动实现（`source_type: custom`），命令逻辑迁移自
`snakemake.smk/isoseq.smk/isoseq.py/ULTRA_align.py` 与 `workflow/modules/ultra/snakemake/local/ultra.smk`。

## 能力

| 子命令 | 说明 | 线程 |
|--------|------|------|
| `gunzip` | 解压 .gz 文件（`gzip -cd <in.gz> > <out>`） | — |
| `index` | `uLTRA index <fasta> <gtf> <outdir> [--disable_infer]`，产出 `*.pickle` / `*.db` | 8（调度提示） |
| `align` | `uLTRA align <genome> <reads> <outdir> --t N --prefix <p> --index <dir>` 后接 `samtools sort` → BAM | ✅ |
| `sort` | GTF 排序 `sort -k1,1 -k4,4n`（index 前置步骤） | — |

运行前提：`uLTRA`、`samtools`、`minimap2`、`namfinder` 需在 PATH（align 子命令会预检依赖）。

## 快速开始

### 1. 安装环境

```bash
mamba env create -f environment.yml
conda activate ultra-native
```

### 2. CLI 调用

```bash
# 解压参考/reads
python main.py gunzip genome.fa.gz -o genome.fa
# GTF 排序（index 前置）
python main.py sort genes.gtf --outdir . --prefix genes
# 建索引（默认 --disable_infer）
python main.py index genome.fa genes.sorted.gtf idx_dir
# 比对 + samtools sort -> BAM
python main.py align genome.fa reads.fa aln_dir --index idx_dir --prefix sample --threads 8
```

### 3. Agent / Schema 自省

```bash
python main.py --schema              # 输出 JSON Schema
python main.py --list-commands       # 列出支持的子命令
```

### 4. 容器运行

```bash
docker build -t bioskills/ultra:0.1-v1.0 -f Dockerfile .
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data bioskills/ultra:0.1-v1.0 \
  index /data/genome.fa /data/genes.sorted.gtf /data/idx_dir --args "--disable_infer"
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data bioskills/ultra:0.1-v1.0 \
  align /data/genome.fa /data/reads.fa /data/aln --index /data/idx_dir --prefix sample --threads 8
```

### 5. 测试

```bash
bash test/run_test.sh
```

## 性能优化约定

- **线程**：`index` / `align` 默认 8 线程（CPU 密集）；`align` 会把 `--t` 同时注入 uLTRA 与
  `samtools sort --threads`；用户显式 `--threads` 永远优先。
- **临时目录**：中间文件统一落在 `outdir` / `$TMPDIR`（`--tmpdir` 可覆盖），避免污染工作目录。
- **依赖路径**：`align` 自动把 minimap2 / namfinder / samtools 所在目录并入 PATH（镜像内为 /opt/conda/bin）。

## 与 isoseq.smk 的对应关系

| 本技能子命令 | 迁移来源 |
|--------------|----------|
| `gunzip` | `ULTRA_align.py:subcmd_gunzip` |
| `index` | `ULTRA_align.py:subcmd_index` + `ultra.smk:ultra_index` |
| `align` | `ULTRA_align.py:subcmd_align` + `ultra.smk:ultra_align` |
| `sort` | `ULTRA_align.py:subcmd_sort` + `ultra.smk:sort_gtf` |

## 历史留存（legacy/）

`legacy/` 存放迁移自原 isoseq.smk 流程 `isoseq.py/` 的原始实现脚本，仅供追溯对照，**正式入口为 `main.py`**。

- `ULTRA_align.py`
