# sopra 软件模块（SOPRA — paired-end 数据 scaffolding 工具）

> # ⚠️ DEPRECATED — 已淘汰，仅历史参考登记
>
> **SOPRA（Statistical Optimization of Paired Read Assembly，v1.4.6）** 是基于
> paired-end / mate-pair 数据把 contigs 连接成 scaffolds 的组装后处理工具
> （Dayarian et al. 2010, *BMC Bioinformatics* 11:345），由一组 Perl 脚本组成：
> `s_prep_contigAseq_v1.4.6.pl`（准备 contig+mate 序列）、`s_parse_sam_v1.4.6.pl`
> （解析 bowtie2 SAM）、`s_read_parsed_sam_v1.4.6.pl`（统计方向/距离）、
> `s_scaf_v1.4.6.pl`（输出 scaffold），比对步骤依赖 **bowtie2**。
> 上游 **v1.4.6（2011-08）之后停止维护**；文档所给 GitHub
> <https://github.com/schneebergerlab/SOPRA> 2026-09-11 探测 **404（不存在）**；
> 真实官网（Rutgers）<http://www.physics.rutgers.edu/~anirvans/SOPRA/> 探测
> **HTTP 200**，官方下载 `SOPRA_v1.4.6.zip` 实测 200（625035 字节）。
>
> **新项目请勿使用**——scaffolding 已被 **SSPACE / SOAPdenovo 内置功能 / BESST /
> LINKS** 等替代。本模块只做「录入」：方法/命令/链接准确登记、不产出自建容器配方
> （Dockerfile/Apptainer.def），仅供复现 2011 时代的 SOPRA 分析。

***

## native 实现（说明型 / 命令构造，`source_type: custom` / `type: native`）

本实现为「说明型 + 命令构造」：`native/main.py` 按官方 `.pl` 脚本用法构造命令行并打印，
**不实际执行**（软件 deprecated、无官方容器/conda、无新用场景）。子命令：

| 子命令 | 实际构造命令 | 作用 |
| ---- | ---- | ---- |
| `prep` | `s_prep_contigAseq_v1.4.6.pl -contig <contig.fa> -mate <frag.fa> [<jump.fa>] -a <dir>` | 准备 contig+mate 序列 |
| `parse_sam` | `s_parse_sam_v1.4.6.pl -sam <sam...> -a <dir>` | 解析 bowtie2 SAM |
| `read_parsed_sam` | `s_read_parsed_sam_v1.4.6.pl -parsed <p1> -d <d1> [-parsed <p2> -d <d2>] -a <dir>` | 统计方向/距离 |
| `scaf` | `s_scaf_v1.4.6.pl -o <orientdistinfo_c5> -a <dir>` | 进行 scaffold 连接 |

```bash
# CLI 直跑（构造历史命令，仅供复现；先装 SOPRA v1.4.6，见「环境安装」）
python main.py prep --contig contig.fasta --mate-frag frag.fasta \
    --mate-jump jump.fasta -a SOPRA_OUT
python main.py parse_sam --sam frag_sopra.sam jump_sopra.sam -a SOPRA_OUT
python main.py read_parsed_sam --parsed frag_sopra.sam_parsed --distance 177 \
    --parsed jump_sopra.sam_parsed --distance 3014 -a SOPRA_OUT
python main.py scaf --orient orientdistinfo_c5 -a SOPRA_OUT

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads`（SOPRA 的 `.pl` 本身单线程，该值仅用于 bowtie2 比对步骤，
未在本驱动透传）与 `--tmpdir`。构造命令通过 stderr 打印 deprecated 提示，
stdout 只输出命令本身。

***

