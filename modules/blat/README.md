# blat 软件模块（UCSC BLAT — 快速序列相似性比对）

> BLAT（BLAST-Like Alignment Tool，UCSC Kent 工具族；Kent WJ, *Genome Res*
> 2002;12:656-64）把查询序列切 k-mer 索引后在目标中找种子并延伸，比对速度远快于
> BLAST（敏感度略低）。经典用途：mRNA/EST 定位基因组、跨物种相似搜索、UCSC
> Browser 批处理比对。**非 deprecated（2026-09 登记）**：UCSC 至今在 hgdownload
> 持续分发独立 blat 二进制（linux.x86_64 直链 2026-09-09 GET **200**）。

***

## native 实现（真实命令构造 + 执行，`source_type: custom` / `type: native`）

本实现为「真实命令构造 + 执行」：`native/main.py` 按 UCSC usage 构造并运行 blat
（本地已装 blat 时真实产出 PSL/PSLX）。单子命令：

| 子命令 | 实际构造命令 | 作用 |
| ---- | ---- | ---- |
| `blat` | `blat -t=<type> -q=<type> -out=<fmt> [-tileSize=N] [-minScore=N] [-fastMap/-fine] <database> <query> <output>` | 目标 vs 查询 → PSL/PSLX 等比对输出 |

```bash
# CLI 直跑（需本机已装 blat，见「环境安装」）
python main.py blat ref.fa reads.fa out.psl
python main.py blat ref.2bit mrna.fa out.pslx -t dnax -q rnax --out-format pslx

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

> blat 为**单线程**程序：`--threads` 仅占位接受、不注入命令行（`-fastMap` 可加速、
> `-fine` 更准但慢）。

***

## 实战示例：mRNA → 基因组 PSL 定位（等价能力 = `native/main.py blat`）

UCSC 手册经典流程（`-t=dnax` 目标为基因组 DNA、`-q=rnax` 查询为 mRNA/EST）：
历史教程多把 UCSC 二进制解到 `/opt/biosoft/` 或直接 `wget` 到工作目录；此处统一
**用户前缀** `~/software`（免 root；原始路径见「历史留存」）：

```bash
# 0) 准备：下载官方独立二进制到用户前缀（linux x86_64 示例）
mkdir -p ~/software/ucsc-blat && cd ~/software/ucsc-blat
curl -fL -o blat https://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64/blat/blat
chmod +x blat && export PATH="$HOME/software/ucsc-blat:$PATH"

# 1) DNA vs DNA（如 EST/转录本对基因组；dnax/rnax 自动剪接）
blat -t=dnax -q=rnax genome.fa mrna.fa mrna.psl
# 2) 蛋白比对（-t=protein -q=protein）
blat -t=protein -q=protein proteins.fa query.fa prot.psl
# 3) 输出 PSLX（含序列）或调参（-tileSize 种子长 / -minScore 得分阈值）
blat -t=dnax -q=rnax -out=pslx -tileSize=11 -minScore=30 genome.fa mrna.fa mrna.pslx
```

> PSL 列含义与下游过滤（pslCDnaFilter 等）见 UCSC FAQ；`-noHead` 去掉 PSL 头部，
> `-fine` 提高精化。

### 参数说明（录入；2026-09 对照 UCSC blat usage）

| 参数 | 说明 |
| ---- | ---- |
| `<database>` | 目标（参考）：FASTA/.nib/.2bit；本驱动面向本地文件 |
| `<query>` | 查询序列文件（FASTA/FASTQ/.nib/.2bit） |
| `<output>` | 输出文件（PSL/PSLX…） |
| `-t=<type>` | 目标类型 dna/protein/dnax/rnax（默认 dna） |
| `-q=<type>` | 查询类型 dna/protein/dnax/rnax（默认 dna） |
| `-out=<fmt>` | psl/pslx/axt/maf/sim4/wublast/blast/sam（默认 psl） |
| `-tileSize=N` | 种子长度（dna 默认 11） |
| `-stepSize=N` | 种子步长（默认 =tileSize） |
| `-minScore=N` | 最小比对得分（默认 30） |
| `-minIdentity=N` | 最小一致率 %（默认 90） |
| `-fastMap` / `-fine` | 快速近似 / 高精度模式（互斥方向） |
| `-noHead` | 不打印 PSL 头部 |

## 测试

```bash
bash test/run_test.sh   # argv 构造 + parser + schema 自省恒跑；stub 假二进制 CLI 冒烟
```

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（UCSC hgdownload 官方二进制 + bioconda `blat=36` / `ucsc-blat` →
quay.io/biocontainers / depot.galaxyproject.org，2026-09-09 核实），直接拉取官方
渠道运行工具本体；本地不维护 Dockerfile/Apptainer.def。

### 1. Conda / brew（包管理器安装）

```bash
# conda：bioconda blat=36（独立 BLAT；与 hgdownload 二进制同源）
mamba create -n blat-native -c conda-forge -c bioconda blat=36
conda activate blat-native
blat 2>&1 | head -2 || true            # 断言：打印 usage（无 --version）
# 另：kent 系工具族用 ucsc-blat（nf-core/blat 官方模块 pin 472）
```

> Homebrew：homebrew-core（formulae.brew.sh/api/formula/blat.json）与 brewsci/bio
> （Formula/blat.rb）均 404（2026-09-09 核实），无公式 → 不登记 brew 安装块。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/blat:36--0
# 运行工具本体（注意 -u $(id -u):$(id -g)，否则产物归 root；tag 以 quay 在线目录为准）
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/blat:36--0 \
    blat /data/genome.fa /data/mrna.fa /data/mrna.psl
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 预构建 sif（与 quay tag 互通）：

```bash
apptainer pull blat.sif docker://depot.galaxyproject.org/singularity/blat:36--0
apptainer run -B $PWD:/data -H /data blat.sif \
    blat /data/genome.fa /data/mrna.fa /data/mrna.psl
