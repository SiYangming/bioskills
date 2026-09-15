# salmon 软件模块

> 汇总说明：本 README 合并各实现（native/官方 wrapper）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# salmon / native — 自包含转录本定量驱动

Salmon 的本地自包含实现（`source_type: custom`、`type: native`）。使用准映射（quasi-mapping）算法，速度快、内存占用低。

## 功能

| 子命令 | 命令 | 作用 |
| --- | --- | --- |
| `index` | `salmon index -t <transcripts.fa> -i <index> --type quasi -k 31 -p N` | 构建转录组 quasi-mapping 索引 |
| `quant` | `salmon quant -i <index> -l A -1 <r1> -2 <r2> -p N --validateMappings -o <out>` | 转录本水平定量（TPM/NumReads） |
| `quantmerge` | `salmon quantmerge --quants <dir...> -o <out>` | 合并多样本定量结果 |

## 用法

```bash
# CLI 直跑
python main.py index -t Trinity.fasta -i salmon_index -k 31
python main.py quant -i salmon_index -1 A1.1.fastq -2 A1.2.fastq -o salmon_out/A1 --threads 8
python main.py quant -i salmon_index -r A1.fastq -o salmon_out/A1 --threads 8   # 单端
python main.py quantmerge --quants salmon_out/A1 salmon_out/A2 -o merged/quant

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：转录本索引 → 逐样本定量 → 表达矩阵

Salmon 使用准映射算法（quasi-mapping），不生成完整比对结果，直接估计转录本丰度，兼顾速度与精度。以下为文档典型批量用法；等价能力由 `native/main.py` 的 `index` / `quant` / `quantmerge` 子命令提供（见上「用法」）。

### 1. 构建索引

```bash
cd exp_cal
mkdir -p salmon_out
salmon index -t Trinity.fasta -i salmon_index --type quasi -k 31
```

### 2. 逐样本定量

```bash
for i in `ls ../*.1.fastq`
do
    i=${i/*\//}
    i=${i/.1.fastq/}
    salmon quant -i salmon_index -l A \
        -1 ../$i.1.fastq -2 ../$i.2.fastq \
        -p 8 --validateMappings \
        -o salmon_out/$i
done
```

### 3. 结果说明

| 文件 | 说明 |
| --- | --- |
| `quant.sf` | 转录本水平定量结果（Name / Length / EffectiveLength / TPM / NumReads） |
| `quant.genes.sf` | 基因水平定量结果（需提供基因-转录本映射） |

`quant.sf`的文件列含义：

| 列名            | 说明                    |
| --------------- | ----------------------- |
| Name            | 转录本ID                |
| Length          | 转录本长度              |
| EffectiveLength | 有效长度                |
| TPM             | Transcripts Per Million |
| NumReads        | 估计的read数            |

### 4. 参数说明

| 参数 | 说明 |
| --- | --- |
| `-i` | 索引目录（index 输出 / quant 输入） |
| `-t` | 转录本 FASTA（index） |
| `-l` | 文库类型，A 表示自动推断 |
| `-1/-2` | 双端 fastq；单端用 `-r` |
| `-p` | CPU 线程数 |
| `--validateMappings` | 开启准映射验证，提高定量精度 |
| `-o` | 输出目录 |

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。官方同时提供 linux-x64 预编译二进制包与源码编译两条路线（均已核实，预编译为推荐首选；v1.3.0 无 macOS 预编译资产，macOS 用户请走 conda）。

### 1. 官方预编译二进制包（首选）

```bash
# 官方 release 预编译包（linux-x64）
wget https://github.com/COMBINE-lab/salmon/releases/download/v1.3.0/salmon-1.3.0_linux_x86_64.tar.gz -P ~/software/
tar zxf ~/software/salmon-1.3.0_linux_x86_64.tar.gz -C ~/software/
echo 'export PATH=$PATH:~/software/salmon-latest_linux_x86_64/bin/' >> ~/.bashrc
source ~/.bashrc
salmon --version   # 断言
```

> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `salmon`，无 conda 时下载官方 linux-x64 预编译包到 `~/software/salmon-<ver>` 并写 PATH；版本默认 1.3.0，与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. 官方源码编译（并列保留）

```bash
# 需要 cmake + C++ 编译器 + boost/tbb 等依赖（详见官方 wiki）
git clone --recursive https://github.com/COMBINE-lab/salmon.git
cd salmon
mkdir build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX=~/software/salmon-1.3.0
make -j 4
make install
export PATH=$PATH:~/software/salmon-1.3.0/bin && salmon --version   # 断言
```

### 3. Conda / brew（包管理器安装）

```bash
mamba create -n salmon-native -c conda-forge -c bioconda salmon=1.3.0
conda activate salmon-native
salmon --version   # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
brew install salmon
salmon --version   # 断言（brew 当前 2.7.0，与 meta 登记 1.3.0 略有差异，以 formula 为准）
```

### 4. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/salmon:1.3.0--hf69c8f4_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/salmon:1.3.0--hf69c8f4_0 \
    quant -i /data/salmon_index -l A -1 /data/A1.1.fastq -2 /data/A1.2.fastq -p 8 --validateMappings -o /data/salmon_out/A1
```

### 5. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull salmon.sif docker://depot.galaxyproject.org/singularity/salmon:1.3.0--hf69c8f4_0
apptainer run -B $PWD:/data -H /data salmon.sif --version
```

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（index/quant/quantmerge），无需已安装 salmon
```

## 版本

* salmon 1.3.0（bioconda::salmon=1.3.0；quay tag `1.3.0--hf69c8f4_0`）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/salmon / depot.galaxyproject.org；本地不再自建容器）；官方另提供 linux-x64 预编译二进制包与源码编译路线

## 容器与 Conda 链接

* **官网**：https://combine-lab.github.io/salmon/

  **Github**：https://github.com/COMBINE-lab/salmon

* **Bioconda 页面**：<https://anaconda.org/channels/bioconda/packages/salmon/overview>

* **Docker**：`docker pull quay.io/biocontainers/salmon:1.3.0--hf69c8f4_0`

* **Singularity**：<https://depot.galaxyproject.org/singularity/salmon%3A1.3.0--hf69c8f4_0>

* 安装方式（本地）：`mamba create -n salmon -c conda-forge -c bioconda salmon=1.3.0`

***

## 官方实现登记（不建目录）

* **nf-core modules**：`modules/nf-core/salmon/index`、`modules/nf-core/salmon/quant`，pin `bioconda::salmon=1.10.3`。执行前请 `nf-core modules install salmon index quant` 安装到项目自身目录，不要直接引用本仓库示例。

* **snakemake-wrappers**：`bio/salmon/decoys`、`bio/salmon/index`、`bio/salmon/quant`（`quant` 环境 pin `salmon=2.5.1`）。运行时靠 `wrapper: "v9.17.1/bio/salmon/quant"` 句柄解析，不要把本地示例当 `wrapper_path`。
