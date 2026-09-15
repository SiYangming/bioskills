# gapcloser 软件模块

> 汇总说明：本 README 合并各实现（native 等）的用法；安装方式见「环境安装」，容器与 conda 信息记录于「容器与 Conda 链接」。

***

## native 实现

# gapcloser / native — 自包含基因组补洞驱动

GapCloser（GapCloser v1.12-r6，SOAPdenovo2 套件）的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

| 子命令   | 命令                                                                          | 作用                       |
| ----- | --------------------------------------------------------------------------- | ------------------------ |
| `fill` | `GapCloser -a <scaffold> -b <config> -o <out> -l <max_read_len> -p <overlap> -t <threads>` | 用配对 reads 回贴 scaffold，闭合序列中的 N gap |

参数语义取自 GapCloser 二进制**内建 help**（`strings` 提取，2026-09 核实）：`-a scaffold file`（必填）· `-b config file` · `-o output file` · `-l max read len` · `-p overlap para`（<=31，default=25）· `-t thread num`。

> ⚠️ 文档原文把 `-l 120` 注释为「最小重叠长度」，与二进制 help（`-l` = max read len，overlap 由 `-p` 控制）不一致；本驱动按二进制 help 保留 `-l`（最大读长，默认 120）与 `-p`（overlap，默认 25）两个独立选项。

## 用法

```bash
# CLI 直跑
python main.py fill -a genome.fa -b config.txt -o gapcloser.fa -l 120 -t 4

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads`（注入 `GapCloser -t`）与 `--tmpdir` 运行期覆盖。

## 实战示例：SOAPdenovo 组装后补洞

GapCloser 是 SOAPdenovo2 流程中「组装 → 补洞」的标准收尾步骤：把 SOAPdenovo 产出的 scaffold 与 BLESS 纠错后的配对 reads 一起输入，闭合装配中的 N gap。以下为文档示例（等价能力由 `native/main.py` 的 `fill` 子命令提供，见上「用法」）。

```bash
mkdir -p 04.genome_assembling/GapCloser
cd 04.genome_assembling/GapCloser

# 复制 SOAPdenovo 的文库配置（-b 参数；SOAPdenovo 式 config）
cp ../SOAPdenovo/config.txt ./

# 建立数据符号链接（-a 输入 scaffold；config 中 q1/q2 指向 reads）
ln -s ../ALLPATHS-LG/allpathslg.fasta genome.fa
ln -s ~/03.sequencing_data_quality_control/BLESS/fragment.1.corrected.fastq fragment.1.fastq
ln -s ~/03.sequencing_data_quality_control/BLESS/fragment.2.corrected.fastq fragment.2.fastq
ln -s ~/03.sequencing_data_quality_control/BLESS/jumping.1.corrected.fastq jumping.1.fastq
ln -s ~/03.sequencing_data_quality_control/BLESS/jumping.2.corrected.fastq jumping.2.fastq

# 运行 GapCloser
#   -a genome.fa: 输入基因组序列（scaffold）
#   -b config.txt: 文库配置文件
#   -o gapcloser.fa: 输出文件
#   -l 120: 最大读长（文档注释为「最小重叠长度」，见上「功能」注）
#   -t 4: 使用 4 个线程
GapCloser -a genome.fa -b config.txt -o gapcloser.fa -l 120 -t 4
```

### config.txt 结构（SOAPdenovo 式文库配置，供 `-b`）

```ini
max_rd_len=150
[LIB]
avg_ins=300        # 平均插入片段长度
reverse_seq=0      # 是否需要反向互补
asm_flags=3        # 用途位标记（1=仅用于 contig，2=仅用于 scaffold，3=both）
rd_len_cutoff=150  # reads 截断长度
rank=1
pair_num_cutoff=3  # 采用的 reads 配对下限
map_len=32         # 比对长度阈值
q1=fragment.1.fastq
q2=fragment.2.fastq
```

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。**注意**：文档称「GapCloser 暂无官方 conda 包」，但 2026-09 在线核实 bioconda 实际提供官方包 **`soapdenovo2-gapcloser`=1.12**（包名非 `gapcloser`），并有 quay / depot 官方镜像。

### 1. Conda / brew（包管理器安装）

