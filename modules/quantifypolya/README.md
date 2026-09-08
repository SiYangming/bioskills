# quantifypolya 软件模块

> 汇总说明：QuantifyPolyA 是 R 包（sourceforge 项目 **quantifypoly-a**，GPL-3，
> v0.3.0，纯 R 源码、无独立命令行二进制），用于长读 / 3' end RNA-seq poly(A)
> 位点定量与 APA（alternative polyadenylation）动态度量。本模块以 Rscript 驱动
> `run_quantifypolya.R` 调用 `Load.PolyA` → `Cluster.PolyA` → `Annotate.PolyA`
> → `Quantify.*` 完成分析；安装方式见「环境安装」，文件留存/重建记录见
> 「文件留存与重建」。
> conda / 容器规范包名（若未来发布）为 **r-quantifypolya**；canonical 目录名沿用
> R 包名小写形态 **quantifypolya**（不连字符，与 R 包 QuantifyPolyA 一致）。

***

## native 实现

# quantifypolya / native — Rscript 驱动的 poly(A) 定量与 APA 分析

本地自包含实现（`source_type: custom`、`type: native`）。软件本体为 R 源码包
（`NeedsCompilation: no`，2021-06 打包于 R 4.1 时代），`native/main.py` 以
`Rscript native/run_quantifypolya.R <params.tsv>` 方式调用 QuantifyPolyA 完成
标准流程：

```
每样本 poly(A) BED（4 列: seqnames strand coord score）
  → Load.PolyA                    读入全部样本
  → [Remove.IP（基因组 fasta）]   去除内部引发 poly(A)
  → Cluster.PolyA                 加权密度峰聚类 → PAC（poly(A) cluster）
  → [Annotate.PolyA（gff）]       注释 gene_id/type + 每样本计数
  → [Filter.PolyA（min_count）]   低丰度过滤
  → Quantify.Canonical/Gene/Split/CNCAPA（colData + contrast）组间 APA 动态度量
```

## 功能

| 子命令 | 实际调用 | 作用 |
| ---- | ---- | ---- |
| `quant` | `Rscript run_quantifypolya.R`（内部 Load.PolyA/Cluster.PolyA/Annotate.PolyA/Quantify.*） | poly(A) 位点定量：输出 `polyA_sites.tsv`（PAC 全表，含注释与每样本计数）；给定实验设计与对比组时另输出 `apa_<mode>.tsv` 组间 APA 动态度量表（canonical/gene/split/cncapa） |

## 用法

```bash
# CLI 直跑（位点定量 + Brain vs UHR 的 canonical APA 动态度量）
python main.py quant --bed-dir Human_MAQC --outdir results \
    --gff annotation.gff3 --col-data colData.tsv \
    --contrast condition,Brain,UHR --quant-mode canonical --threads 8

# 只做位点定量/聚类（无注释无对比；输出 PAC 簇表）
python main.py quant --bed-dir Human_MAQC --outdir results

# 显式 BED 文件列表 + Remove.IP（内部引发去除，需基因组 fasta）
python main.py quant --bed-files s1.bed,s2.bed --outdir results \
    --fasta genome.fa --max-gapwidth 24

# 其它 APA 度量模式 / 过滤 / 导出 RDS（供 Visualize.PolyA 下游画图）
python main.py quant --bed-dir Human_MAQC --outdir results \
    --gff anno.gff3 --col-data colData.tsv --contrast condition,Brain,UHR \
    --quant-mode split --min-count 10 --min-sample 1 --save-rds

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖：`--threads` 取 `auto`
（默认；不写 threads 参数，由 R 驱动按「物理核数-1」自动检测，供
`Cluster.PolyA(mc.cores=)`）或正整数（显式 pin）。

> 也可跳过 main.py 直接调 R 驱动（独立 CLI，参数名 `-`/`_` 等价）：
>
> ```bash
> Rscript run_quantifypolya.R --bed-dir Human_MAQC --outdir results \
>     --gff anno.gff3 --col-data colData.tsv --contrast condition,Brain,UHR
> # 产物：results/polyA_sites.tsv（+ results/apa_canonical.tsv）
> Rscript run_quantifypolya.R --help
> ```

## 实战示例：poly(A) 位点定量与组间 APA 分析

等价能力由 `native/main.py` 的 `quant` 子命令提供（见上「用法」）。官方协议与
生物学背景见 [QuantifyPoly(A) User Manual.pdf](https://sourceforge.net/projects/quantifypoly-a/files/QuantifyPoly%28A%29%20User%20Manual.pdf/download)
（原始文献：Ye C. et al., *Bioinformatics* 2022, QuantifyPoly(A)；SIRV/内参 spike-in
拷贝数校准可配合 `Quantify.CNCAPA` 使用）。

### 1. 输入文件准备

* **poly(A) 位点 BED**（每样本一个，无表头，Tab 分隔 4 列）：`seqnames<TAB>strand<TAB>coord<TAB>score`
  —— coord 为 poly(A) 位点单点坐标，score 为支持 read 数；**文件名去 `.bed` 即样本名**
  （须与 colData 行名一致）。可从 3' end 测序（如 FLAM-seq/PAL-seq/TAIL-seq/长读
  polyA 软件输出）整理得到。
* **基因注释 GFF3/GTF**（可选；`Annotate.PolyA` 需 GTF/GFF3 与染色体系名一致的
  fasta 配套，如 GENCODE 人类注释 + 对应基因组）。
* **实验设计表 colData.tsv**（可选；首列样本名，须含 `condition` 列）：

  ```bash
  # 官方示例数据（Human_MAQC，含 brain1/brain2/UHR1/UHR2 四个 .bed，见「文件留存与重建」）
  unzip Human_MAQC.zip -d ./Human_MAQC
  printf 'sample\tcondition\nbrain1\tBrain\nbrain2\tBrain\nUHR1\tUHR\nUHR2\tUHR\n' > colData.tsv
  ```

### 2. 运行分析

```bash
# 位点定量 + 组间 canonical APA 动态度量（Brain vs UHR）
python main.py quant --bed-dir Human_MAQC --outdir qpa_out \
    --gff gencode.v38.annotation.gff3 \
    --col-data colData.tsv --contrast condition,Brain,UHR \
    --quant-mode canonical --threads 8

