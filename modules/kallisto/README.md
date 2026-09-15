# kallisto 软件模块

> 汇总说明：本 README 合并各实现（native/官方 wrapper）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# kallisto / native — 自包含转录本定量驱动

Kallisto 的本地自包含实现（`source_type: custom`、`type: native`）。使用伪比对（pseudoalignment）算法，是目前最快的转录组定量工具之一。

## 功能

| 子命令 | 命令 | 作用 |
| --- | --- | --- |
| `index` | `kallisto index -i <index> <transcripts.fa> -t N` | 构建转录组伪比对索引 |
| `quant` | `kallisto quant -i <index> -b 100 -o <outdir> -t N <r1> <r2>` | 转录本定量（abundance.tsv / abundance.h5） |
| `inspect` | `kallisto inspect <index>` | 查看索引信息 |

## 用法

```bash
# CLI 直跑
python main.py index -i kallisto_index Trinity.fasta
python main.py quant -i kallisto_index -b 100 -o kallisto_out/A1 A1.1.fastq A1.2.fastq --threads 8
python main.py quant -i kallisto_index -b 100 --single -l 180 -s 20 -o kallisto_out/A1 A1.fastq
python main.py inspect kallisto_index

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：转录本索引 → 逐样本定量

Kallisto 使用伪比对算法（pseudoalignment），不生成完整比对结果，而是直接估计转录本丰度，速度比传统比对方法快数十倍。以下为文档典型批量用法；等价能力由 `native/main.py` 的 `index` / `quant` 子命令提供（见上「用法」）。

### 1. 构建索引

```bash
cd exp_cal
mkdir -p kallisto_out
kallisto index -i kallisto_index Trinity.fasta
```

### 2. 逐样本定量

```bash
for i in `ls ../*.1.fastq`
do
    i=${i/*\//}
    i=${i/.1.fastq/}
    kallisto quant -i kallisto_index -b 100 \
        -o kallisto_out/$i \
        ../$i.1.fastq ../$i.2.fastq
done
```

### 3. 结果说明

| 文件 | 说明 |
| --- | --- |
| `abundance.tsv` | 转录本水平定量结果（target_id / length / eff_length / est_counts / tpm） |
| `abundance.h5` | HDF5 格式结果（含 bootstrap 数据） |

`abundance.tsv`列名：

| 列名       | 说明                    |
| ---------- | ----------------------- |
| target_id  | 转录本ID                |
| length     | 转录本长度              |
| eff_length | 有效长度                |
| est_counts | 估计的count数           |
| tpm        | Transcripts Per Million |

### 4. 参数说明

| 参数 | 说明 |
| --- | --- |
| `-i` | 索引路径（index 输出 / quant 输入） |
| `-o` | 输出目录 |
| `-b` | bootstrap 重采样次数（默认 100） |
| `-t` | CPU 线程数 |
| `--single` | 单端模式，需配合 `-l`（平均片段长度）与 `-s`（标准差） |
| `-k` | index 的 k-mer 长度（默认 31） |

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。官方同时提供预编译二进制包（linux-x64 / macos-x64）与源码编译两条路线（均已核实，预编译为推荐首选）。

### 1. 官方预编译二进制包（首选）

```bash
# 官方 release 预编译包（linux-x64；macOS 用 kallisto_mac-v0.46.2.tar.gz）
wget https://github.com/pachterlab/kallisto/releases/download/v0.46.2/kallisto_linux-v0.46.2.tar.gz -P ~/software/
tar zxf ~/software/kallisto_linux-v0.46.2.tar.gz -C ~/software/
echo 'export PATH=$PATH:~/software/kallisto' >> ~/.bashrc
source ~/.bashrc
kallisto version   # 断言
```

> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `kallisto`，无 conda 时下载官方预编译包到 `~/software/kallisto-<ver>` 并写 PATH；版本默认 0.46.2，与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. 官方源码编译（并列保留）

```bash
# 需要 cmake + C++ 编译器 + zlib/htslib 等依赖
git clone https://github.com/pachterlab/kallisto.git
cd kallisto
mkdir build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX=~/software/kallisto-0.46.2
make -j 4
make install
export PATH=$PATH:~/software/kallisto-0.46.2/bin && kallisto version   # 断言
```

### 3. Conda / brew（包管理器安装）

```bash
mamba create -n kallisto-native -c conda-forge -c bioconda kallisto=0.46.2
conda activate kallisto-native
kallisto version   # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
brew install kallisto
kallisto version   # 断言（brew 当前 0.52.0，与 meta 登记 0.46.2 略有差异，以 formula 为准）
```

### 4. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/kallisto:0.46.2--h60f4f9f_2
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/kallisto:0.46.2--h60f4f9f_2 \
    quant -i /data/kallisto_index -b 100 -o /data/kallisto_out/A1 /data/A1.1.fastq /data/A1.2.fastq
```

### 5. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull kallisto.sif docker://depot.galaxyproject.org/singularity/kallisto:0.46.2--h60f4f9f_2
apptainer run -B $PWD:/data -H /data kallisto.sif version
```

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（index/quant/inspect），无需已安装 kallisto
```

## 版本

* kallisto 0.46.2（bioconda::kallisto=0.46.2；quay tag `0.46.2--h60f4f9f_2`）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/kallisto / depot.galaxyproject.org；本地不再自建容器）；官方另提供 linux-x64 / macos-x64 预编译二进制包与源码编译路线

## 容器与 Conda 链接

* **官网**：https://kallisto.readthedocs.io/en/latest/

* **GitHub**：https://github.com/pachterlab/kallisto
* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/kallisto/overview>

* **Docker**：`docker pull quay.io/biocontainers/kallisto:0.46.2--h60f4f9f_2`

* **Singularity**：<https://depot.galaxyproject.org/singularity/kallisto%3A0.46.2--h60f4f9f_2>

* 安装方式（本地）：`mamba create -n kallisto -c conda-forge -c bioconda kallisto=0.46.2`

***

## 官方实现登记（不建目录）

* **nf-core modules**：`modules/nf-core/kallisto/index`、`modules/nf-core/kallisto/quant`，pin `bioconda::kallisto=0.51.1`。执行前请 `nf-core modules install kallisto index quant` 安装到项目自身目录，不要直接引用本仓库示例。

* **snakemake-wrappers**：`bio/kallisto/index`、`bio/kallisto/quant`，环境 pin `kallisto=0.52.0`。运行时靠 `wrapper: "v9.17.1/bio/kallisto/quant"` 句柄解析，不要把本地示例当 `wrapper_path`。