```bash
# bioconda 官方包名是 soapdenovo2-gapcloser（直接搜 gapcloser 为 404）
mamba create -n gapcloser -c conda-forge -c bioconda soapdenovo2-gapcloser=1.12
conda activate gapcloser
GapCloser 2>&1 | grep "input scaffold file name"   # 断言（GapCloser 无 --version）
```

> Homebrew：homebrew-core（`formulae.brew.sh/api/formula/gapcloser.json`）与 brewsci/bio（`Formula/gapcloser.rb`）均 404（2026-09 核实）→ 无公式，不登记 brew 安装块。
>
> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `gapcloser`，无 conda 时自动下载官方 SourceForge 预编译 tgz 到 `~/software/gapcloser-<ver>` 并写 PATH；版本默认 1.12，与 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/soapdenovo2-gapcloser:1.12--h077b44d_3
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/soapdenovo2-gapcloser:1.12--h077b44d_3 \
    GapCloser -a genome.fa -b config.txt -o gapcloser.fa -l 120 -t 4
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
apptainer pull gapcloser.sif docker://depot.galaxyproject.org/singularity/soapdenovo2-gapcloser:1.12--h077b44d_3
apptainer run -B $PWD:/data -H /data gapcloser.sif \
    GapCloser -a /data/genome.fa -b /data/config.txt -o /data/gapcloser.fa -l 120 -t 4
```

### 4. 官方预编译二进制包（首选）

官方 SourceForge 提供预编译包 `GapCloser-bin-v1.12-r6.tgz`（仅 linux-x86_64；2026-09 核实可下载，114553 B，sha256 `8ca1a7e5…`）：

```bash
mkdir -p ~/software/gapcloser-1.12 && cd ~/software/gapcloser-1.12
wget https://sourceforge.net/projects/soapdenovo2/files/GapCloser/bin/r6/GapCloser-bin-v1.12-r6.tgz
tar zxf GapCloser-bin-v1.12-r6.tgz
export PATH="$PWD:$PATH"
GapCloser 2>&1 | grep "input scaffold file name"   # 断言
```

> 💡 一键安装：`bash native/install.sh --method binary`（自动校验 sha256 并部署到 `~/software/gapcloser-1.12`）。

### 5. 官方源码编译（并列保留）

官方同时提供源码包 `GapCloser-src-v1.12-r6.tgz`（bioconda recipe 即由此构建）：

```bash
wget https://sourceforge.net/projects/soapdenovo2/files/GapCloser/src/r6/GapCloser-src-v1.12-r6.tgz
tar zxf GapCloser-src-v1.12-r6.tgz && cd GapCloser-src-v1.12-r6
make                    # 依赖 g++ / zlib（bioconda recipe: compiler('cxx') + zlib）
# 产物 GapCloser，放入 PATH 即可
```

## 测试

```bash
bash test/run_test.sh   # argv 构造 + parser + schema 自省（不下载/不编译）；GapCloser 已装时附 help 冒烟
```

## 容器与 Conda 链接

* **官网 / 下载页**：<https://sourceforge.net/projects/soapdenovo2/files/GapCloser>
* **Bioconda 页面**：<https://anaconda.org/bioconda/soapdenovo2-gapcloser>
* **Docker**：`docker pull quay.io/biocontainers/soapdenovo2-gapcloser:1.12--h077b44d_3`
* **Singularity**：<https://depot.galaxyproject.org/singularity/soapdenovo2-gapcloser%3A1.12--h077b44d_3>
* **brew**：无公式（homebrew-core 与 brewsci/bio 均 404 核实）
* 安装方式（本地）：`mamba create -n gapcloser -c conda-forge -c bioconda soapdenovo2-gapcloser=1.12`

## 版本

* GapCloser **v1.12-r6**（SOAPdenovo2 套件补洞工具；Li R et al. *GigaScience* 2014）
* bioconda 版本号 **1.12**（包名 `soapdenovo2-gapcloser`；quay tag `1.12--h077b44d_3`；license GPL-3.0-or-later）
* License：**GPL-3.0-or-later**（bioconda recipe `about.license`）
* nf-core / snakemake-wrappers：无官方子模块（2026-09 核实 `modules/nf-core/` 与 `bio/` 均 404）→ 不登记官方说明层
* 构建路线：官方镜像/conda 优先（quay.io/biocontainers/soapdenovo2-gapcloser / depot.galaxyproject.org；本地不再自建容器）
