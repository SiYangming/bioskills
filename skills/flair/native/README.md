# flair / native — 自包含 isoform 分析驱动

FLAIR（Full-Length Alternative Isoform analysis of RNA）的本地自包含实现
（`source_type: custom`、`type: native`），命令逻辑迁移自
`snakemake.smk/nanoseq.smk/nanoseq.sh/run_flair_consensus.sh`（Nanopore direct RNA-seq 模式）。

## 功能

三个子命令对应 nanoseq 的 FLAIR_CONSENSUS 三段链路：

| 子命令 | 可执行 | 作用 |
|--------|--------|------|
| `bam2bed12` | `bam2Bed12` | sorted BAM → BED12（剪接结构） |
| `annotate` | `identify_gene_isoform` | BED12 + GTF → 带基因注释 BED |
| `collapse` | `flair` | 带注释 BED + genome + reads → 一致性转录本 FASTA |

`collapse` 完整迁移了 nanoseq 的 direct RNA-seq 优化参数：
`-q -g -r -o -t -f -s -w --trust_ends --remove_internal_priming --intprimingthreshold
--stringent --check_splice --mm2_args="-I8g,--MD" --quiet`。

## 用法

```bash
# CLI 直跑
python main.py bam2bed12 -i sample.sorted.bam -o sample.bed12
python main.py annotate sample.bed12 gencode.v49.annotation.gtf sample.annotated.bed
python main.py collapse -q sample.annotated.bed -g hg38.fa -r sample.fastq.gz \
    -o out/sample -f gencode.v49.annotation.gtf -s 3 -w 100 --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 环境安装（三选一）

### 1. Conda（HPC 无 root / 离线兜底）

```bash
mamba env create -f environment.yml   # name: flair-native（含 flair + minimap2）
conda activate flair-native
```

### 2. Docker

```bash
docker build -t bioskills/flair:3.0.0b1-v1.0 -f Dockerfile .
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/flair:3.0.0b1-v1.0 collapse \
    -q sample.annotated.bed -g hg38.fa -r sample.fastq.gz -o out/sample -f gencode.v49.annotation.gtf
```

### 3. Apptainer / Singularity

```bash
apptainer build flair.sif Apptainer.def
apptainer run -B $PWD:/data -H /data flair.sif collapse \
    -q /data/sample.annotated.bed -g /data/hg38.fa -r /data/sample.fastq.gz -o /data/out/sample
```

## 测试

```bash
bash test/run_test.sh   # 无需真实 long-read 数据；flair 未安装时退化为 argv 构造验证
```

## 版本

* flair 3.0.0b1（bioconda::flair=3.0.0b1，包内可执行 flair / bam2Bed12 / identify_gene_isoform）
* 依赖 minimap2=2.30（flair collapse 内部比对）
* 构建路线：debian:bookworm-slim + micromamba 引导 bioconda env（flair 不在 Debian apt）

## 历史留存（legacy/）

`legacy/` 存放迁移自 nanoseq 流程 `nanoseq.sh/run_flair_consensus.sh` 的原始脚本，仅供追溯对照，**正式入口为 `main.py`**。

- `run_flair_consensus.sh`
