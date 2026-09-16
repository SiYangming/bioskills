# maker 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；容器与 conda 环境信息记录于文末「容器与 Conda 链接」。
> 官方 nf-core / snakemake-wrappers 均无 MAKER 实现（2026-09 抓取 404，见「版本」），故仅登记 native。

***

## native 实现

# maker / native — 自包含综合基因注释驱动

MAKER 综合基因组注释流水线的本地自包含实现（`source_type: custom`、`type: native`；Perl 驱动）。

## 功能

MAKER 是一个综合基因预测工具，可以整合多种证据（EST、蛋白、重复序列等）进行基因预测。

四个子命令对应 MAKER 的配置 → 运行 → 汇总链路：

| 子命令           | 命令                                                         | 作用                          |
| ------------- | ---------------------------------------------------------- | --------------------------- |
| `ctl`         | `maker -CTL`                                               | 生成 maker_opts.ctl / maker_exe.ctl / maker_bopts.ctl |
| `run`         | `[mpiexec -n N] maker <genome> ...`                        | 运行注释（可 MPI 并行）              |
| `merge`       | `gff3_merge -d <genome>_master_datastore_index.log [-o out]` | 汇总各分区为一个 GFF                 |
| `fasta_merge` | `fasta_merge -d <genome>_master_datastore_index.log`        | 汇总 transcript/cds/protein FASTA |

> 线程优先级：`--threads` > `per_subcommand_threads`（run=8 / merge=2）> `default_cpus`；仅 `run --mpi` 时经 `mpiexec -n <threads>` 透传。

## 用法

```bash
# CLI 直跑
python main.py ctl
python main.py run genome.fasta -est Trinity.fasta -protein homolog.fasta \
    -model_org fungi -rmlib consensi.fa -est2genome -protein2genome -trna
python main.py run genome.fasta --mpi --threads 8
python main.py merge genome.maker.output/genome_master_datastore_index.log -o genome.all.gff
python main.py fasta_merge genome.maker.output/genome_master_datastore_index.log

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：MAKER 综合注释

MAKER 整合 EST、同源蛋白、重复序列与从头预测器（AUGUSTUS/SNAP/GeneMark）进行基因预测。以下为典型流程；等价能力由 `native/main.py` 的 4 个子命令提供（见上「用法」）。

### 1. 准备输入文件

```bash
mkdir -p maker && cd maker
ln -s ../genome.fasta .
ln -s ../Trinity.fasta .
gzip -dc protein.faa.gz > homolog.fasta
perl -p -i -e 'if (m/^>/) { s/\s+.*//; s/\./_/g; }' homolog.fasta   # 清理蛋白 ID
ln -s ../RepeatModeler_database.consensi.fa consensi.fa
ln -s ../genemark_es_et/es/output/gmhmm.mod .
ln -s ../snap/species.hmm .
```

### 2. 准备配置文件

```bash
# 生成配置模板
maker -CTL

# 修改 maker_opts.ctl（基因组 / 证据 / 重复库 / 从头预测模型）
perl -p -i -e 's/^genome=.*/genome=genome.fasta/; s/^est=.*/est=Trinity.fasta/; \
  s/^protein=.*/protein=homolog.fasta/; s/^model_org=.*/model_org=fungi/; \
  s/^rmlib=.*/rmlib=consensi.fa/; s/^augustus_species=.*/augustus_species=malassezia_sympodialis/; \
  s/^snaphmm=.*/snaphmm=species.hmm/; s/^gmhmm=.*/gmhmm=gmhmm.mod/; \
  s/^est2genome=.*/est2genome=1/; s/^protein2genome=.*/protein2genome=1/; \
  s/^trna=.*/trna=1/; s/^keep_preds=.*/keep_preds=1/;' maker_opts.ctl

