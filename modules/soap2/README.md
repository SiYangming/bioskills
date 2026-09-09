# soap2 软件模块（SOAPaligner/SOAP2 — 华大二代短读比对器）

> # ⚠️ DEPRECATED — 已淘汰，仅历史参考登记
>
> **SOAPaligner/SOAP2（soap2.21release，华大 BGI）** 是 SOAP（Short
> Oligonucleotide Analysis Package）家族的短读比对器，用 2way-BWT 压缩索引把
> Illumina/Solexa 短读快速比对到参考基因组（Li R et al. *Bioinformatics*
> 2009;25:1966-7），比 SOAPv1 快约一个数量级。程序族：**2bwt-builder**（建索引）
> 与 **soap**（比对，输出 SOAP 自定义格式）。
> 上游在 soap2.21release 之后**长期停更**；BGI 官网 soap.genomics.org.cn
> 2026-09-09 探测**不可达**（curl 000），SourceForge soap2/soapaligner 项目 404。
>
> **新项目请勿使用**——短读比对已被 **BWA / Bowtie2** 全面替代。本模块只做
> 「录入」：方法/命令/链接准确登记、不产出自建容器配方（Dockerfile/Apptainer.def），
> 仅供复现 2009–2011 时代的 SOAP2 分析。

***

## native 实现（说明型 / 命令构造，`source_type: custom` / `type: native`）

本实现为「说明型 + 命令构造」：`native/main.py` 按官方 man page 构造 SOAPaligner/soap2
命令行并打印，**不实际执行**（软件 deprecated、官网停服、无新用场景）。两个子命令：

| 子命令 | 实际构造命令 | 作用 |
| ---- | ---- | ---- |
| `2bwt-builder` | `2bwt-builder <ref.fasta>` | 参考 FASTA → 2way-BWT 索引（产物在 FASTA 同目录：`<ref>.bwt/.amb/.ann/.pac`） |
| `soap` | `soap -D <index> -a <reads.fa> [-b <reads2.fa>] -o <out> [-2 <unpaired>] [-m/-x 插入] [-r 重复] [-p 线程]` | SE/PE 短读比对，输出 SOAP 格式（转 SAM 需 soap2sam） |

```bash
# CLI 直跑（构造历史命令，仅供复现；先装 soapaligner 2.21，见「环境安装」）
python main.py 2bwt-builder ref.fasta
python main.py soap --index ref -a reads_1.fa -b reads_2.fa -o reads.soap \
    --min-insert 200 --max-insert 600 --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads`（`auto` 或正整数；正整数透传 soap `-p`）与 `--tmpdir`。
构造命令通过 stderr 打印 deprecated 提示，stdout 只输出命令本身。

***

### 参数说明（录入；2026-09 对照 soap.1 man page 与 SOAP2 论文）

| 参数 | 说明 |
| ---- | ---- |
| `2bwt-builder <ref.fasta>` | 建索引；只接受 FASTA，产物在 FASTA 同目录；不支持 32 位平台 |
| `-D <index>` | soap：参考索引前缀名（如 ref.fa；必填） |
| `-a <file>` | SE reads 或 PE read1（必填；FASTA/FASTQ） |
| `-b <file>` | PE read2（省略 → SE 比对） |
| `-o <out>` | 比对结果文件（必填） |
| `-2 <out>` | PE 比对中 mapped-but-unpaired reads 的输出文件 |
| `-m / -x` | PE 允许最小/最大插入片段 bp（默认 400 / 600） |
| `-n <int>` | 过滤含 >n 个 N 的低质量 reads（默认 5） |
| `-r <int>` | 重复 hits 报告：0=不报；1=随机一个；2=全部（默认 1） |
| `-l <int>` | 长 reads 3' 端高错误时先比对 5' 端种子长度（默认 256=全长） |
| `-v <int>` | 单条 read 允许错配总数（默认 5） |
| `-g <int>` | 允许 gap 数（默认 0，不支持 indel） |
| `-M <int>` | 匹配模式：0/1/2=精确/1/2 错配；4=找最佳 hits（默认 4） |
| `-p <int>` | 线程数（默认 1） |

## 测试

```bash
bash test/run_test.sh   # argv 构造 + parser + schema 自省为常驻断言（不下载/不编译）；
                        # stub 假二进制 CLI 冒烟恒跑
```

## 环境安装（官方镜像优先，不维护本地配方）

> 官方现状（2026-09-09 在线核实，如实记录）：**上游停更**，BGI 官网不可达；
> bioconda 存在 **soapaligner=2.21** 历史包（linux-64 + osx-64 各 build -0，
> license=GPL）→ quay.io/biocontainers 与 depot.galaxyproject.org 有自动构建镜像；
> 但多年未随上游维护 → 判定「官方渠道存在但属历史遗留，不建议新项目依赖」；软件
> deprecated → **不维护本地 Dockerfile/Apptainer.def 配方**。

### 1. Conda / brew（包管理器安装）

```bash
# conda：bioconda 历史包 soapaligner=2.21（linux-64/osx-64；license=GPL）
mamba create -n soap2-native -c conda-forge -c bioconda soapaligner=2.21
conda activate soap2-native
soap -V 2>&1 | head -1 || soap 2>&1 | head -2   # 断言：命令可达（2.21 无统一 --version）
```

> Homebrew：homebrew-core（formulae.brew.sh/api/formula/soapaligner.json、
> soap2.json）与 brewsci/bio（Formula/soapaligner.rb）均 404（2026-09-09 核实），
> 无公式 → 不登记 brew 安装块。

