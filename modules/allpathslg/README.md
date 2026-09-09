# allpathslg 软件模块（ALLPATHS-LG — 短读 de novo 组装 + FindErrors/KmerSpectrumPlot）

> # ⚠️ DEPRECATED — 已淘汰，仅历史参考登记
>
> **ALLPATHS-LG** 是 Broad Institute 的**短读（Illumina）de novo 组装器**
> （Gnerre et al. *PNAS* 2011；OLC/k-mer 混合图），要求 **≥2 个文库**
> （fragment：短插入重叠 + jumping：长插入 ≥3 kb）与高深度（推荐 ≥100X）。
> 软件包同时含 **FindErrors**（`ErrorCorrectReads.pl`，PE 纠错/overlap 拼接与
> 基因组特征评估）与 **KmerSpectrumPlot.pl**（k-mer 频谱图）两个 QC 子工具。
> 上游 **~2013 年 r52488 后停止发布**，Broad FTP（ftp.broadinstitute.org）已整体
> 关闭、官网页面下线（2026-09 核实）→ **官方分发点失效**。
>
> **新项目请勿使用**——短读组装改用 SPAdes / MaSuRCA / ABySS 等。本模块只做
> 「录入」：方法/命令/链接准确登记、不产出自建容器配方，仅供复现 2011–2013
> 时代的 ALLPATHS-LG 分析（含旧文献中 FindErrors 纠错流程）。

***

## native 实现（说明型 / 命令构造，`source_type: custom` / `type: native`）

`native/main.py` 按历史教程构造 ALLPATHS-LG 命令行（KEY=VALUE 形态）并打印，
**不实际执行**（软件 deprecated、官方下载点下线）。四个子命令：

| 子命令 | 实际构造命令 | 作用 |
| ---- | ---- | ---- |
| `prepare` | `PrepareAllPathsInputs.pl DATA_DIR=… PLOIDY=1 IN_GROUPS_CSV=… IN_LIBS_CSV=… [GENOME_SIZE=…] OVERWRITE=True` | 输入准备：读 in_groups/in_libs → data 目录（fastb/pairs/qualb） |
| `assemble` | `RunAllPathsLG PRE=… REFERENCE_NAME=… DATA_SUBDIR=data RUN=run SUBDIR=test OVERWRITE=True MAXPAR=1` | 主组装 → `…/ASSEMBLIES/<SUBDIR>/final.assembly.fasta` |
| `errorcorrect` | `ErrorCorrectReads.pl PHRED_ENCODING=33 READS_OUT=… [KEEP_KMER_SPECTRA=1] [FILL_FRAGMENTS=1] PAIRED_READS_A_IN=… PAIRED_READS_B_IN=… PLOIDY=1 PAIRED_SEP=… PAIRED_STDEV=…` | **FindErrors** 双端纠错（评估基因组大小/重复/杂合率） |
| `kspec` | `KmerSpectrumPlot.pl SPECTRA=1` | k-mer 频谱绘图（在 `<READS_OUT>.fastq.kspec` 内运行） |

```bash
# CLI 直跑（构造历史命令，仅供复现）
python main.py prepare --data-dir $PWD/E_coli.genome/data \
    --in-groups-csv in_groups.csv --in-libs-csv in_libs.csv --ploidy 1
python main.py assemble --pre $PWD --ref-name E_coli.genome --run run --subdir test
python main.py errorcorrect --reads-out illumina \
    --paired-reads-a illumina.1.fastq --paired-reads-b illumina.2.fastq \
    --paired-sep 68 --paired-stdev 66 --keep-kspec
python main.py kspec
# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

> 每个子命令支持 `--threads` / `--tmpdir`（占位兼容，旧版并行靠 MAXPAR / 环境变量）。
> 构造命令经 stderr 打印 deprecated 提示，stdout 只输出命令本身。

***

## 实战示例：RunAllPathsLG 组装（历史流程）

以 E. coli 双文库（fragment + jumping）为例，等价能力由 `native/main.py` 的
prepare / assemble 子命令提供（见上）：

```bash
mkdir -p ALLPATHS-LG && cd ALLPATHS-LG
# 0) 数据符号链接（fragment.?.fastq / jumping.?.fastq，? 通配 R1/R2）
ln -s ~/.../fragment.1.fastq fragment.1.fastq && ln -s ~/.../fragment.2.fastq fragment.2.fastq
ln -s ~/.../jumping.1.fastq jumping.1.fastq && ln -s ~/.../jumping.2.fastq jumping.2.fastq

