# gblocks 软件模块

> 汇总说明：本 README 合并本模块各实现（仅 native 一路，`source_type: custom`）的用法；官方 nf-core 子模块与
> snakemake-wrappers 情况记录于此（不建目录，仅说明层）。安装方式见「环境安装」节，容器与 conda 环境信息
> 记录于文末。

***

## native 实现

# gblocks / native — 保守区块提取驱动

Gblocks（[官网](http://molevol.cmima.csic.es/castresana/Gblocks.html)，Castresana 2000，经典版本 **0.91b**）是
**系统发育分析前的多序列比对（MSA）过滤工具**：从比对结果（FASTA/PIR/NBRF）中自动筛选**保守区块
（conserved blocks）**，剔除高变区与难比对区域，输出更可靠的比对（原生在输入名后追加 `-gb`），再送入
RAxML / RAxML-NG 等建树。它是 14.md「四、单拷贝同源基因提取和多序列比对 → 3.5 Gblocks 保守区块提取」的
核心步骤，与 trimAl 并列为 MSA 修剪的两条主流路线。

本实现为自包含驱动（`source_type: custom`、`type: native`），二进制由**官方容器/conda**
（quay.io/biocontainers/gblocks / bioconda gblocks）提供，登记经典版本 **0.91b**（bioconda 现行 latest 为 1.0，
但 14.md 与官方文档流程锁定 0.91b）。

## 功能

| 子命令       | 命令                                                                    | 作用                                            |
| --------- | --------------------------------------------------------------------- | --------------------------------------------- |
| `extract` | `Gblocks <aln> -t=<c\|p\|d> [-e=-gaps] [-b1..-b5]`                     | 从多序列比对提取保守区块（原生写 `<aln>-gb`，`-o` 改名）           |
| `version` | `Gblocks --help`                                                       | 打印 Gblocks 用法/版本                              |

> `-t`：`c`=codon/密码子比对、`p`=protein/蛋白质比对、`d`=DNA 比对。`-b1..-b5` 为区块参数（长度/侧翼阈值/
> 允许空位策略）。Gblocks 原生**不支持 `-o`**，结果固定写到 `<输入>-gb`；驱动在给定 `-o` 时把该文件改名搬运。

## 用法

```bash
# CLI 直跑
python main.py extract sample.aln -t p                 # 输出 sample.aln-gb（蛋白质）
python main.py extract sample.aln -t c -o sample.codon-gb   # 密码子比对，改名输出
python main.py extract sample.aln -t p -e --b1 10 --b2 8    # 允许空位 + 自定义区块参数

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--tmpdir` 同时注入 `TMPDIR`）。**Gblocks 为单线程
经典工具**，`--threads` 仅作统一接口保留，**不注入命令行**。

## 实战示例：保守区块提取（14.md 3.5 链路）

Gblocks 通常接在 MAFFT 比对（或蛋白质比对转密码子比对）之后，对每个单拷贝同源基因分别提取保守区块；
**等价能力由 `native/main.py` 的 `extract` 子命令提供**（见上「用法」）。

### 1. 批量保守区块提取（Codon 与 Protein 两种模式）

```bash
# 对每个同源基因的比对结果提取保守区块（-t=c：Codon 模式；-t=p：Protein 模式）
for i in `cat orthologGroups.txt`
do
    Gblocks orthologGroups_CDS/$i.fasta.align -t=c
    Gblocks orthologGroups_Protein/$i.fasta.align -t=p
done

# 输出文件：{prefix}.fasta.align-gb（提取保守区块后的比对）
# 驱动等价写法（单文件）：
python modules/gblocks/native/main.py extract orthologGroups_CDS/$i.fasta.align -t c
```

### 2. 参数说明

| 参数          | 说明                                        |
| ----------- | ----------------------------------------- |
| `-t=c/p/d`  | 序列类型：codon / protein / DNA                 |
| `-e=-gaps`  | 允许半位点含空位（更宽松，保留更多位点）                       |
| `-b1`       | 最小保守区块长度（默认 10）                            |
| `-b2`       | 侧翼位置阈值（默认 8）                              |
| `-b3`       | 最大连续非保守位置数（默认 10）                          |
| `-b4`       | 区块内最小空位位置数（默认 4）                           |
| `-b5=n/h/a` | 允许的空位位置策略（默认 h）                           |

## 环境安装（官方预编译二进制包优先；Conda / brew 并列保留）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；
main.py 驱动在宿主机跑。官方同时提供**预编译二进制包**（Linux64 / OSX，`.tar.Z`），两条路线并列保留。

### 1. 官方预编译二进制包（首选）

官方下载页 <http://molevol.cmima.csic.es/castresana/Gblocks.html>（老式 http 站点，2026-09 从测试环境不可达；
下列 URL 与 sha256 依据 brewsci/homebrew-bio 公式核实）：

```bash
# .tar.Z = tar + compress，解压需 ncompress（Linux）/ 支持 -Z 的 tar（macOS 自带）
mkdir -p ~/software && cd ~/software
# Linux x86_64：
wget http://molevol.cmima.csic.es/castresana/Gblocks/Gblocks_Linux64_0.91b.tar.Z
tar -xZf Gblocks_Linux64_0.91b.tar.Z -C ~/software/
# macOS：
# wget http://molevol.cmima.csic.es/castresana/Gblocks/Gblocks_OSX_0.91b.tar.Z
# tar -xZf Gblocks_OSX_0.91b.tar.Z -C ~/software/

mkdir -p ~/software/gblocks-0.91b/bin
install -m 0755 Gblocks ~/software/gblocks-0.91b/bin/Gblocks
echo 'export PATH=$PATH:~/software/gblocks-0.91b/bin' >> ~/.bashrc && source ~/.bashrc
echo q | Gblocks        # 断言（打印版本 0.91b 后退出）
```

> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `gblocks`，
> 无 conda 时自动下载官方 `.tar.Z` 二进制到 `~/software/gblocks-<ver>` 并写 PATH；版本默认 0.91b，
> 与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Conda / brew（包管理器安装，备选）

```bash
mamba create -n gblocks-native -c conda-forge -c bioconda gblocks=0.91b
conda activate gblocks-native
echo q | Gblocks        # 断言（0.91b）
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap；homebrew-core 无此公式）
brew tap brewsci/bio     # 首次使用需要
brew install gblocks
echo q | Gblocks         # 断言
```

### 3. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/gblocks:0.91b--h9ee0642_2
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/gblocks:0.91b--h9ee0642_2 \
    Gblocks /data/sample.aln -t=p
```

### 4. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull gblocks.sif docker://depot.galaxyproject.org/singularity/gblocks:0.91b--h9ee0642_2
apptainer run -B $PWD:/data -H /data gblocks.sif Gblocks /data/sample.aln -t=p
```

> **说明（源码编译小节略去的理由）**：官方以**预编译二进制**（Linux64/OSX）分发，未检索到官方一键源码归档
> （下载页 2026-09 从测试环境不可达，未核实源码发布）→ 本 README 省略「官方源码编译」小节，备选路线走
> bioconda/brew（上 §2）。

## 官方实现登记（不建目录，仅说明层）

* **nf-core**：官方**无** `modules/nf-core/gblocks`（2026-09 抓取 `contents/modules/nf-core/gblocks` 返回
  **404**）→ 不建目录；Nextflow 场景请用本模块 `native/` 兜底（见上「native 实现」节）。

* **snakemake-wrappers**：官方**无** `bio/gblocks`（2026-09 核实 `tree/master/bio/gblocks` 返回 **404**）→
  不建目录；Snakemake 场景请用本模块 `native/` 兜底。

## 测试

```bash
cd modules/gblocks/native && bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema）+ argv 构造断言必跑；
# PATH 含 Gblocks 时追加真实保守区块提取（生成 <aln>-gb）；否则跳过（argv 验证已通过）。
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/gblocks>（现行 latest 1.0；本模块登记经典版 0.91b）

* **Docker**：`docker pull quay.io/biocontainers/gblocks:0.91b--h9ee0642_2`（bioconda 自动构建；tag 以 quay /
  depot.galaxyproject.org 页面为准）

* **Singularity**：<https://depot.galaxyproject.org/singularity/gblocks%3A0.91b--h9ee0642_2>

* 安装方式（本地）：`mamba create -n gblocks -c conda-forge -c bioconda gblocks=0.91b`（或
  `brew tap brewsci/bio && brew install gblocks`；或官方预编译二进制 `Gblocks_Linux64_0.91b.tar.Z`）

* 上游：<http://molevol.cmima.csic.es/castresana/Gblocks.html>（下载页）·
  <https://home.cc.umanitoba.ca/~psgendb/doc/Castresana/Gblocks_documentation.html>（文档）
  
* **在线**：https://phylogeny.fr/tools/gblocks

## 版本

* gblocks **0.91b**（bioconda::gblocks=0.91b；官方容器 tag `0.91b--h9ee0642_2`；bioconda 现行 latest 为 1.0，
  本模块按 14.md 流程锁定经典版 0.91b）

* 许可：自定义（bioconda gblocks 包未登记标准 SPDX；包元数据 license 记为「as is, without guarantee of
  support or maintenance」；以官方文档为准）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/gblocks / depot.galaxyproject.org；本地不再自建容器）；
  官方另有预编译二进制（`.tar.Z`，需 ncompress）

* 官方层：nf-core 无子模块、snakemake-wrappers 无 wrapper（均 2026-09 核实 404）
