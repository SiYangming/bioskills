# dorado / native — 自包含 basecalling 驱动

Dorado（Oxford Nanopore 官方 basecaller）的本地自包含实现
（`source_type: custom`、`type: native`），命令逻辑提炼自
`snakemake.smk/nanoseq.smk/config/config.yaml` 的 `dorado` 段（`enable_dorado` 开关、
`model: rna004_130bps_sup@v5.1.0`、`docker_image: docker.1ms.run/nanoporetech/dorado:latest`）
与 dorado 官方 CLI 用法。nanoseq 流程中 dorado 为**可选**环节（`enable_dorado: false` 时跳过）。

## 功能

两个子命令覆盖 nanoseq / dorado 官方的高频用法：

| 子命令        | 命令                                                                                         | 作用                                                            |
| ---------- | ------------------------------------------------------------------------------------------ | ------------------------------------------------------------- |
| `basecall` | `dorado basecaller <model> <reads> --emit-fastq [--output-dir] [--device] [--num-workers]` | POD5/FAST5 原始信号 → FASTQ（RNA 用 `rna004_130bps_sup@v5.1.0` 等模型） |
| `demux`    | `dorado demux <reads> [--kit-name] [--output-dir]`                                         | 按 barcode 拆分 reads                                            |

nanoseq Snakefile 中的 dorado 规则（`dorado basecaller <model> <pod5> --estimate-poly-a > <fastq>`）
由 `basecall` 子命令 + `--estimate-poly-a`（经 `--extra-args` 透传）等价覆盖。

## 用法

```bash
# CLI 直跑
python main.py basecall rna004_130bps_sup@v5.1.0 pod5_dir/ --output-dir out --emit-fastq --threads 8
python main.py demux reads.fastq --kit-name SQK-RNA004-24 --output-dir demux_out

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 环境安装（三选一）

### 1. Conda（HPC 无 root / 离线兜底）

```bash
mamba env create -f environment.yml   # name: dorado-native（仅 python 驱动；dorado 二进制需单独下载）
# dorado 官方二进制（不在 bioconda）：
curl -Ls https://cdn.oxfordnanoportal.com/software/analysis/dorado-<ver>-linux-x64.tar.gz | tar -xz
export PATH=$PWD/dorado-<ver>-linux-x64/bin:$PATH
```

### 2. Docker

```bash
docker build -t bioskills/dorado:latest-v1.0 -f Dockerfile .   # --build-arg DORADO_VERSION=<release> 可 pin
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/dorado:latest-v1.0 basecall \
    rna004_130bps_sup@v5.1.0 pod5/ --output-dir out --emit-fastq
# 建议挂载模型缓存目录（dorado 首次运行会自动下载模型，体积较大）
```

### 3. Apptainer / Singularity

```bash
apptainer build dorado.sif Apptainer.def
apptainer run -B $PWD:/data -H /data dorado.sif basecall \
    rna004_130bps_sup@v5.1.0 /data/pod5/ --output-dir /data/out --emit-fastq
```

## 测试

```bash
bash test/run_test.sh   # dorado basecaller 需要真实 POD5 + 模型，本脚本退化为 argv 构造验证
```

## 版本

* dorado：latest（官方 release，如 0.9.x / 0.10.x；Dockerfile 用 `ARG DORADO_VERSION` 可 pin）

* 不在 Debian bookworm apt、不在 bioconda；容器走 bookworm-slim + 官方二进制下载路线

* Docker 直用建议：`docker.1ms.run/nanoporetech/dorado:latest`（nanoseq config 默认）

## 历史留存（legacy/）

nanoseq 流程中 dorado **无 shell 脚本**（`nanoseq.sh/` 下没有 dorado 脚本），只有
`config/config.yaml` 的 dorado 配置段，因此 `legacy/` 目录以 README 记录该 config 段原文，
不做脚本留存。dorado 的 native 命令逻辑按 config 默认值 + 官方 CLI 在 `main.py` 实现。

* `legacy/README.md`（config 段说明）


## 历史说明（来自原 legacy/README.md）

nanoseq 流程中 dorado 无 shell 脚本（nanoseq.sh/ 下没有 dorado 脚本），
仅通过 config 的 dorado 段配置 basecall 参数；native 实现见 main.py 的 basecall 子命令。