# 1) 分组表（group_name, library_name, file_name）
printf 'frags, Illumina_180bp, fragment.?.fastq\njumps, Illumina_3000bp, jumping.?.fastq\n' \
  > in_groups.csv

# 2) 文库表（12 列；fragment 填 frag_size/stddev，jumping 填 insert_size/stddev；
#    方向 fragment=inward、jumping=outward）
printf 'library_name, project_name, organism_name, type, paired, frag_size, frag_stddev, insert_size, insert_stddev, read_orientation, genomic_start, genomic_end\nIllumina_180bp, E_coli.genome, E.coli, fragment, 1, 177, 25, , , inward, 0, 0\nIllumina_3000bp, E_coli.genome, E.coli, jumping, 1, , , 3014, 1204, outward, 0, 0\n' \
  > in_libs.csv

# 3) 准备输入（DATA_DIR 必须绝对路径；organism_name 与目录名一致）
mkdir -p E_coli.genome/data
PrepareAllPathsInputs.pl \
  DATA_DIR=$PWD/E_coli.genome/data \
  PLOIDY=1 IN_GROUPS_CSV=in_groups.csv IN_LIBS_CSV=in_libs.csv \
  OVERWRITE=True | tee prepare.out

# 4) 运行组装（旧版 MAXPAR 建议 1；大基因组先 ulimit -s 100000 调大栈）
ulimit -s 100000
RunAllPathsLG PRE=$PWD REFERENCE_NAME=E_coli.genome DATA_SUBDIR=data \
  RUN=run SUBDIR=test OVERWRITE=True MAXPAR=1 | tee -a assemble.out

# 5) 格式化结果（final.assembly.fasta 为 Efasta；拆分为 scaffold .fsa 并去 'n'）
ln -s E_coli.genome/data/run/ASSEMBLIES/test/final.assembly.fasta ./
EfastaToFasta HEAD=E_coli.genome/data/run/ASSEMBLIES/test/final.assembly \
  SPLIT_DIR=scaffolds IUPAC=False