# 若 RepeatMasker 为自建路径，修改 maker_exe.ctl
perl -p -i -e 's#RepeatMasker=.*#RepeatMasker=/opt/biosoft/RepeatMasker/RepeatMasker#' maker_exe.ctl
```

### 3. 并行运行 MAKER

```bash
mpiexec -n 8 maker -fix_nucleotides &> maker.log
```

### 4. 处理结果

```bash
cd genome.maker.output
gff3_merge -d genome_master_datastore_index.log
grep -P "\tmaker\t" genome.all.gff > genome.maker.gff3
```

> **桥接**：上述命令等价于 `python main.py ctl` / `python main.py run ... --mpi --threads 8` / `python main.py merge <log>`；下游过滤（`grep maker`）为纯文本后处理。

### 5. 参数说明

| 参数                        | 说明                |
| ------------------------- | ----------------- |
| `genome=`                 | 基因组序列文件           |
| `est=`                    | EST/转录本序列文件        |
| `protein=`                | 同源蛋白序列文件          |
| `model_org=`              | 物种模型类型（如 fungi）    |
| `augustus_species=`       | AUGUSTUS 物种参数      |
| `snaphmm=` / `gmhmm=`     | SNAP / GeneMark HMM 模型文件 |
| `est2genome=` / `protein2genome=` | 直接用 EST / 蛋白证据预测 |
| `trna=`                   | 预测 tRNA           |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；`main.py` 驱动在宿主机跑。
MAKER 上游**不提供预编译二进制**（官方源码发行包需在官网注册获取），故本地安装走 conda；源码编译小节并列保留。

### 依赖工具（MAKER 运行依赖）

MAKER 为 Perl 驱动流水线，运行依赖以下工具（conda 安装会自动带入大部分）：

* **AUGUSTUS**（从头预测，`augustus_species`）
* **SNAP**（从头预测，`snaphmm`）
* **GeneMark-ES/ET**（从头预测，`gmhmm`；需另配 `~/.gm_key` 密钥）
* **RepeatMasker** / **RepeatModeler**（重复序列屏蔽与库构建，`rmlib`）
* **tRNAscan-SE**（`trna=1` 时；MAKER 自带/依赖旧版本）
* **exonerate**（蛋白序列比对）
* **MPI（mpich）**（并行运行，`mpiexec`）

### 1. Conda（包管理器安装）

```bash
mamba create -n maker -c conda-forge -c bioconda maker=3.01.03
conda activate maker
maker --version   # 断言
```

> Homebrew 无 MAKER 公式，故不登记 brew 块。
>
> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `maker`；MAKER 无官方预编译二进制，故二进制路线直接报错并指引 conda / 官网注册。版本默认 3.01.03，与 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/maker:3.01.03--pl5321h9ce0226_4
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/maker:3.01.03--pl5321h9ce0226_4 maker -CTL
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull maker.sif docker://depot.galaxyproject.org/singularity/maker:3.01.03--pl5321h9ce0226_4
apptainer run -B $PWD:/data -H /data maker.sif maker -CTL
```

### 4. 官方源码编译（并列保留）

* **官网**：<https://yandell-lab.org/software/maker/>
* **下载**：<http://yandell.topaz.genetics.utah.edu/cgi-bin/maker_license.cgi>（**需填写信息注册后**获取下载链接）
* **GitHub**：<https://github.com/Yandell-Lab/maker>

MAKER 为 Perl 驱动（`perl Build.PL && ./Build install`）。旧教程的直链分发主机（`yandell.topaz.genetics.utah.edu/maker_downloads/...`）当前不可达（2026-09 核实），须经官网注册获取 `maker-3.01.03.tgz` 后编译：

```bash
# 官网注册获取 maker-3.01.03.tgz 后：
tar zxf ~/software/maker-3.01.03.tgz -C ~/software/
cd ~/software/maker/src/
perl Build.PL
# 交互式选择 MPI（Y）并指定 mpicc / mpi.h 路径
./Build install
echo 'export PATH=$PATH:~/software/maker/bin' >> ~/.bashrc
source ~/.bashrc
maker --version   # 验证
```

## 测试

```bash
bash test/run_test.sh   # 全部子命令退化为 argv 构造验证（MAKER 真实运行需完整证据集与依赖工具）
```

## 版本

* maker `3.01.03`（bioconda::maker=3.01.03；bioconda 另有 3.01.04）
* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/maker / depot.galaxyproject.org；本地不再自建容器）
* Perl 驱动：`perl Build.PL && ./Build install`；依赖 AUGUSTUS / SNAP / GeneMark / RepeatMasker / tRNAscan-SE / RepeatModeler / exonerate / MPI
* 官方 nf-core module（`modules/nf-core/maker`）与 snakemake-wrappers（`bio/maker`）均无（2026-09 抓取 404）

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/maker>
* **Docker**：`docker pull quay.io/biocontainers/maker:3.01.03--pl5321h9ce0226_4`
* **Singularity**：<https://depot.galaxyproject.org/singularity/maker%3A3.01.03--pl5321h9ce0226_4>
* 安装方式（本地）：`mamba create -n maker -c conda-forge -c bioconda maker=3.01.03`
