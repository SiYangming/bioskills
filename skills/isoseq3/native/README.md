# isoseq3 / native — 自包含 isoseq3 refine 驱动

PacBio **IsoSeq3 refine**（去 polyA 尾与人工连接体）的本地自包含实现
（`source_type: custom`、`type: native`）。
> ⚠️ 命名差异：bioconda 包名为 **`isoseq`**，可执行二进制为 **`isoseq3`**
> （PacBio IsoSeq 套件入口，内含 refine / cluster / polish 等子命令）。本技能聚焦 `refine`。

## 功能

- `isoseq3 refine <bam> <primers> <out.bam>`：lima 产物 → 精炼 reads（polyA 修剪、去连接体）
- 默认 `--require-polya`（可用 `--no-require-polya` 关闭）
- `--min-polya-length`：polyA 尾最小长度
- 自动注入线程（`-j`，与 `--num-threads` 等价）
- 报告：`.consensusreadset.xml` / `.filter_summary.report.json` / `.report.csv` / `.pbi`（与输出同前缀）

## 用法

```bash
# CLI 直跑
python main.py refine --bam in.bam --primers primers.fasta --outdir out --prefix sample --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

子命令 `refine` 支持 `--threads` / `--tmpdir` 运行期覆盖。

## 环境安装（三选一）

### 1. Conda（HPC 无 root / 离线兜底）

```bash
mamba env create -f environment.yml   # name: isoseq3-native
conda activate isoseq3-native
```

### 2. Docker

```bash
docker build -t bioskills/isoseq3:4.0.0-v1.0 -f Dockerfile .
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/isoseq3:4.0.0-v1.0 refine --bam in.bam --primers primers.fasta --outdir out
```

### 3. Apptainer / Singularity

```bash
apptainer build isoseq3.sif Apptainer.def
apptainer run -B $PWD:/data -H /data isoseq3.sif \
    refine --bam /data/in.bam --primers /data/primers.fasta --outdir /data/out
```

## 测试

```bash
bash test/run_test.sh   # 合成最小 BAM；isoseq3 未安装时退化为 argv 构造验证
```

## 版本

- isoseq 4.0.0（bioconda::isoseq=4.0.0，binary `isoseq3`）
- 构建路线：debian:bookworm-slim + micromamba 引导 bioconda env（isoseq 不在 Debian apt）
