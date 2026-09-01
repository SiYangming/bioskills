# td2 / native — 自包含 ORF 预测驱动

**TD2**（TransDecoder 继任者，转录本 CDS 预测）的本地自包含实现（`source_type: custom`、`type: native`）。
conda 包 `td2=1.0.6` 提供两个二进制：**`TD2.LongOrfs`** 与 **`TD2.Predict`**。

## 功能

* `longorfs`：提取候选最长 ORF → 输出 `longest_orfs.{pep,cds,gff3}` 到 `-O` 目录

  `TD2.LongOrfs -t <fasta> -O <dir> [--gene-trans-map <gtm>] [-m <aa>] [-M <aa>] [-G <code>] [-S] [--alt-start] [--all-stopless] [--complete-orfs-only] --threads <N>`

* `predict`：基于 PSAURON + 长度模型预测最终 CDS → 输出 `<prefix>.TD2.{pep,cds,gff3,bed}`

  `TD2.Predict -t <fasta> -O <dir> [--retain-mmseqs-hits] [--retain-blastp-hits] [--retain-hmmer-hits] [--psauron-all-frame] [--all-good] --threads <N>`

* 自动解压 `.gz` 输入、自动注入线程（`--threads`）与 `TMPDIR`

> 注意：TD2 的 `-O` 即最终输出目录（与 TransDecoder 会建子目录不同）；
> `TD2.Predict` 的 `-O` 通常直接指向 LongOrfs 产物目录。

## 用法

```bash
# CLI 直跑（参数与 flrnaseq config.yaml td2 段对应）
python main.py longorfs -t transcripts.fa -O out --min-length 90 --abs-min-length 90 --genetic-code 1 --strand-specific --alt-start --all-stopless
python main.py predict  -t transcripts.fa -O out --retain-mmseqs-hits hits.m8 --retain-blastp-hits blastp.outfmt6 --retain-hmmer-hits pfam.domtblout --psauron-all-frame --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

子命令 `longorfs` / `predict` 均支持 `--threads` / `--tmpdir` 运行期覆盖。

## 环境安装（三选一）

### 1. Conda（HPC 无 root / 离线兜底）

```bash
mamba env create -f environment.yml   # name: td2-native（td2=1.0.6）
conda activate td2-native
```

### 2. Docker

```bash
docker build -t bioskills/td2:1.0.6-v1.0 -f Dockerfile .
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/td2:1.0.6-v1.0 \
    longorfs -t transcripts.fa -O out --strand-specific
```

### 3. Apptainer / Singularity

```bash
apptainer build td2.sif Apptainer.def
apptainer run -B $PWD:/data -H /data td2.sif \
    longorfs -t /data/transcripts.fa -O /data/out --strand-specific
```

## 测试

```bash
bash test/run_test.sh   # 无需真实转录本 FASTA；工具未装时退化为 argv 构造验证
```

## 版本

* td2 1.0.6（bioconda::td2=1.0.6，二进制 TD2.LongOrfs / TD2.Predict）

* 构建路线：debian:bookworm-slim + micromamba 引导 bioconda env（td2 不在 Debian apt）

* ⚠️ 版本差异：nf-core master 当前 pin `bioconda::td2=1.1.0`（比本实现 1.0.6 新），跨引擎迁移时注意。

## 历史留存（legacy/）

`legacy/` 存放迁移自 flrnaseq.smk 流程 `workflow/scripts/` 的原始 Snakemake wrapper 脚本，
仅供追溯对照，**正式入口为 `main.py`**。

- `td2_longorfs.py` — TD2.LongOrfs 原始 wrapper（snakemake.shell + docker_wrapper）
- `td2_predict.py` — TD2.Predict 原始 wrapper（snakemake.shell + docker_wrapper）

## 历史单元测试（test/unit/）

`test/unit/` 存放迁移自原 flrnaseq.smk `.tests/unit/` 的原始单元测试（td2_predict 用例 + common.py/conftest.py），供追溯对照与 pytest 回归；`test/run_test.sh` 为技能自带的最小回归。