```

### 4. 二进制包安装（官方 release）

UCSC hgdownload 直接分发独立二进制（2026-09-09 GET 200），无需编译：

```bash
# linux x86_64
curl -fL -o ~/software/ucsc-blat/blat \
    https://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64/blat/blat
chmod +x ~/software/ucsc-blat/blat
export PATH="$HOME/software/ucsc-blat:$PATH"
# macos x86_64 / 其他平台：换 admin/exe/macosx.x86_64/... 同路径（arm64 需自行编译 kent 源码）
```

**源码编译（备选；kent 源码 blatSrc，历史教学方案；官方以分发二进制为主）**：

> 源码包源（官方 kent src，**可下载**）：`https://hgwdev.gi.ucsc.edu/~kent/src/blatSrc37.zip`
> （2026-09 用户实测可下载；个别网络/直连工具可能失败——如遇连接超时可用
> 浏览器下载或换网络后重试）；历史教学亦见旧版 blatSrc36.zip。

```bash
# 官方 blatSrc37.zip（可下载，见上注）；解压后设 MACHTYP 再 make（产物输出到 ~/bin/x86_64）
wget https://hgwdev.gi.ucsc.edu/~kent/src/blatSrc37.zip -P ~/software/
unzip ~/software/blatSrc37.zip -d ~/software/
cd ~/software/blatSrc
export MACHTYP=x86_64
mkdir -p ~/bin/x86_64
make -j 4
mkdir -p ~/software/blat && mv ~/bin/x86_64 ~/software/blat/bin
export PATH="$HOME/software/blat/bin:$PATH"
```

> 历史教学常用绝对路径（解压 `-d /opt/biosoft/`、`mv ~/bin/x86_64 /opt/biosoft/blat/bin`）归档时统一改为用户级 `~/software` 前缀（见 AGENT §7）。BLAT 定位：适合快速定位序列在基因组上的位置（验证 PCR 产物、定位 EST 等），**不适合大批量短读长测序数据比对**（该场景用 BWA / Bowtie2）。

## 替代建议（使用定位）

| 工具 | 定位 | 说明 |
| ---- | ---- | ---- |
| **BLAT**（本模块） | 快速相似搜索 / mRNA-EST 定位 / 跨物种搜索 | 快但敏感度低于 BLAST；单线程；适合大库粗筛 |
| **minimap2** | 通用长/短读比对（本仓库另见 `minimap2` 模块） | 现代流程比对首选（基因组比对/重叠群/RNA） |
| **BLAST / Diamond** | 高敏感相似性搜索 | BLAST+ 官方；Diamond 为蛋白快速版 |
| **BWA-MEM** | 短读比对 | NGS reads 比对首选（本仓库另见 `bwa` 模块） |

## 版本

* **v36**（经典独立 BLAT release；UCSC hgdownload 现分发二进制，2026-09-09
  `admin/exe/linux.x86_64/blat/blat` GET 200）
* bioconda：**blat=36**（独立包）与 **ucsc-blat=482**（kent 系最新，2026-09-09
  api.anaconda.org 核实 latest=482；nf-core/blat 官方模块 pin **472**）
* License：**Free for academic, nonprofit and personal use**（UCSC；商用需许可）
* 引用：Kent WJ. BLAT—the BLAST-like alignment tool. *Genome Res*
  2002;12(4):656-64. doi:10.1101/gr.229202
* nf-core：**有** `modules/nf-core/blat` 官方 module（environment.yml pin
  bioconda::ucsc-blat=472，单模块无子目录，2026-09-09 核实）；snakemake-wrappers
  `bio/blat` **404**

## 历史留存

* 历史教程常把 UCSC 二进制 `wget` 到 **`/opt/biosoft/`** 或直接在项目目录运行
  （如 `wget https://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64/blat/blat`）；
  本 README 统一改写为**用户前缀** `~/software/ucsc-blat`（免 root）。
* 服务器版：UCSC 另提供 **gfServer/gfClient**（blat 服务器/客户端，同目录分发），
  支持远程 2bit 库与多查询并发；本模块只包装单机 blat，需要 gfServer 时请直接
  调用同套件二进制（见「容器与 Conda 链接」）。
* PSL 后处理工具（pslCDnaFilter、pslMap、pslPosTarget 等）在 UCSC 同套件
  `admin/exe/.../` 目录，本模块不逐一包装。

## 容器与 Conda 链接

* **UCSC FAQ（BLAT 说明）**：<https://genome.ucsc.edu/FAQ/FAQblat.html>
* **官方二进制目录**：<https://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64/blat/>
  （含 blat 与 gfServer/gfClient；macosx.x86_64 等平台同结构）
* **conda**：bioconda `blat=36` → <https://anaconda.org/bioconda/blat>；
  `ucsc-blat` → <https://anaconda.org/bioconda/ucsc-blat>
* **nf-core 官方模块**：<https://github.com/nf-core/modules/tree/master/modules/nf-core/blat>
* **Docker / Singularity**：`quay.io/biocontainers/blat:36--0`（tag 以在线目录为准）/
  depot.galaxyproject.org 同名 sif
* **brew**：无公式（homebrew-core 与 brewsci/bio 均 404 核实）
* **引用论文**：<https://genome.cshlp.org/content/12/4/656.full>
