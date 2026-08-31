# gstama / native

自包含的 gstama 驱动实现（`source_type: custom`），命令逻辑迁移自 `isoseq.py/gs_tama.py` + `tama_polyacleanup.py`。

## 能力

| 子命令 | 说明 | 依赖 |
|--------|------|------|
| `polyacleanup` | TAMA FLNC polyA 清理并 gzip 输出 | `tama_flnc_polya_cleanup.py` |
| `collapse` | 转录本去冗余（collapse） | `tama_collapse.py` + `samtools` |
| `filelist` | 由 collapse bed 生成 merge 用 TSV | 无（纯 Python） |
| `merge` | 合并多来源转录本集合 | `tama_merge.py` |

Iso-Seq 链路：`bamtools convert` → `polyacleanup` → `minimap2 align` → `collapse` → `filelist` → `merge`。

## 快速开始

### 1. 安装环境

```bash
mamba env create -f environment.yml
conda activate gstama-native
```

### 2. CLI 调用

```bash
# polyA 清理（bamtools convert 的 FASTA 输出）
python main.py polyacleanup --fasta flnc.fa --outdir gstama --prefix sample

# collapse（输入 minimap2 排序 BAM + 参考）
python main.py collapse --bam aln.bam --fasta ref.fa --outdir collapse --prefix sample

# filelist（纯 Python 生成 TSV）
python main.py filelist --bed-dir collapse/beds --outdir filelist --prefix fl

# merge
python main.py merge --filelist filelist/fl.tsv --outdir merge --prefix merged
```

### 3. Agent / Schema 自省

```bash
python main.py --schema              # 输出 JSON Schema
python main.py --list-commands       # 列出支持的子命令
python main.py collapse --bam x.bam --fasta r.fa --dry-run   # 只打印构建出的命令
```

### 4. 容器运行

```bash
docker build -t bioskills/gstama:1.0.3-v1.0 -f Dockerfile .
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data bioskills/gstama:1.0.3-v1.0 \
  collapse --bam /data/aln.bam --fasta /data/ref.fa --outdir /data/collapse
```

Apptainer：

```bash
apptainer build gstama.sif Apptainer.def
apptainer run -B "$PWD":/data gstama.sif polyacleanup --fasta /data/flnc.fa --outdir /data
```

### 5. 测试

```bash
bash test/run_test.sh
```

`filelist` 子命令不依赖任何外部工具（纯 Python），无 gs-tama 环境也能端到端验证；
`polyacleanup/collapse/merge` 需 gs-tama 脚本（bioconda `gs-tama=1.0.3`），未安装时测试自动降级为命令构建自检。

## 版本说明

- **二进制来源**：bioconda `gs-tama=1.0.3`（apt 无此包），包提供
  `tama_flnc_polya_cleanup.py` / `tama_collapse.py` / `tama_merge.py` 到 env `bin/`。
- **容器路线**：Dockerfile / Apptainer.def 用 **micromamba** 引导 bioconda env（禁止 miniconda），
  驱动 main.py 由 env python 运行。
- `collapse` 依赖 `samtools`（tama_collapse.py 内部调用），容器 env 已含 `samtools=1.21`。

## 性能优化约定

- TAMA 脚本为单线程；`--threads` 作为契约字段接收，供上层调度器参考。
- `--tmpdir` 覆盖 `$TMPDIR`；所有中间产物落在 `--outdir` 内。

## 历史留存（legacy/）

`legacy/` 存放迁移自原 isoseq.smk 流程 `isoseq.py/` 的原始实现脚本，仅供追溯对照，**正式入口为 `main.py`**。

- `gs_tama.py, tama_polyacleanup.py`
