# NGSQCToolkit（NGS QC Toolkit）软件模块

> ## ⚠️ 已淘汰（DEPRECATED）
>
> **NGSQCToolkit 自 2014 年 v2.3.3 后停止更新，其功能已被 Trimmomatic、fastp、
> cutadapt 完全取代（本仓库已有 `modules/trimmomatic`、`modules/fastp`、
> `modules/cutadapt`、`modules/fastqc` 可直接使用）。**
>
> 2026-09-08 在线核实：官方主页 <https://www.nipgr.ac.in/NGSQCToolkit.php> 与
> v2.3.3 下载 <https://www.nipgr.ac.in/ngsqctoolkit/NGSQCToolkit_v2.3.3.zip> 均返回
> **HTTP 404**；论文引用的旧主页 `nipgr.res.in` 域名已无法解析。
>
> **不要在新流程中使用本模块**——本模块仅作「历史参考登记」：native 实现是
> 说明 + argv 构造型驱动（默认 dry_run，不实际运行），用于复现/理解旧流程时
> 查询官方命令的准确形态。

- 原始文献：Patel RK, Jain M (2012). *NGS QC Toolkit: A toolkit for quality control
  of next generation sequencing data.* **PLoS ONE** 7(2): e30619.
  （[PMC3270013](https://pmc.ncbi.nlm.nih.gov/articles/PMC3270013/)）
- 开发单位：印度国家植物基因组研究所（NIPGR, New Delhi），作者 Ravi K. Patel /
  Mukesh Jain；工具全部以 **Perl** 实现。
- 支持平台：Roche 454（sff 转 fastq 后）与 Illumina 数据 QC/过滤/统计/格式转换。

---

## 一、状态与弃用声明（2026-09-08 核实）

| 检查项 | 结果 | 证据 |
| ---- | ---- | ---- |
| 官网主页 `nipgr.ac.in/NGSQCToolkit.php` | ❌ HTTP 404（站根仍 200，工具页已下线） | curl 2026-09-08 |
| v2.3.3 zip `nipgr.ac.in/ngsqctoolkit/NGSQCToolkit_v2.3.3.zip` | ❌ HTTP 404 | curl 2026-09-08 |
| 旧主页 `nipgr.res.in/ngsqctoolkit.html` | ❌ DNS 无法解析 | curl 2026-09-08 |
| bioconda / conda-forge `ngsqctoolkit` | ❌ 均不存在（api 404） | api.anaconda.org 2026-09-08 |
| nf-core modules `ngsqctoolkit` | ❌ 不存在（404） | api.github.com 2026-09-08 |
| snakemake-wrappers `bio/ngsqctoolkit` | ❌ 不存在（404） | api.github.com 2026-09-08 |
| Homebrew `ngsqctoolkit` | ❌ 无公式（formulae.brew.sh 404） | 2026-09-08 |
| quay.io/biocontainers | ❌ 推断无（bioconda 无包即无自动构建；quay API 需认证，未直接核实） | — |
| GitHub 源码分支 | ① 作者 lab `mjain-lab/NGSQCToolkit`（v2.3，2021-03 上传后无更新）；② 用户修复 fork `SiYangming/NGSQCToolkit`（tag v2.3.3，2026-09-08） | api.github.com 2026-09-08 |

结论：**无官方维护、无 conda/容器分发、无活跃社区分支**。搜索引擎中同名项
（如 RAHenriksen/**NGSNGS**=测序数据模拟器、pyNGSQC、ngsqc 等）均为**不相关软件**，
勿混淆。官方 GitHub 源现状：① `mjain-lab/NGSQCToolkit` 是作者（Mukesh Jain lab）
上传的完整源码留存（`Format-converter/`、`QC/`、`Statistics/`、`Trimming/` +
官方 v2.3 手册 PDF + README；16 stars / 3 forks），可用作脚本级核对与下载兜底，
但**不是维护分支**（最后一次 push 2021-03、仅到 v2.3）；② `SiYangming/NGSQCToolkit`
为**用户 fork 修复版**（2026-09-08 tag/release **v2.3.3**），提供官网 404 后对应
官方最终 2.3.3 的可获取本体（见「五、4」下载命令与「六、版本」）。

**license**：官方未声明 SPDX 许可（主页/论文仅称 free / open source、学术免费使用；
GitHub 镜像无 LICENSE 文件）——2026-09 官网已 404，更细条款无法复核，按
`custom`（学术自定义）登记。

---

## 二、替代建议（新项目请直接选这些）

| NGSQCToolkit 历史能力 | 推荐替代 | 本仓库对应模块 |
| ---- | ---- | ---- |
| `IlluQC.pl` / `IlluQC_PRLL.pl`：接头过滤 + 低质量过滤 + 统计/图 | **Trimmomatic**（PE/SE，ILLUMINACLIP + SLIDINGWINDOW + MINLEN）；统计/图用 **FastQC + MultiQC**；或 **fastp**（一体式，更快） | `modules/trimmomatic`、`modules/fastp`、`modules/fastqc` |
| `TrimmingReads.pl`：3' 端质量截短 + 长度过滤 | **Trimmomatic**（LEADING/TRAILING/SLIDINGWINDOW/MINLEN）、**cutadapt**（`-q`/`-m`）、**fastp** | `modules/trimmomatic`、`modules/cutadapt`、`modules/fastp` |
| `AmbiguityFiltering.pl`：N 碱基计数/百分比过滤 | **cutadapt `--max-n <n>`**（丢弃含 N 过多的读段）；端部 N 修剪可用 fastp 邻近能力或自定义（awk/seqtk） | `modules/cutadapt`、`modules/fastp`、`modules/seqkit` |
| `AvgQuality.pl` / `N50Stat.pl` / 格式转换 | FastQC/MultiQC、`seqtk`/`seqkit` | `modules/fastqc`、`modules/seqkit` |

---

## 三、native 实现（说明 + argv 构造型驱动）

本地自包含实现（`source_type: custom`、`type: native`）。NGSQCToolkit 本体是 Perl
脚本集（无独立二进制、无 conda 包），官方渠道已下线 → 本模块 `native/main.py`
**不封装运行环境**，只按官方脚本 help 提供**准确的命令构造**（参数名与默认值与
mjain-lab 镜像 v2.3 原始脚本 help 文本逐项核对，2026-09-08），并默认 dry_run：

| 子命令 | 构造的命令（历史） | 说明 |
| ---- | ---- | ---- |
| `qc` | `perl <root>/QC/IlluQC_PRLL.pl -pe|-se …` | Illumina 高质量过滤（并行版）；⚠️ 改用 trimmomatic/fastp |
| `trim` | `perl <root>/Trimming/TrimmingReads.pl -i …` | 3' 端质量/长度修剪；⚠️ 改用 trimmomatic/fastp |
| `ambig` | `perl <root>/Trimming/AmbiguityFiltering.pl -i …` | 模糊碱基 N 过滤；⚠️ 改用 cutadapt `--max-n` |

> 若确需真实执行（强烈不推荐），`<root>` 指向解压后的 NGSQCToolkit 根目录
> （`--toolkit-dir` 或环境变量 `NGSQCTOOLKIT_ROOT`），加 `--execute` 才会运行
> perl；届时需先按「环境安装」装好 perl 依赖。

```bash
# 历史 argv 打印（默认 dry_run，无需安装工具本体）
python main.py qc --r1 R1.fq --r2 R2.fq --toolkit-dir ~/sw/NGSQCToolkit_v2.3.3 \
    --adapter N --phred A --qual-cut 20 --len-cut 70 --outdir qc_out --threads 4
python main.py trim --input R1_filtered.fq --qual-cut 20 --len-cut 70 --outdir t_out.fq
python main.py ambig --input reads.fq --max-n 0

# Agent / Schema 自省
python main.py --list-commands
python main.py --schema
```

### 参数对照（源自官方脚本 help，2026-09-08 经 mjain-lab v2.3 源核对）

- `qc`（IlluQC_PRLL.pl）：`-pe R1 R2 <接头库> <FASTQ 变体>`（或 `-se reads <库> <变体>`）；
  接头库=内置编号或 `N`（不过滤）或自备序列文件；FASTQ 变体 `1`=Sanger(Phred+33)、
  `2`=Solexa、`3/4`=Illumina(Phred+64)、`5`=Illumina1.8+(Phred+33)、`A`=自动；
  `-l` HQ 长度百分比阈值（默认 70）、`-s` 质量阈值（默认 20）、`-c` CPU 数（默认 1）、
  `-onlyStat`、`-t` 统计格式（1 文本/2 tab）、`-o` 输出目录（默认输入旁的
  `IlluQC_Filtered_files/`）、`-z g` 输出 gzip。
- `trim`（TrimmingReads.pl）：`-i` 输入、`-irev` PE R2；`-l/-r` 左右端固定截短、
  `-q` 3' 端质量截短（与 `-l/-r` 互斥，默认 0 关）、`-n` 长度阈值（默认 -1 关）、`-o` 输出。
- `ambig`（AmbiguityFiltering.pl）：`-i`/`-irev`；`-c` 最大 N 数（默认 0）、`-p` 最大
  N 百分比、`-t5`/`-t3` 端部 N 修剪——**四者任选其一**；`-n` 长度阈值；`-o` 输出。

### 测试

```bash
bash test/run_test.sh   # 生成合成 FASTQ + fake-toolkit 骨架；
                        # 断言 --list-commands/--schema + qc/trim/ambig argv 构造
                        # （软件已淘汰 → 按登记契约不做真实 perl 回归）
```

---

## 四、历史留存：原工具方法与依赖清单（仅供历史参考，勿用于新流程）

> 本小节完整记录 NGSQCToolkit v2.3.x 的历史用法，供解读旧流程/旧文献（2012–2015
> 时代 Illumina 数据 QC 的常见做法）时对照。**命令未在本机实测运行**（已淘汰 +
> 官方分发下线），形态以下列来源交叉核对为准：
>
> ① mjain-lab/NGSQCToolkit（v2.3 源码）各脚本 `-h` help 文本（2026-09-08 抓取）；
> ② GitHub 第三方教学流程 severaus/LncRNA-Pipiline（2020，中文教程）；
> ③ ILRI HPC 软件页安装记录（记载 2.3.3 与下载镜像 IP）。
>
> 第三方面记录中个别参数（如 `IlluQC.pl -p 2` 中的 `-p`）不在官方脚本 help 中，
> 属旧版/教程约定，**请以官方手册 PDF 为准**（GitHub 镜像内
> `NGSQCToolkitv2.3_manual.pdf`）。

### 4.1 官方 zip 结构（v2.3.3 / v2.3 布局一致，2026-09-08 经镜像核对）

```
NGSQCToolkit_v2.3.3/
├── Format-converter/   FastqToFasta.pl  FastqTo454.pl
│                       SangerFastqToIlluFastq.pl  SolexaFastqToIlluFastq.pl
├── QC/                 IlluQC.pl（单线程）  IlluQC_PRLL.pl（并行，官方推荐）
│                       454QC.pl  454QC_PE.pl  454QC_PRLL.pl
│                       lib/（自带 Parallel::ForkManager 等 pure-perl 模块，
│                           脚本要求与脚本同目录，勿删除）
├── Statistics/         AvgQuality.pl  N50Stat.pl
├── Trimming/           TrimmingReads.pl  AmbiguityFiltering.pl  HomopolymerTrimming.pl
└── NGSQCToolkit manual.pdf
```

### 4.2 依赖安装清单（Perl 模块，CPAN 均在线，2026-09-08 fastapi.metacpan.org 核实）

| 模块 | 用途 | 作者/CPAN |
| ---- | ---- | ---- |
| `String::Approx` | 模糊串匹配（接头/引物检测核心依赖） | JHI，[CPAN](https://metacpan.org/pod/String::Approx) |
| `YAML` | 统计/配置读取 | TINITA，[CPAN](https://metacpan.org/pod/YAML) |
| `GD` | 统计图形输出（QC 图） | RURBAN，[CPAN](https://metacpan.org/pod/GD) |
| `GD::Text`（GDTextUtil 发行版） | 图中文本 | MVERB，[CPAN](https://metacpan.org/pod/GD::Text) |
| `GD::Graph`（GDGraph 发行版） | 图形绘制 | BPS，[CPAN](https://metacpan.org/pod/GD::Graph) |
| `Parallel::ForkManager` | 并行版（IlluQC_PRLL.pl） | 官方 zip 自带于 `QC/lib/`，无需单独安装 |

安装（历史做法）：

```bash
# macOS：先装 libgd（GD XS 编译依赖）
brew install gd
cpanm -n String::Approx YAML GD GDTextUtil GDGraph

# Debian/Ubuntu
sudo apt-get install libgd-dev
cpanm -n String::Approx YAML GD GDTextUtil GDGraph

# conda 兜底（perl 运行时 + 上述依赖的 conda 打包版，见 §5.1）
mamba env create -f native/environment.yml
```

> **CentOS 6 历史方案（libgd 源码安装，已淘汰、仅供旧系统参考）**：旧教程先自编译
> libgd（GD XS 的 C 库）再装 GD 系模块；现代 Debian/Ubuntu/RHEL 请直接用发行版
> `libgd-dev`/`libgd-devel` 或上方 conda 路线，勿再走源码：
>
> ```bash
> # libgd 2.1.1 源码 → /usr（历史写法；现代建议 --prefix 免污染系统）
> tar Jxf libgd-2.1.1.tar.xz && cd libgd-2.1.1/
> ./configure --prefix=/usr/ && make -j 4 && sudo make install
> cd ../ && rm -rf libgd-2.1.1/
> /bin/rm /usr/lib64/libgd.so          # 去旧符号链接（仅 CentOS 6 时代步骤）
> cp /usr/lib/libgd.* /usr/lib64/
> # GD 系 Perl 模块（GD::Text/GD::Graph 等）
> sudo ln -s /usr/lib64/libgd.so.2.0.0 /usr/lib64/libgd.so.3
> sudo cpan -fi GD
> sudo cpan -i ExtUtils::MakeMaker
> sudo cpan -i GD::Text
> sudo cpan -i GD::Graph
> ```
> （`String::Approx` / `YAML` 直接 `sudo cpan -i` 即可，无 C 库依赖。）

### 4.3 注意事项（历史复现时）

- 脚本为 2008–2014 时代 Perl：无现代语法，但对 Perl 版本不敏感；安装依赖时若宿主
  Perl 很新（5.36+），`String::Approx`/`GD` 等 XS 模块会就地重编译，需系统库齐全。
- 各脚本 require 同目录 `QC/lib/`（`Parallel::ForkManager` 等），**不要把脚本单独拷走**
  脱离 lib/ 运行。
- `TrimmingReads.pl` 的 `-q`（质量截短）与 `-l/-r`（固定截短）互斥；`AmbiguityFiltering.pl`
  的 `-c/-p/-t5/-t3` 互斥——均由官方脚本校验。
- QC 图输出依赖 GD/GD::Text/GD::Graph；只需文本统计时可不装 GD 系（`-t 2` 表格输出）。

---

## 五、环境安装（官方镜像优先，不维护本地配方）

**首句声明**：NGSQCToolkit 在官方渠道（bioconda → quay.io/biocontainers →
depot.galaxyproject.org）**均无 conda 包与官方镜像**（2026-09 核实），且**软件已淘汰**
→ 本模块**不维护 Dockerfile/Apptainer.def**（维护已淘汰软件的容器配方无意义）。
以下仅登记宿主机历史复现的安装方式；**新项目请勿安装，直接改用 trimmomatic/fastp/
cutadapt**。

### 1. Conda / brew（包管理器安装）

- **conda 无法直接装软件本体**（bioconda/conda-forge 无 `ngsqctoolkit` 包，api 404）；
  conda 仅用于搭建 perl 运行环境（perl + CPAN 依赖的 conda 打包版，均 2026-09 在线核实）：
  ```bash
  mamba env create -f native/environment.yml      # 环境名 ngsqctoolkit-native
  # 验证依赖可加载：
  mamba run -n ngsqctoolkit-native perl -e 'require String::Approx; require YAML; require GD; print qq(deps OK\n)'
  ```
- **brew**：homebrew-core 无 `ngsqctoolkit` 公式（formulae.brew.sh 404，2026-09），
  brewsci/bio 亦无 → 不登记 brew 安装块；brew 只用于给 cpan 路线提供系统库
  （`brew install gd`）。
- 一键安装（conda/cpan 双路线 + 脚本包下载，历史复现用）：
  ```bash
  bash native/install.sh          # auto：有 conda 走 conda 路线，否则 cpan 路线
  bash native/install.sh --method cpan --prefix ~/software/ngsqctoolkit-2.3.3
  ```

### 2. Docker（官方镜像）

无官方镜像（bioconda 无包 → quay.io/biocontainers 无自动构建；quay API 需认证，
未直接核实 repo 空置）。已淘汰 → **不产出自建 Dockerfile**。若必须在容器里复现旧
流程，可用通用 perl 镜像自行装依赖（**说明性示例，非推荐路线**）：

```bash
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    perl:5.36 cpanm -n String::Approx YAML GD GDTextUtil GDGraph
```

### 3. Apptainer / Singularity

无官方预构建 sif（无 biocontainer 镜像）；已淘汰 → 不提供本地 def 配方。需要时同上
用通用 perl 镜像转换（`apptainer pull perl.sif docker://perl:5.36`），并自行装依赖。

### 4. 二进制/源码包安装（官网 zip / GitHub 镜像，历史复现唯一本体来源）

官网 zip 已核实 404；当前可获取的本体：**用户修复镜像 `SiYangming/NGSQCToolkit`
（tag/release v2.3.3，2026-09-08，对应官方最终 2.3.3，主源）** + 作者 lab 镜像
`mjain-lab/NGSQCToolkit`（仅到 v2.3，旧版备选）。一键安装走 `native/install.sh`；
手动步骤：

```bash
mkdir -p ~/software && cd ~/software
# 官网 zip（2026-09-08 核实 404，保留 URL 供官网恢复时使用）：
# wget https://www.nipgr.ac.in/ngsqctoolkit/NGSQCToolkit_v2.3.3.zip
# 主源：用户修复镜像 tag v2.3.3（对应官方最终 2.3.3；无官方 sha256，解压自检）
wget https://codeload.github.com/SiYangming/NGSQCToolkit/zip/refs/tags/v2.3.3 \
    -O NGSQCToolkit-2.3.3.zip
unzip NGSQCToolkit-2.3.3.zip
mv NGSQCToolkit-2.3.3 ~/software/ngsqctoolkit-2.3.3   # 解压目录名以实际 zip 为准
chmod +x ~/software/ngsqctoolkit-2.3.3/{QC,Trimming,Statistics,Format-converter}/*.pl
export NGSQCTOOLKIT_ROOT="$HOME/software/ngsqctoolkit-2.3.3"   # main.py 缺省读取
# 备选：作者 lab 镜像 main 分支（仅到 v2.3，无 2.3.3 后续）：
# wget https://codeload.github.com/mjain-lab/NGSQCToolkit/zip/refs/heads/main \
#     -O NGSQCToolkit-main.zip && unzip NGSQCToolkit-main.zip
# 版本说明：mjain-lab release tag 为 v2.3；SiYangming tag 为 v2.3.3（修复版）
```

---

## 六、版本

- NGSQCToolkit **2.3.3**（官网最终版，2014-08 发布；2024 年文献仍引用该版本号；
  ILRI HPC 记录佐证；2026-09 官网 zip 404 无法复核包内版本号）
- GitHub 作者 lab 镜像：**v2.3**（2021-03-19 上传，`mjain-lab/NGSQCToolkit`，
  16 stars / 3 forks，最后一次 push 2021-03；含官方 v2.3 手册 PDF；release tag `v2.3`）
- 用户修复镜像：**v2.3.3**（`SiYangming/NGSQCToolkit`，fork 修复版；2026-09-08 tag
  v2.3.3 并 release，内容对应官方最终 2.3.3——官网 zip 404 后的主本体来源；
  作者镜像 mjain-lab 仅到 v2.3，无后续更新）
- 实现 ID / 版本登记：`ngsqctoolkit_native` → 2.3.3（argv 构造驱动本身与本体版本无关）
- Perl 依赖：见「四、4.2」清单（CPAN 在线核实）；官方渠道无 conda 包、无 nf-core
  模块、无 snakemake-wrappers wrapper（均 404 核实）→ `software_versions` 中相关
  登记项注明 deprecated + 替代。

## 七、容器与 Conda 链接

- **官网**：<https://www.nipgr.ac.in/NGSQCToolkit.php>（❌ 2026-09-08 核实 404）
- **官网 zip**：<https://www.nipgr.ac.in/ngsqctoolkit/NGSQCToolkit_v2.3.3.zip>
  （❌ 404；sha256 从未有官方发布）
- **GitHub 镜像（下载兜底）**：作者 lab <https://github.com/mjain-lab/NGSQCToolkit>
  （v2.3，无后续）｜**用户修复版（主源，v2.3.3）**：
  <https://github.com/SiYangming/NGSQCToolkit>（tag/release v2.3.3，对应官方 2.3.3）
- **conda**：bioconda `ngsqctoolkit` 不存在（404）；conda 仅兜底 perl 环境
  （`native/environment.yml`：conda-forge `perl` + `perl-app-cpanminus`；bioconda
  `perl-string-approx`/`perl-yaml`/`perl-gd`/`perl-gdgraph`/`perl-gdtextutil`）
- **Docker / Singularity**：无官方镜像（推断无自动构建）；已淘汰 → 不维护本地容器配方
- **CPAN 依赖**：String::Approx / YAML / GD / GD::Text / GD::Graph（在线核实，见 §4.2）
- 安装方式（本地，历史复现）：`bash native/install.sh`（见 §5.1/§5.4）
- ⚠️ 新项目请使用替代模块：`modules/trimmomatic`、`modules/fastp`、`modules/cutadapt`、
  `modules/fastqc`
