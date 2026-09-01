# transdecoder / native — 自包含 ORF 预测驱动

**TransDecoder**（转录本 CDS 预测）的本地自包含实现（`source_type: custom`、`type: native`）。
conda 包 `transdecoder=5.7.1` 提供两个二进制：**`TransDecoder.LongOrfs`** 与 **`TransDecoder.Predict`**。

## 功能

* `longorfs`：提取候选最长 ORF → 生成 `<prefix>.transdecoder_dir/` 中间目录（longest_orfs.pep/cds/gff3）

  `TransDecoder.LongOrfs -t <fasta> -O <dir> [--gene_trans_map <gtm>] [-m <aa>] [-G <code>] [-S] [--complete_orfs_only]`

* `predict`：基于序列组成模型预测最终 CDS → 输出 `<prefix>.transdecoder.{pep,cds,gff3,bed}`

  `TransDecoder.Predict -t <fasta> -O <dir> [--retain_pfam_hits] [--retain_blastp_hits] [--single_best_only] [--no_refine_starts] --cpu <N>`

* 自动解压 `.gz` 输入、自动注入线程（`--cpu`）与 `TMPDIR`

## 用法

```bash
# CLI 直跑（参数与 flrnaseq config.yaml transdecoder 段对应）
python main.py longorfs -t transcripts.fa -O out --min-protein-length 50 --genetic-code Universal --strand-specific --complete-orfs-only
python main.py predict  -t transcripts.fa -O out --retain-pfam-hits pfam.domtblout --retain-blastp-hits blastp.outfmt6 --no-refine-starts --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

子命令 `longorfs` / `predict` 均支持 `--threads` / `--tmpdir` 运行期覆盖。

## 环境安装（三选一）

### 1. Conda（HPC 无 root / 离线兜底）

```bash
mamba env create -f environment.yml   # name: transdecoder-native（transdecoder=5.7.1 + perl + parallel）
conda activate transdecoder-native
```

### 2. Docker

```bash
docker build -t bioskills/transdecoder:5.7.1-v1.0 -f Dockerfile .
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/transdecoder:5.7.1-v1.0 \
    longorfs -t transcripts.fa -O out --min-protein-length 50 --strand-specific
```

### 3. Apptainer / Singularity

```bash
apptainer build transdecoder.sif Apptainer.def
apptainer run -B $PWD:/data -H /data transdecoder.sif \
    longorfs -t /data/transcripts.fa -O /data/out --min-protein-length 50
```

## 测试

```bash
bash test/run_test.sh   # 无需真实转录本 FASTA；工具未装时退化为 argv 构造验证
```

## 版本

* transdecoder 5.7.1（bioconda::transdecoder=5.7.1，二进制 TransDecoder.LongOrfs / TransDecoder.Predict）

* 构建路线：debian:bookworm-slim + micromamba 引导 bioconda env（transdecoder 不在 Debian apt）

## 历史留存（legacy/）

`legacy/` 存放迁移自 flrnaseq.smk 流程 `workflow/scripts/` 的原始 Snakemake wrapper 脚本，
仅供追溯对照，**正式入口为 `main.py`**。

- `transdecoder_longorfs.py` — TransDecoder.LongOrfs 原始 wrapper（snakemake.shell + docker_wrapper）
- `transdecoder_predict.py` — TransDecoder.Predict 原始 wrapper（snakemake.shell + docker_wrapper）

## 历史单元测试（test/unit/）

`test/unit/` 存放迁移自原 flrnaseq.smk `.tests/unit/` 的原始单元测试（test_transdecoder_longorfs.py / test_transdecoder_predict.py + common.py/conftest.py），供追溯对照与 pytest 回归；`test/run_test.sh` 为技能自带的最小回归。
