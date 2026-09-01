# orffinder / native — 自包含 ORF 预测驱动

**ORFfinder**（NCBI 开放阅读框查找工具，本地版）的自包含实现（`source_type: custom`、`type: native`）。
conda 包 `orffinder=0.4.3` 提供二进制 **`ORFfinder`**（来自 NCBI，flrnaseq 流程对应
`quay.io/preskaa/orffinder:0.4.3`）。

## 功能

* `run`：在核酸序列中查找 ORF 并输出蛋白翻译

  `ORFfinder -in <fasta> -out <file> -outfmt <int> [-g <code>] [-s <0|1|2>] [-ml <nt>] [-strand <both|plus|minus>] [-n]`

* 输出格式（`-outfmt`，与 flrnaseq config.yaml suffix_map 一致）：
  - `0` → ORFs FASTA（后缀 `_orf.fa`）
  - `1` → CDS FASTA（后缀 `_cds.fa`）
  - `2` → Text ASN.1（后缀 `.asn1`，flrnaseq 默认）
  - `3` → Feature table（后缀 `.ft`）

* 自动解压 `.gz` 输入、自动生成默认输出路径、注入 `TMPDIR`

## 用法

```bash
# CLI 直跑（参数与 flrnaseq config.yaml orffinder 段对应）
python main.py run -in transcripts.fa -out out/result.asn1 -outfmt 2 --start-codon 2 --min-length 30

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

子命令 `run` 支持 `--threads` / `--tmpdir` 运行期覆盖（ORFfinder 单线程，线程数仅调度参考）。

## 环境安装（三选一）

### 1. Conda（HPC 无 root / 离线兜底）

```bash
mamba env create -f environment.yml   # name: orffinder-native（orffinder=0.4.3）
conda activate orffinder-native
```

### 2. Docker

```bash
docker build -t bioskills/orffinder:0.4.3-v1.0 -f Dockerfile .
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/orffinder:0.4.3-v1.0 \
    run -in transcripts.fa -out out/result.asn1 -outfmt 2 --start-codon 2 --min-length 30
```

### 3. Apptainer / Singularity

```bash
apptainer build orffinder.sif Apptainer.def
apptainer run -B $PWD:/data -H /data orffinder.sif \
    run -in /data/transcripts.fa -out /data/out/result.asn1 -outfmt 2 --start-codon 2 --min-length 30
```

## 测试

```bash
bash test/run_test.sh   # 无需真实核酸序列；工具未装时退化为 argv 构造验证
```

## 版本

* orffinder 0.4.3（bioconda orffinder=0.4.3 / quay.io/preskaa/orffinder:0.4.3，二进制 ORFfinder 来自 NCBI）

* 构建路线：debian:bookworm-slim + micromamba 引导 bioconda env（orffinder 不在 Debian apt）

## 历史留存（legacy/）

`legacy/` 存放迁移自 flrnaseq.smk 流程 `workflow/scripts/` 的原始 Snakemake wrapper 脚本，
仅供追溯对照，**正式入口为 `main.py`**。

- `orffinder.py` — ORFfinder 原始 wrapper（snakemake.shell + docker_wrapper）
