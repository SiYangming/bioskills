# pbccs / native — 自包含 ccs 驱动

PacBio **CCS（HiFi）一致性序列生成**的本地自包含实现（`source_type: custom`、`type: native`）。
conda 包名为 `pbccs`，可执行二进制为 **`ccs`**。

## 功能

* `ccs <subreads.bam> <out.bam>`：subreads BAM → HiFi/CCS BAM

* 分块并行：`--chunk N/TOTAL`（大型样本按 ZMW 分块，可多机并行）

* 过滤阈值：`--min-rq --min-passes --min-snr --min-length --max-length --top-passes`

* 报告：`--report-file --report-json --metrics-json`（与输出同前缀自动生成）

* 自动注入线程（`-j`）与 `TMPDIR`

## 用法

```bash
# CLI 直跑
python main.py ccs --subreads sample.subreads.bam --outdir out --chunk-num 1 --chunk-total 4 --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

子命令 `ccs` 支持 `--threads` / `--tmpdir` 运行期覆盖。

## 环境安装（三选一）

### 1. Conda（HPC 无 root / 离线兜底）

```bash
mamba env create -f environment.yml   # name: pbccs-native
conda activate pbccs-native
```

### 2. Docker

```bash
docker build -t bioskills/pbccs:6.4.0-v1.0 -f Dockerfile .
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/pbccs:6.4.0-v1.0 ccs --subreads sample.subreads.bam --outdir out --chunk-num 1 --chunk-total 1
```

### 3. Apptainer / Singularity

```bash
apptainer build pbccs.sif Apptainer.def
apptainer run -B $PWD:/data -H /data pbccs.sif \
    ccs --subreads /data/sample.subreads.bam --outdir /data/out --chunk-num 1 --chunk-total 1
```

## 测试

```bash
bash test/run_test.sh   # 无需真实 subreads BAM；ccs 未安装时退化为 argv 构造验证
```

## 版本

* pbccs 6.4.0（bioconda::pbccs=6.4.0，二进制 `ccs`）

* 构建路线：debian:bookworm-slim + micromamba 引导 bioconda env（pbccs 不在 Debian apt）

## 历史留存（legacy/）

`legacy/` 存放迁移自原 isoseq.smk 流程 `isoseq.py/` 的原始实现脚本，仅供追溯对照，**正式入口为 `main.py`**。

- `ccs_analysis.py`
