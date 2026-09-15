# edena 软件模块（Edena — String Graph 基因组组装器）

> # ⚠️ DEPRECATED — 已淘汰，仅历史参考登记
>
> **Edena（Edena V3.131028）** 是基于 **String Graph（字符串图）** 算法的基因组组装
> 工具，面向中等读长数据（一代/二代混用场景；Hernandez et al. 2008）。核心命令
> `edena`：`-nThreads` 指定线程、`-DRpairs` 处理 paired-end 数据、`-e`/`-overlapCutoff`
> 导出重叠信息并按阈值重跑。
> 上游在 **V3.131028**（版本号内置日期 13-10-28，约 2013-10）之后**长期停更**；
> 官网 <http://www.genomic.ch/edena.php> 2026-09-11 探测 **HTTP 200 但页面内容为
> PHP Fatal error**（站点功能性损坏）；官方源码直链
> `http://www.genomic.ch/edena/EdenaV3.131028.tar.gz` 实测仍可下载（HTTP 200）。
>
> **新项目请勿使用**——基因组组装已被 **SPAdes / Velvet / Canu** 等现代工具替代。
> 本模块只做「录入」：方法/命令/链接准确登记、不产出自建容器配方
> （Dockerfile/Apptainer.def），仅供复现 2013 时代的 Edena 分析。

***

## native 实现（说明型 / 命令构造，`source_type: custom` / `type: native`）

本实现为「说明型 + 命令构造」：`native/main.py` 按官方用法构造 Edena 命令行并打印，
**不实际执行**（软件 deprecated、官网损坏、无新用场景）。两个子命令：

| 子命令 | 实际构造命令 | 作用 |
| ---- | ---- | ---- |
| `assemble` | `edena -nThreads <N> -DRpairs <r1> <r2> [-p <prefix>]`（PE）<br>`edena -nThreads <N> <reads1> [-p <prefix>]`（SE） | reads → contigs（String Graph 组装） |
| `overlap` | `edena -e <out.ovl> -overlapCutoff <N> -p <out_N>` | 导出重叠信息 / 按阈值重跑 |

```bash
# CLI 直跑（构造历史命令，仅供复现；先装 edena，见「环境安装」）
python main.py assemble --reads1 fragment.1.fastq --reads2 fragment.2.fastq --threads 4
python main.py overlap --overlap-out out.ovl --overlap-cutoff 70 --prefix out_70

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads`（透传 `-nThreads`）与 `--tmpdir`。
构造命令通过 stderr 打印 deprecated 提示，stdout 只输出命令本身。

***

### 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `-nThreads <N>` | 线程数（文档示例 4） |
| `-DRpairs <r1> <r2>` | 处理 paired-end 数据（文档 PE 用法） |
| `-e <out.ovl>` | 导出重叠信息文件（供 `-overlapCutoff` 重跑） |
| `-overlapCutoff <N>` | 重叠阈值（文档示例 50–90，步长 10，逐个尝试后选最优） |
| `-p <prefix>` | 输出前缀（产物 `<prefix>_contigs.fasta`） |

## 测试

```bash
bash test/run_test.sh   # argv 构造 + parser + schema 自省为常驻断言（不下载/不编译）；
                        # stub 假二进制 CLI 冒烟恒跑
```

## 环境安装（官方镜像优先，不维护本地配方）

> 官方现状（2026-09-11 在线核实，如实记录）：**上游停更**，官网页面功能性损坏，
> 但官方源码直链仍可下载；bioconda 存在 **edena=3.131028** 历史包（linux-64 + osx-64）
> → quay.io/biocontainers 与 depot.galaxyproject.org 有自动构建镜像；
> 但多年未随上游维护 → 判定「官方渠道存在但属历史遗留，不建议新项目依赖」；软件
> deprecated → **不维护本地 Dockerfile/Apptainer.def 配方**。

### 1. Conda / brew（包管理器安装）

```bash
# conda：bioconda 历史包 edena=3.131028（linux-64/osx-64）
mamba create -n edena-native -c conda-forge -c bioconda edena=3.131028
conda activate edena-native
edena 2>&1 | head -2   # 断言：命令可达（3.131028 无统一 --version）
```

> Homebrew：formulae.brew.sh/api/formula/edena.json 返回 404（2026-09-11 核实），
> 无公式 → 不登记 brew 安装块。

### 2. Docker（官方镜像）

无「当前维护」官方镜像；仅历史镜像可作复现（bioconda 3.131028 老包自动构建）：