# 结果结构
head qpa_out/polyA_sites.tsv   # 每行一个 PAC：seqnames start end width strand score center
                               # split_label gene_id type + 每样本一列计数（有 gff 时）
head qpa_out/apa_canonical.tsv # 基因 × APA 动态度量（有 colData+contrast 时）
```

### 3. 大批量分层运行（按染色体/样本组）

```bash
# 多组实验逐个跑（此处循环示范；实际建议 xargs -P 或流程编排）
for cond in Brain UHR; do
    python main.py quant --bed-dir Human_MAQC --outdir qpa_out_${cond} \
        --gff anno.gff3 --col-data colData.${cond}.tsv \
        --contrast condition,condA,condB &
done
wait
```

### 4. 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `--bed-dir` / `--bed-files` | 输入：含每样本一个 .bed 的目录，或逗号分隔 BED 列表（二选一必填） |
| `--outdir` | 输出目录（必填） |
| `--gff` | 基因注释 GFF3/GTF（注释 + 每样本计数 + APA 度量必需） |
| `--fasta` | 基因组 FASTA（可选；执行 Remove.IP 去除内部引发） |
| `--col-data` | 实验设计 TSV（首列样本名；与 `--contrast` 一起启用组间度量） |
| `--contrast` | `<组列>,<对照>,<处理>`（默认列 condition），如 `condition,Brain,UHR` |
| `--quant-mode` | `canonical`（基因 3'UTR PAC，默认）/ `gene` / `split` / `cncapa` |
| `--max-gapwidth` | PAC 聚类相邻位点最大 gap（默认 24 bp） |
| `--min-count` / `--min-sample` | Filter.PolyA 过滤（需 gff；默认不过滤） |
| `--save-rds` | 同时保存 `QuantifyPolyA.rds`（QpolyA 对象，供 Visualize.PolyA） |
| `--threads` | `auto`（默认，物理核数-1）或正整数（Cluster.PolyA mc.cores） |

## 测试

```bash
bash test/run_test.sh   # argv 构造 + schema 自省为常驻断言；
                        # Rscript+QuantifyPolyA 可用时再做真实回归（Load+Cluster 冒烟）
