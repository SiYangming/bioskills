# ultra 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# ultra / native

自包含的 uLTRA 驱动实现（`source_type: custom`），命令逻辑迁移自
`snakemake.smk/isoseq.smk/isoseq.py/ULTRA_align.py` 与 `workflow/modules/ultra/snakemake/ultra.smk`。

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


---

## snakemake 实现

# ultra / snakemake / local — 自定义 Snakemake 实现

> 本目录为 snakemake-wrappers 官方缺失（bio/ultra 404）时的 **Snakemake 自维护 rule**。
> 规则从 `snakemake.smk/isoseq.smk/workflow/modules/ultra/snakemake/ultra.smk` 迁移，去掉了对
> `workflow/lib/helpers.py` 的全局依赖（get_sample_species / get_ultra_reads /
> get_index_flag / SPECIES_INFO 等），改为 config 驱动 + 内联简化。

## 使用方式

```python
# Snakefile 中引入（可按需 use 重命名避免规则冲突）
include: "modules/ultra/snakemake/ultra.smk"
# 或
use rule prepare_genome, prepare_gtf, sort_gtf, ultra_index, ultra_align \
    from rule_ultra as ultra_prepare_genome, ultra_prepare_gtf, ultra_sort_gtf, ultra_index, ultra_align
```

## 规则清单

| 规则 | 作用 | 迁移自 |
|------|------|--------|
| `prepare_genome` | 解压/软链参考基因组到 `resources/{species}/genome.fa` | `ultra.smk:prepare_genome` |
| `prepare_gtf` | 解压 + 去 `#` 注释行到 `resources/{species}/genes.gtf` | `ultra.smk:prepare_gtf` |
| `sort_gtf` | `sort -k1,1 -k4,4n` → `genes.sorted.gtf` | `ultra.smk:sort_gtf` |
| `ultra_index` | `uLTRA index <fa> <gtf> <outdir> [--disable_infer]`，touch `INDEX/{species}/done` | `ultra.smk:ultra_index` |
| `ultra_align` | `uLTRA align ... --index <idx>` + `samtools sort` → BAM | `ultra.smk:ultra_align` |

## 需要的配置（在 Snakefile 中先声明）

```python
config.setdefault("ultra", {})
config["ultra"].setdefault("ultra_bin", "uLTRA")
config["ultra"].setdefault("index_args", "--disable_infer")
config["ultra"].setdefault("align_args", "")
config["samtools"].setdefault("samtools_bin", "samtools")
# 物种 -> 参考路径映射（替代原 helpers.SPECIES_INFO + get_sample_species）
config.setdefault("species_genome", {"hg38": "refs/hg38.fa.gz"})   # 按需改
config.setdefault("species_gtf",   {"hg38": "refs/hg38.gtf"})
config.setdefault("resources_dir", "resources")
config.setdefault("output_dir", "results")
config.setdefault("ultra_dir", "results/ULTRA")
```

## 与原 isoseq.smk 的差异

- 移除 `helpers.get_ultra_reads`：`ultra_align` 的 reads 输入改为显式通配
  `reads/{sample}.fa.gz`（可在 `use rule` 后按项目覆盖 input）。
- 移除 `helpers.get_index_flag`：`ultra_align` 的 `index_flag` 依赖
  `INDEX/{species}/done`，由调用方保证 `{species}` 通配符与 `ultra_index` 一致。
- `threads: 8` 保留（align/index CPU 密集）；容器/conda 由调用方在 rule 外声明。


---

## Conda 环境（原 native/environment.yml）

```yaml
# ultra native Conda 环境配方（兜底：HPC 无 root / 非容器场景）
# 创建：mamba env create -f environment.yml
# 注意：Debian apt 无 ultra 包，uLTRA 仅由 bioconda 提供；minimap2 / namfinder /
#       samtools 为 uLTRA 运行时依赖（align 子命令按 PATH 查找），必须同环境安装。
name: ultra-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - ultra_bioinformatics=0.1
  - minimap2
  - namfinder
  - samtools
  - pyyaml>=6.0
  - pip
  - pip:
      - -e .  # 若把 native/ 打包为可安装包（可选）
```