```bash
docker pull quay.io/biocontainers/edena:3.131028--h9948957_8
# 运行工具本体（产物归当前用户，避免 root 持有）
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/edena:3.131028--h9948957_8 \
    edena -nThreads 4 -DRpairs /data/fragment.1.fastq /data/fragment.2.fastq
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 预构建 sif（2026-09-11 核实存在，与 quay tag 互通）：

```bash
apptainer pull edena.sif docker://depot.galaxyproject.org/singularity/edena:3.131028--h9948957_8
apptainer run -B $PWD:/data -H /data edena.sif \
    edena -nThreads 4 -DRpairs /data/fragment.1.fastq /data/fragment.2.fastq
```

### 4. 二进制包安装（官方 release / 源码编译）

官方源码归档 `EdenaV3.131028.tar.gz` 仍可下载（2026-09-11 实测 200，497784 字节）：

```bash
# 历史教程原为 /opt/biosoft/EdenaV3.131028（root 全局限定路径）；
# 本 README 一律改写为用户前缀 ~/software/EdenaV3.131028（免 root）
mkdir -p ~/software && cd ~/software
curl -fL -o EdenaV3.131028.tar.gz \
    http://www.genomic.ch/edena/EdenaV3.131028.tar.gz
tar zxf EdenaV3.131028.tar.gz -C ~/software/
cd ~/software/EdenaV3.131028
make -j 4
cp src/edena bin/
export PATH="$HOME/software/EdenaV3.131028/bin:$PATH"
```

> ⚠️ 2013 时代源码对现代编译器/glibc 的兼容性**未核实**；优先推荐 bioconda
> edena=3.131028 路线。

## 替代建议（新项目请直接使用）

| 替代工具 | 说明 | 官方入口 |
| ---- | ---- | ---- |
| **SPAdes** | 多 k-mer de Bruijn 组装器，短读/混合数据主流选择 | <https://github.com/ablab/spades>（bioconda `spades`） |
| **Velvet** | 经典 de Bruijn 组装器（Edena 同代） | <https://github.com/dzerbino/velvet>（bioconda `velvet`） |
| **Canu** | 三代长读组装器（本仓库另见 `canu`/`flye` 类模块） | <https://github.com/marbl/canu>（bioconda `canu`） |

## 版本

* **3.131028**（EdenaV3.131028，Edena 系列最终发布；版本号内置日期 13-10-28，
  2026-09-11 在线核实官网页面损坏、官方源码直链仍可下载）
* bioconda 版本号 **3.131028**（linux-64 + osx-64；2026-09-11 api.anaconda.org
  核实，包元数据未声明 license）
* License：官网页面损坏无法在线复核；历史惯例为学术免费、商用需授权（未证实）
* 引用：Hernandez D, François P, Farinelli L, Osterås M, Schrenzel J. De novo
  bacterial genome sequencing: millions of very short reads assembled on a
  desktop computer. *Genome Research* 2008;18(5):802-9.
* nf-core / snakemake-wrappers：无官方子模块（2026-09-11 核实
  `modules/nf-core/edena`、`bio/edena` 均 404）→ 不登记官方说明层

## 历史留存

* 历史教程常见安装前缀为 **`/opt/biosoft/EdenaV3.131028`**（root 全局限定路径）；
  本 README 一律改写为**用户前缀** `~/software/EdenaV3.131028`（免 root）。
  原始发布包名：`EdenaV3.131028.tar.gz`（官网 genomic.ch `edena/` 目录）。
* 历史流程中 Edena 的 `out_contigs.fasta` 常作为下游 scaffolding 工具（如 SOPRA）
  的 contigs 输入；现代流程统一建议 SPAdes/Canu 产出 contigs 后走 BWA-MEM +
  samtools + 现代 scaffolder。

## 容器与 Conda 链接

* **官网（页面损坏）**：<http://www.genomic.ch/edena.php>
* **官方源码直链**（历史归档，200）：<http://www.genomic.ch/edena/EdenaV3.131028.tar.gz>
* **社区归档**：https://github.com/SiYangming/edena
* **conda**：bioconda `edena=3.131028`（历史包）→ <https://anaconda.org/bioconda/edena>
* **Docker / Singularity**：`quay.io/biocontainers/edena:3.131028--h9948957_8`（历史镜像）/
  depot.galaxyproject.org 同名 sif
* **brew**：无公式（homebrew-core 404 核实）