```

## 环境安装（官方镜像优先，不维护本地配方）

官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org → conda r 频道）
**均无** r-quantifypolya 的 conda 包与官方镜像（2026-09 在线核实：
`anaconda.org/bioconda/r-quantifypolya` soft-404、nf-core / snakemake-wrappers 子模块
404）→ 判定「无官方维护」。QuantifyPolyA 是纯 R 源码包、无编译代码，且依赖经
BiocManager/CRAN 安装，与通用 R 运行时解耦，因此本模块**不维护 Dockerfile/
Apptainer.def**（自建 R 镜像与官方 rocker/r-ver 重复）：容器场景直接用 rocker
基础镜像 + 本模块安装脚本装包即可（见 §2/§3）。

### 1. 包管理器安装（R CRAN / BiocManager / Conda）

R 是 QuantifyPolyA 的包管理器宿主；一键安装（auto 双路线：有 Rscript → R 源码
路线；无 Rscript 且有 conda → environment.yml 建独立 env 再补齐依赖）：

```bash
bash native/install.sh                       # auto：依赖 + QuantifyPolyA 0.3.0 全自动
bash native/install.sh --method R            # 强制 R 路线
bash native/install.sh --method conda        # 强制 conda 路线（--conda-env / --force 可选）
```

R 路线的底层是依赖配方脚本（也可单独运行，参数可传本地源码包实现完全离线安装）：

```bash
Rscript native/install_deps_QuantifyPolyA.R                        # 在线自动
Rscript native/install_deps_QuantifyPolyA.R ~/sw/QuantifyPolyA_0.3.0.tar.gz ~/sw/ggalt_0.4.0.tar.gz  # 离线
# 安装后断言
Rscript -e 'cat(as.character(packageVersion("QuantifyPolyA")))'
```

conda 兜底（`environment.yml`：r-base + ggalt + 需编译依赖预编译包；剩余 CRAN/Bioc
依赖由环境内 Rscript 跑 install_deps 补齐）：

```bash
mamba env create -f native/environment.yml          # 环境名 r-quantifypolya
mamba run -n r-quantifypolya Rscript native/install_deps_QuantifyPolyA.R
```

> Homebrew 无 QuantifyPolyA / r-quantifypolya 公式（formulae.brew.sh 404；
> brewsci/bio 亦无）——homebrew 的 `r` 公式只提供 R 本体，R 包统一走
> CRAN/BiocManager，故不登记 brew 块。

### 2. Docker

无官方镜像；通用 R 运行时路线（rocker/r-ver，官方 R 基础镜像）：

```bash
docker pull rocker/r-ver:4.5.2
# 运行态装包（或把 native/ 挂进容器跑 install_deps）
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    rocker/r-ver:4.5.2 Rscript native/install_deps_QuantifyPolyA.R
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    rocker/r-ver:4.5.2 Rscript native/run_quantifypolya.R /data/params.tsv
```

### 3. Apptainer / Singularity

无官方预构建 sif；同上用 rocker 通用 R 镜像构建：

```bash
apptainer pull r-quantifypolya.sif docker://rocker/r-ver:4.5.2
apptainer run -B $PWD:/data -H /data r-quantifypolya.sif \
    Rscript /data/native/install_deps_QuantifyPolyA.R