### 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `-contig <contig.fa>` | `prep`：输入 contigs FASTA |
| `-mate <frag.fa> [<jump.fa>]` | `prep`：配对末端片段库（frag）与跳步库（jump）FASTA |
| `-sam <sam...>` | `parse_sam`：bowtie2 单端比对 SAM（可多个：frag/jump） |
| `-parsed <sam>_parsed` | `read_parsed_sam`：`parse_sam` 产物 |
| `-d <int>` | `read_parsed_sam`：对应文库插入距离（文档示例 frag=177、jump=3014） |
| `-o <prefix>` | `scaf`：方向/距离信息前缀（文档示例 `orientdistinfo_c5`） |
| `-a <dir>` | 分析目录（所有子命令的产物目录） |

### 完整历史流程（比对用 bowtie2）

```bash
# 1) mate-pair 反向互补 + 合并 PE 序列（bowtie2 附带的 helper）
fastq_rc.pl jumping.1.fastq > jump_rc.1.fastq
fastq_rc.pl jumping.2.fastq > jump_rc.2.fastq
shuffleSequences_fastq.pl fragment.1.fastq fragment.2.fastq frag.fastq
shuffleSequences_fastq.pl jump_rc.1.fastq jump_rc.2.fastq jump.fastq
# 2) fastq -> fasta
perl -e '$num=1; while(<>){print ">$num\n"; $_=<>; print; $_=<>; $_=<>; $num++}' frag.fastq > frag.fasta
# 3) 准备 contig（本驱动 prep 子命令）
s_prep_contigAseq_v1.4.6.pl -contig contig.fasta -mate frag.fasta jump.fasta -a SOPRA_OUT/
# 4) bowtie2 单端比对
cd SOPRA_OUT && bowtie2-build contigs_sopra.fasta contig
bowtie2 -p 4 -x contig -k 10 -f -3 15 -U frag_sopra.fasta -S frag_sopra.sam
bowtie2 -p 4 -x contig -k 10 -f -5 15 -U jump_sopra.fasta -S jump_sopra.sam
# 5) 解析 SAM（parse_sam）→ 6) 方向/距离（read_parsed_sam）→ 7) scaffold（scaf）
```

## 测试

```bash
bash test/run_test.sh   # argv 构造 + parser + schema 自省为常驻断言（不下载/不编译）；
                        # stub 假脚本 CLI 冒烟恒跑
```

## 环境安装（历史官方渠道；无官方镜像，不维护本地配方）

> 官方现状（2026-09-11 在线核实，如实记录）：**上游停更**，文档所给 GitHub 链接 404；
> 真实官网（Rutgers）200、官方 zip 可下载、SourceForge 有镜像；**bioconda sopra 404**、
> quay.io/biocontainers / depot.galaxyproject.org 无镜像、brew 无公式 → 判定「无官方
> 容器/conda 渠道」；软件 deprecated → **不维护本地 Dockerfile/Apptainer.def 配方**。

### 1. 官方源码（Perl 脚本）安装

```bash
# 历史教程原为 /opt/biosoft/SOPRA_v1.4.6（root 全局限定路径）；
# 本 README 一律改写为用户前缀 ~/software/SOPRA_v1.4.6（免 root）
mkdir -p ~/software/SOPRA_v1.4.6
cd ~/software/SOPRA_v1.4.6
curl -fL -o SOPRA_v1.4.6.zip \
    http://www.physics.rutgers.edu/~anirvans/SOPRA/SOPRA_v1.4.6.zip
unzip -o SOPRA_v1.4.6.zip
chmod 755 source_codes_v1.4.6/SOPRA_with_prebuilt_contigs/*.pl
# 规范化行尾（文档 04.md 步骤）
perl -p -i -e 's/\s*$/\n/' source_codes_v1.4.6/SOPRA_with_prebuilt_contigs/*.pl
export PATH="$HOME/software/SOPRA_v1.4.6/source_codes_v1.4.6/SOPRA_with_prebuilt_contigs:$PATH"
```

> SourceForge 镜像（200）：<https://sourceforge.net/projects/sopra/>

### 2. 依赖：bowtie2（比对步骤）

