# lima / native — 自包含驱动

PacBio **条形码拆分与引物去除**的本地自包含实现（`source_type: custom`、`type: native`）。
二进制名与 conda 包名均为 **`lima`**。

## 功能

- `lima <reads> <primers> <out>`：去引物 / 按条形码拆分（reads 支持 bam/fasta/fasta.gz/fastq/fastq.gz）
- 输出扩展名按输入格式自动推断（bam→bam、fastq.gz→fastq.gz …）
- Iso-Seq 模式：`--isoseq` / `--peek-guess`
- 质量阈值：`--min-score`
- 报告产物：`.counts` / `.report` / `.summary` / `.json` / `.xml` / `.clips`（与输出同前缀）
- 自动注入线程（`-j`）与 `TMPDIR`

## 用法

```bash
# CLI 直跑
python main.py lima reads.bam primers.fasta out/demux.bam --isoseq --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

子命令 `lima` 支持 `--threads` / `--tmpdir` 运行期覆盖。

## 环境安装（三选一）

### 1. Conda（HPC 无 root / 离线兜底）

```bash
mamba env create -f environment.yml   # name: lima-native
conda activate lima-native
```

### 2. Docker

```bash
docker build -t bioskills/lima:2.9.0-v1.0 -f Dockerfile .
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/lima:2.9.0-v1.0 lima reads.bam primers.fasta out/demux.bam --isoseq
```

### 3. Apptainer / Singularity

```bash
apptainer build lima.sif Apptainer.def
apptainer run -B $PWD:/data -H /data lima.sif \
    lima /data/reads.bam /data/primers.fasta /data/out/demux.bam --isoseq
```

## 测试

```bash
bash test/run_test.sh   # 合成最小 BAM；lima 未安装时退化为 argv 构造验证
```

## 版本

- lima 2.9.0（bioconda::lima=2.9.0）
- 构建路线：debian:bookworm-slim + micromamba 引导 bioconda env（lima 不在 Debian apt）

## 历史留存（legacy/）

`legacy/` 存放迁移自原 isoseq.smk 流程 `isoseq.py/` 的原始实现脚本，仅供追溯对照，**正式入口为 `main.py`**。

- `lima_analysis.py`