### 2. Docker（官方镜像）

无「当前维护」官方镜像；仅历史镜像可作复现（bioconda 2.21 老包自动构建）：

```bash
docker pull quay.io/biocontainers/soapaligner:2.21--0
# 运行工具本体（产物归当前用户，避免 root 持有）
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/soapaligner:2.21--0 \
    soap -D /data/ref.fa -a /data/reads_1.fa -b /data/reads_2.fa -o /data/lib1.soap
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 预构建 sif（2026-09-09 核实存在，与 quay tag 互通）：

```bash
apptainer pull soapaligner.sif docker://depot.galaxyproject.org/singularity/soapaligner:2.21--0
apptainer run -B $PWD:/data -H /data soapaligner.sif \
    2bwt-builder /data/ref.fa
```

### 4. 二进制包安装（官方 release / 源码编译）

官方 BGI 直链 `http://soap.genomics.org.cn/down/soap2.21release.tar.gz` 已不可达
（000）；SourceForge soap2/soapaligner 项目 404。可用的**历史二进制渠道**为
**GigaScience 存档仓库** `github.com/gigascience/bgi-soap2`（BGI 官方数据归档的
GitHub 副本，`executables/2.21/x86_64/` 含 `soap` / `2bwt-builder` / `soap2sam.pl`
等可执行文件，2026-09-09 raw 直链 200）：

```bash
mkdir -p ~/software/soap2.21release && cd ~/software/soap2.21release
# 逐文件取 2.21 x86_64 可执行（以 soap 为例；2bwt-builder 同理）
curl -fL -o soap \
    https://raw.githubusercontent.com/gigascience/bgi-soap2/master/executables/2.21/x86_64/soap
chmod +x soap
export PATH="$HOME/software/soap2.21release:$PATH"
```

> ⚠️ 2011 时代 x86_64 二进制对现代 glibc/macOS 的兼容性**未核实**；优先推荐
> bioconda soapaligner=2.21 路线。

## 替代建议（新项目请直接使用）

| 替代工具 | 说明 | 官方入口 |
| ---- | ---- | ---- |
| **BWA** | 短读 BWT 比对（bwa aln/samse/sampe 或 bwa mem），SOAP2 时代主流继任者 | <https://github.com/lh3/bwa>（bioconda `bwa`） |
| **Bowtie2** | 短读/最长 ~1kb 局部与端到端比对，支持 indel | <https://github.com/BenLangmead/bowtie2>（bioconda `bowtie2`） |
| **BWA-MEM / minimap2** | 更长的 reads 与三代数据比对（本仓库另见 `minimap2` 模块） | <https://github.com/lh3/bwa> / <https://github.com/lh3/minimap2> |

## 版本

* **2.21**（soap2.21release，SOAP2 系列最终发布；2.21 可执行文件时代约 2009–2011，
  2026-09 在线核实 BGI 官网不可达、无更新渠道）
* bioconda 版本号 **2.21**（soapaligner；linux-64 + osx-64 build -0，license=GPL，
  依赖 zlib 1.2.11；2026-09-09 api.anaconda.org 核实）
* License：bioconda 包元数据 **GPL**；官方许可声明因官网停服未能在线复核
  （学术免费 / 商用需 BGI 授权为历史惯例，未证实）
* 引用：Li R, Yu C, Li Y, Lam TW, Yiu SM, Kristiansen K, Wang J. SOAP2: an
  improved ultrafast tool for short read alignment. *Bioinformatics*
  2009;25(15):1966-7. doi:10.1093/bioinformatics/btp336
* nf-core / snakemake-wrappers：无官方子模块（2026-09-09 核实
  `modules/nf-core/soap2`、`bio/soap2` 均 404）→ 不登记官方说明层

## 历史留存

* 历史教程常见安装前缀为 **`/opt/biosoft/soap2.21release`**（root 全局限定路径）；
  本 README 一律改写为**用户前缀** `~/software/soap2.21release`（免 root）。
  原始发布包名：`soap2.21release.tar.gz`（BGI 官网 `down/` 目录，现已不可达）。
* SOAP 自定义格式 → SAM：历史上用 BGI 的 **soap2sam**（soap2sam.pl）；该转换器
  官方页面随 soap.genomics.org.cn 停服，2026-09 未找到稳定归档 → 不列入安装步骤，
  历史流程如需转换请自行查找存档版本（部分第三方镜像仍流传，未逐一核实）。
* 下游组装工具（SOAPdenovo 等）时代常配套使用 soap2 输出直接喂组装器，不需要 SAM；
  现代流程统一建议 BWA/Bowtie2 + SAM/BAM。

## 容器与 Conda 链接

* **官网（已停服）**：<http://soap.genomics.org.cn/soapaligner.html>
* **GigaScience 存档**（历史二进制，200）：<https://github.com/gigascience/bgi-soap2>
* **conda**：bioconda `soapaligner=2.21`（历史包）→ <https://anaconda.org/bioconda/soapaligner>
* **Docker / Singularity**：`quay.io/biocontainers/soapaligner:2.21--0`（历史镜像）/
  depot.galaxyproject.org 同名 sif
* **brew**：无公式（homebrew-core 与 brewsci/bio 均 404 核实）
* **引用论文**：<https://academic.oup.com/bioinformatics/article/25/15/1966/214699>