perl -p -i -e 's/n/N/g' scaffolds/*.fsa && cat scaffolds/*.fsa > allpathslg.fasta
```

> 要求：fragment 插入长度需 < 2×读长（保证双端重叠）；官方建议基因组覆盖 ≥100X；
> 内存需求大（哺乳动物 ~512 G、小基因组 ~32 G）。**发布已停止**，其要求现被
> SPAdes / MaSuRCA 等更易用的短读组装器取代。

***

## 实战示例：FindErrors + KmerSpectrumPlot（历史流程）

ALLPATHS-LG 软件包内含两个重要 QC 子工具（FindErrors / KmerSpectrumPlot）：

- **FindErrors（`ErrorCorrectReads.pl`）**：对 Paired-End 测序数据做错误修正，可将
  有 overlap 的 paired-end 两端连成一条更长的序列，同时评估基因组大小、重复序列
  含量、杂合率等信息。
- **KmerSpectrumPlot.pl**：绘制 k-mer 频谱图，可视化 k-mer 深度分布，辅助评估
  基因组特征（大小/重复/杂合）。

```bash
# 1) fragment（PE，方向正常）：纠错 + 连 overlap 双端（FILL_FRAGMENTS=1）
ErrorCorrectReads.pl PHRED_ENCODING=33 READS_OUT=illumina FILL_FRAGMENTS=1 \
  KEEP_KMER_SPECTRA=1 \
  PAIRED_READS_A_IN=illumina.1.fastq PAIRED_READS_B_IN=illumina.2.fastq \
  PLOIDY=1 PAIRED_SEP=68 PAIRED_STDEV=66 &> ErrorCorrectReads.log
ln -s illumina.paired.A.fastq illumina.1.fastq
ln -s illumina.paired.B.fastq illumina.2.fastq

# 2) jumping（mate-pair，方向相反）：先反向互补 → 纠错 → 再 rc 还原
fastq_rc.pl jumping.1.fastq > jumping_rc.1.fastq
fastq_rc.pl jumping.2.fastq > jumping_rc.2.fastq
ErrorCorrectReads.pl PHRED_ENCODING=33 READS_OUT=jumping1 \
  PAIRED_READS_A_IN=jumping_rc.1.fastq PAIRED_READS_B_IN=jumping_rc.2.fastq \
  PLOIDY=1 PAIRED_SEP=3000 PAIRED_STDEV=1000
fastq_rc.pl jumping1.paired.A.fastq > jumping.1.fastq
fastq_rc.pl jumping1.paired.B.fastq > jumping.2.fastq

# 3) k-mer 频谱图（在 <READS_OUT>.fastq.kspec 目录内；必要时按需改 @fns 列表）
cd illumina.fastq.kspec
KmerSpectrumPlot.pl SPECTRA=1
convert kmer_spectrum.distinct.log.log.eps kmer_spectrum.distinct.log.log.png
```

**参数说明（ErrorCorrectReads.pl）**：

| 参数 | 说明 |
| ---- | ---- |
| `PHRED_ENCODING=33` | Phred+33 质量格式 |
| `READS_OUT=` | 输出前缀（`<前缀>.paired.A/B.fastq`、`<前缀>.fastq.kspec/`） |
| `KEEP_KMER_SPECTRA=1` | 保留 k-mer 频谱（供 KmerSpectrumPlot 绘图） |
| `FILL_FRAGMENTS=1` | 把 overlap 双端连成更长序列 |
| `PAIRED_READS_A_IN` / `PAIRED_READS_B_IN` | 双端输入 FASTQ |
| `PAIRED_SEP=` | 插入片段长度（bp；jumping 需先 rc 再纠错再还原） |
| `PAIRED_STDEV=` | 插入片段标准差 |
| `PLOIDY=` | 倍性（1 单 / 2 二倍体） |

**参数说明（KmerSpectrumPlot.pl）**：`SPECTRA=1` 生成频谱图（输出
`kmer_spectrum.{cumulative_frac.log.lin,distinct.lin.lin,distinct.log.log}.eps`）。

***

## 测试

```bash
bash test/run_test.sh   # argv 构造 + parser + schema 自省为常驻断言（不下载/不编译）
```

## 环境安装（官方镜像优先，不维护本地配方）

> 官方现状（2026-09-08 在线核实，如实记录）：**无官方当前渠道**——bioconda /
> conda-forge 无 allpathslg 包（anaconda.org 404）→ 无 quay.io/biocontainers 与
> depot.galaxyproject.org 镜像；nf-core / snakemake-wrappers 均无该软件；Homebrew
> 两源无公式（旧 homebrew-science tap 2016-2017 已归档移除，仅其历史公式留下
> r52488 tar.gz sha256）。**Broad FTP 与官网页面已下线** → 软件 deprecated、
> **不维护本地 Dockerfile/Apptainer.def 配方**；宿主机复现唯一路线＝从历史存档
> 恢复源码 tarball 再编译（GCC 4.8 环境实测最稳）。**新项目请直接用 SPAdes。**

### 1. Conda / brew（包管理器安装）

```bash
# Conda：无官方包（bioconda/conda-forge 均无 allpathslg）→ 无 conda 安装路线。
# Homebrew：homebrew-core 404、brewsci/bio 404（旧 homebrew-science 公式已移除）
#   → 不登记 brew 块。
# main.py 驱动环境（python3+pyyaml）见 native/environment.yml：
conda env create -f native/environment.yml
```

> brew 判定记录：homebrew-core `formulae.brew.sh/api/formula/allpathslg.json` 404；
> brewsci/homebrew-bio `Formula/allpathslg.rb` 404；历史 homebrew-science
> `allpaths-lg.rb`（r52488，sha256 035b49cb…）随 tap 归档移除 → 两源均无公式。

### 2 / 3. Docker / Apptainer（官方镜像）

无（bioconda 无包 → quay.io/biocontainers、depot.galaxyproject.org 无自动构建；
历史镜像未见登记）。不产出自建配方（deprecated + 下载点下线）。

### 4. 预编译包 / 源码安装（私有备份存档，需 GitHub 鉴权）

官方分发点已下线；可获取本体＝**本人私有仓库 `SiYangming/ALLPATHS-LG`
（private，2026-09-08 登记）**：源码 tarball（`source/allpathslg-52488.tar.gz`）＋
release **v1.0** 两个预编译资产。所有直链需 GitHub 鉴权（`gh auth login` 或浏览器
登录态），本人账号外不可达。

**预编译二进制包（历史教程推荐；免编译，解压即用）**

```bash
cd ~/software
# 拉取 release v1.0 全部 tar.gz 资产（gh 已登录；仓库 private 仅本人可下）
gh release download v1.0 -R SiYangming/ALLPATHS-LG --pattern '*.tar.gz' -D ~/software
# 或网页：https://github.com/SiYangming/ALLPATHS-LG/releases/tag/v1.0

# CentOS 8.1 预编译（历史教程推荐；原解压到 /opt/biosoft，此处用户前缀免 root）
tar zxf ALLPATHS-LG.CentOS8.1_1911_opt_biosoft.tar.gz -C ~/software
# CentOS 6 时代预编译（二进制包安装方案）
tar zxf ALLPATHS-LG_r52488.tar.gz -C ~/software
# 两包解压后均为 ALLPATHS-LG/ 目录（含 bin/；历史教程把 bin 加入 PATH）
export PATH="$HOME/software/ALLPATHS-LG/bin:$PATH"
```

**源码编译（需历史存档 tarball；耗时长、旧 GCC 环境较稳）**：

```bash
# ① 获取 r52488 源码 tarball（私有备份；网页 blob 或 gh CLI 均可）
gh repo clone SiYangming/ALLPATHS-LG /tmp/allpaths-lg-backup
cp /tmp/allpaths-lg-backup/source/allpathslg-52488.tar.gz ~/software/
#    原址（已不可达，仅记录）：ftp://ftp.broadinstitute.org/pub/crd/ALLPATHS/Release-LG/
#      latest_source_code/allpathslg-52488.tar.gz
#    sha256（旧 homebrew-science 公式记录；恢复后核对）：
#    035b49cb21b871a6b111976757d7aee9c2513dd51af04678f33375e620998542
# ② 编译安装（源码编译耗时，需耐心；依赖 GCC ≥4.7/4.8 + GMP/MPFR/MPC +
#    libieee1284→libieee + graphviz）
tar zxf allpathslg-52488.tar.gz && cd allpathslg-52488/
./configure --prefix=$HOME/software/allpathslg
make -j 4 && make install
echo 'export PATH=$PATH:~/software/allpathslg/bin/' >> ~/.bashrc && source ~/.bashrc
# ③ 冒烟（官方以 test 数据验证）：bin 下应有 PrepareAllPathsInputs.pl /
#    RunAllPathsLG / ErrorCorrectReads.pl / KmerSpectrumPlot.pl / EfastaToFasta
```

> 预编译/源码资产均无官方 sha256 摘要（release 未附校验值）：预编译包以
> `tar tzf` 内目录 + `bin/RunAllPathsLG` 存在性自检；源码包恢复后核对
> `035b49cb…`。

> 现代 Ubuntu/Debian 编译该 2011 年代源码的已知坑（历史社区记录，供复现参考）：
> 高版本 GCC 会报 `CleanEfasta.o` 编译失败（建议 g++-4.8）；glibc 2.27+ 缺
> `-lieee`（`apt install libieee1284-3` 后 `ln -s /usr/lib/x86_64-linux-gnu/
> libieee1284.so.3 /usr/lib/libieee.so`）。

## 替代建议（新项目请直接使用）

| 替代工具 | 说明 | 官方入口 |
| ---- | ---- | ---- |
| **SPAdes** | 短读/单细胞/hybrid de novo 组装（当前主流，发育完善） | <https://github.com/ablab/spades>（bioconda `spades`） |
| **MaSuRCA** | 短读/长读 hybrid 组装（融合 OLC+deBruijn） | <https://github.com/alekseyzimin/masurca>（bioconda `masurca`） |
| **fastp / trimmomatic** | reads 纠错/质控替代 FindErrors 的日常清洗 | 本仓库 modules/fastp、modules/trimmomatic |

## 版本

* **r52488**（源码 `allpathslg-52488`；Broad「LATEST_VERSION」即此版，~2013 冻结；
  部分文档误写 52448，以 tar 目录名 52488 为准）
* 私有备份 release **v1.0**（`SiYangming/ALLPATHS-LG`，2026-09-08，private）：两个
  预编译资产 `ALLPATHS-LG.CentOS8.1_1911_opt_biosoft.tar.gz`（CentOS 8.1 预编译，
  历史教程推荐）与 `ALLPATHS-LG_r52488.tar.gz`（CentOS 6 时代二进制包）——均对应
  r52488，无官方 sha256（见「环境安装 §4」）
* License：**custom**（Broad 自定义条款——免费学术/科研使用、发表需引用
  Gnerre et al. PNAS 2011；2026-09 官网下线无法复核更细条款）
* 引用：Gnerre S. et al. *PNAS* 2011, 108(4):1513-8（doi:10.1073/pnas.1017351108）
* nf-core / snakemake-wrappers：无官方子模块（2026-09-08 核实 404）→ 不登记官方说明层

## 历史留存

* **来源**：用户「生物信息实践教程」ALLPATHS-LG（含 FindErrors / KmerSpectrumPlot）
  两节合并登记为单软件模块（FindErrors/KmerSpectrumPlot 是 ALLPATHS-LG 包内子工具，
  不单独成模块）；安装方案（预编译二进制包 CentOS 6/8 等）已并入上文「环境安装」。
* **官方下载点下线说明**：ftp.broadinstitute.org 与
  www.broadinstitute.org/software/allpaths-lg/ 均不可达（2026-09 核实）→ README 只
  记录原址与重建方式，**tarball 本体已备份于本人私有仓库**
  `SiYangming/ALLPATHS-LG`（source/allpathslg-52488.tar.gz，private；bioskills 仓库
  本身不保存大文件）。

## 容器与 Conda 链接

* **官网（已下线）**：<http://www.broadinstitute.org/software/allpaths-lg/blog/>
* **原下载（已下线）**：<ftp://ftp.broadinstitute.org/pub/crd/ALLPATHS/Release-LG/latest_source_code/allpathslg-52488.tar.gz>
* **用户私有备份（tarball 存档）**：<https://github.com/SiYangming/ALLPATHS-LG>
  （**private**，2026-09-08 登记；`source/allpathslg-52488.tar.gz`，仅本人账号
  可见，拉取需 GitHub 鉴权，见「环境安装 §4」①）
  - release **v1.0** 预编译资产（private，下载见「环境安装 §4」）：
    `ALLPATHS-LG.CentOS8.1_1911_opt_biosoft.tar.gz`（CentOS 8.1）｜
    `ALLPATHS-LG_r52488.tar.gz`（CentOS 6 时代）——
    <https://github.com/SiYangming/ALLPATHS-LG/releases/tag/v1.0>
* **conda**：无（bioconda/conda-forge 404）
* **Docker / Singularity**：无官方镜像
* **brew**：无公式（两源 404；旧 homebrew-science 已归档移除）
* 安装方式（本地）：源码编译（需存档恢复），见「环境安装」§4