```

### 4. 源码归档安装（sourceforge，无官方 release 二进制，即官方源码归档）

QuantifyPolyA 官方只以 R 源码包（tar.gz）发布在 sourceforge 文件区，0.3.0 即最新：

```bash
cd ~/software
wget https://downloads.sourceforge.net/project/quantifypoly-a/QuantifyPolyA_0.3.0.tar.gz
R CMD INSTALL ~/software/QuantifyPolyA_0.3.0.tar.gz   # 依赖需先装（install_deps_QuantifyPolyA.R）
```

## 文件留存与重建（仓库最小化处置记录）

原 `modules/quantifypolya/` 根目录为「官方文件转储」（2025-11 归档），均已核实
**可从官方重新下载**后删除，精确重建方式如下（下载后放置 `~/software/` 即可）：

| 删除文件 | 处置理由 | 官方来源（重建 URL） |
| ---- | ---- | ---- |
| `QuantifyPolyA_0.3.0.tar.gz` | 官方最新版 0.3.0（2021-06-22），sourceforge 文件区可下载；本地文件打包日期/大小与官方一致 | <https://sourceforge.net/projects/quantifypoly-a/files/QuantifyPolyA_0.3.0.tar.gz/download> |
| `ggalt_0.4.0.tar.gz` | CRAN Archive 官方原件（sha256 与 CRAN 比对一致 `ec4ad778…`），可下载 | <https://cran.r-project.org/src/contrib/Archive/ggalt/ggalt_0.4.0.tar.gz> |
| `QuantifyPoly(A) User Manual.pdf` | 官方公开手册（463.6 kB，大小与官方一致），sourceforge 文件区可下载，不保留大 PDF | <https://sourceforge.net/projects/quantifypoly-a/files/QuantifyPoly%28A%29%20User%20Manual.pdf/download> |
| `QuantifyPolyA.Rproj` | 本机 RStudio 工程文件，无复用价值 | —（无需重建） |
| `Human_MAQC.zip` + `Human_MAQC/` | 官方示例数据（5.9 MB，4 个 .bed：brain1/brain2/UHR1/UHR2），文件区可下载 | <https://sourceforge.net/projects/quantifypoly-a/files/Human_MAQC.zip/download> |
| `Arabidopsis_FY.zip` + `Arabidopsis_FY/` | 官方示例数据（17.1 MB，12 个 .bed），文件区可下载 | <https://sourceforge.net/projects/quantifypoly-a/files/Arabidopsis_FY.zip/download> |
| `install_deps_QuantifyPolyA.R`（旧根目录版） | 有留存价值（依赖配方）→ 移动改造为 `native/install_deps_QuantifyPolyA.R`（本地包路径参数化 + 在线下载兜底） | 见该脚本头注与 §1 |

一键重建示例数据 + 离线安装：

```bash
mkdir -p ~/software && cd ~/software
wget https://downloads.sourceforge.net/project/quantifypoly-a/QuantifyPolyA_0.3.0.tar.gz
wget https://downloads.sourceforge.net/project/quantifypoly-a/Human_MAQC.zip
unzip Human_MAQC.zip
# 完全离线安装（两个源码包路径显式传入，跳过一切在线下载）
Rscript modules/quantifypolya/native/install_deps_QuantifyPolyA.R \
    ~/software/QuantifyPolyA_0.3.0.tar.gz ~/software/ggalt_0.4.0.tar.gz
```

> 注：sourceforge 直链在部分网络环境会被 CDN 拦截（本仓库维护环境实测 curl 直下
> 返回 HTML），浏览器打开 `/download` 页面即可正常下载；install_deps 下载失败时会
> 打印手动下载指引并可用本地路径参数重跑。

## 版本

* QuantifyPolyA **0.3.0**（sourceforge 最新版，2021-06-22 发布；2026-09-07 在线核实
  文件区 0.1.0/0.2.0/0.3.0，无更新版本）
* R 版本：DESCRIPTION 未 pin R；源码包打包于 R 4.1 时代 → **R >= 4.0（建议 4.2+）**，
  依赖随 BiocManager 自动匹配当前 Bioconductor 版本
* 依赖：`DESCRIPTION Depends` 含 ~24 个 CRAN/Bioc 包，其中 **ggalt 0.4.0 自 2021-06
  起被 CRAN 归档**（`importFrom(ggalt, geom_lollipop)`，非 ggsci 替代）——安装须从
  CRAN Archive 源码装或 conda-forge `r-ggalt`（本模块 install_deps/environment.yml
  已处理）；nf-core / snakemake-wrappers / bioconda / brew 均无官方实现（在线核实）
* 主要接口：`Load.PolyA` `Remove.IP` `Cluster.PolyA` `Annotate.PolyA` `Filter.PolyA`
  `Quantify.CanonicalAPA` `Quantify.GeneAPA` `Quantify.SplitAPA` `Quantify.CNCAPA`
  `DESeq2.PolyA` `Visualize.PolyA`（DESeq2.PolyA 以交互式 R 会话使用为主，本模块
  quant 驱动输出可表格化的 Quantify.* 度量）

## 容器与 Conda 链接

* **sourceforge 项目**：<https://sourceforge.net/projects/quantifypoly-a/>（主页 /
  文件区 / 手册 PDF / 示例数据都在此；作者 Congting Ye，厦门大学）
* **conda**：bioconda `r-quantifypolya` 不存在（soft-404）；anaconda r 频道亦无 →
  conda 只提供 R 运行时兜底（`native/environment.yml`）
* **Docker / Singularity**：无官方镜像；通用 R 运行时用 `rocker/r-ver:4.5.2`
  （官方 R 基础镜像，非 QuantifyPolyA 专用）
* **CRAN Archive ggalt**：<https://cran.r-project.org/src/contrib/Archive/ggalt/ggalt_0.4.0.tar.gz>
* 安装方式（本地）：`bash native/install.sh` 或
  `Rscript native/install_deps_QuantifyPolyA.R`（见「环境安装」）