```bash
# SOPRA 的比对步骤用 bowtie2 单端比对；现代 bowtie2 走 bioconda 即可
mamba install -c conda-forge -c bioconda bowtie2
# 历史教程从源码编译 bowtie2 2.3.0 并另装 TBB（threadingbuildingblocks）；
# 现代 conda bowtie2 已内置所需依赖，无需手工 TBB。
```

### 3. Conda / brew（均无）

* conda：**bioconda 无 sopra 包**（2026-09-11 核实 404）→ 不登记。
* Homebrew：formulae.brew.sh/api/formula/sopra.json 404（2026-09-11 核实）→ 不登记。

### 4. Docker / Apptainer（均无）

bioconda 无 sopra → 无 quay.io/biocontainers/sopra、无 depot.galaxyproject.org 镜像
（2026-09-11 核实）；软件 deprecated → 不产出自建配方文件。

## 替代建议（新项目请直接使用）

| 替代工具 | 说明 | 官方入口 |
| ---- | ---- | ---- |
| **SSPACE / SSPACE-LongRead** | 经典 paired-end/长读 scaffolder | <https://github.com/nsoranzo/sspace_basic>（bioconda `sspace_basic`） |
| **BESST** | 基于比对结果的 scaffolding | <https://github.com/ksahlin/BESST> |
| **LINKS** | 长读 scaffolding | <https://github.com/bcgsc/LINKS>（bioconda `links`） |
| **SOAPdenovo 内置 scaffolding** | 组装器内建 scaffold 阶段 | <https://github.com/aquaskyline/SOAPdenovo2> |

## 版本

* **1.4.6**（SOPRA v1.4.6，2011-08 最后发布；2026-09-11 在线核实官方 Rutgers 归档
  仍可下载、文档所给 GitHub 链接 404）
* bioconda：**无**（2026-09-11 api.anaconda.org 核实 404）
* License：官网页面未列出明确许可声明，未能在线复核
* 引用：Dayarian A, Michael TP, Sengupta AM. SOPRA: Scaffolding algorithm for
  paired reads via statistical optimization. *BMC Bioinformatics* 2010;11:345.
  doi:10.1186/1471-2105-11-345
* nf-core / snakemake-wrappers：无官方子模块（2026-09-11 核实
  `modules/nf-core/sopra`、`bio/sopra` 均 404）→ 不登记官方说明层

## 历史留存

* 历史教程常见安装前缀为
  **`/opt/biosoft/SOPRA_v1.4.6/source_codes_v1.4.6/SOPRA_with_prebuilt_contigs/`**
  （root 全局限定路径）；本 README 一律改写为**用户前缀** `~/software/...`（免 root）。
  原始发布包名：`SOPRA_v1.4.6.zip`（Rutgers 官网，仍可下载）。
* 文档所给 GitHub 链接 `schneebergerlab/SOPRA` **已 404**（2026-09-11 核实）；可用
  的官方来源为 Rutgers 官网与 SourceForge 镜像。
* 历史流程中 SOPRA 常以 Edena 等组装器产出的 `*_contigs.fasta` 作为 contig 输入；
  现代流程统一建议现代组装器 + 现代 scaffolder（BESST/LINKS）。

## 容器与 Conda 链接

* **官网（Rutgers，200）**：<http://www.physics.rutgers.edu/~anirvans/SOPRA/>
* **官方下载**（200，625035 字节）：
  <http://www.physics.rutgers.edu/~anirvans/SOPRA/SOPRA_v1.4.6.zip>
* **SourceForge 镜像（200）**：<https://sourceforge.net/projects/sopra/>
* **社区归档**：https://github.com/SiYangming/SOPRA
* **conda**：bioconda 无 `sopra`（404 核实）
* **Docker / Singularity**：无官方镜像（bioconda 404 核实）
* **brew**：无公式（homebrew-core 404 核实）
* **引用论文**：<http://www.biomedcentral.com/1471-2105/11/345>
