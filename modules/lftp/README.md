# lftp 软件模块

> 汇总说明：lftp 是一款**多协议命令行文件传输客户端**（FTP/FTPS/HTTP/HTTPS/SFTP/fish/torrent 等），
> 自带任务控制（job control + readline）、书签、内建 `mirror` 镜像命令与并行传输（`-P`），支持
> 断点续传（`get -c` / `mirror -c`）与 `lftp -e "<命令串>; exit" <host>` 的非交互执行形态。
> 生信场景主要用于从 NCBI / ENA(EBI) / Ensembl 等公共库批量下载大文件（SRA / FASTQ / 参考基因组）
> 与目录镜像。本模块仅实现 `native/`（get / mirror / eval 三个技能子命令——lftp 主命令**无内置
> 子命令体系**，技能子命令收敛官方 `-e` 执行形态）。
> 官方登记：**nf-core `modules/lftp` 404、snakemake-wrappers `bio/lftp` 404**（2026-09-08 GitHub
> API 核实）→ 不建 nextflow/、snakemake/ 目录；**生物官方渠道（bioconda → quay.io/biocontainers →
> depot.galaxyproject.org）亦无 lftp**（逐条 404/无仓库证据见下）→ 本项目按**通用网络工具**处理：
> 宿主机 conda-forge / Homebrew / Debian apt / 官方源码编译；容器提供**自建** Dockerfile /
> Apptainer.def（debian:bookworm-slim + apt lftp，linux/amd64，仅录入不实构建）。

***

## 官方登记（不建目录，仅说明 + 引用）

* **nf-core**：`modules/nf-core/lftp/` **不存在**（2026-09-08 抓取
  <https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/lftp> 返回 404）。
  Nextflow 场景请用容器镜像（自建或 conda-forge）后走 native `get`/`mirror` 子命令。

* **snakemake-wrappers**：`bio/lftp` **不存在**（2026-09-08 抓取
  <https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/lftp> 返回 404）。
  Snakemake 场景请在容器内 PATH 直调 `lftp` 或走 native `get`/`mirror`/`eval` 子命令；
  确需本地规则时按 td2 式自建 `snakemake/` 并登记 meta。

## native 实现

# lftp / native — 多协议传输客户端驱动

lftp 4.9.3 的本地自包含实现（`source_type: custom`、`type: native`）。lftp 上游是
`lftp -e "<命令串>; exit" <host>` 单命令形态（无 `get`/`mirror` 子命令树），本驱动把官方
`-e` 命令串收敛为三个技能子命令：

| 子命令 | 构建出的等价命令 | 作用 |
| --- | --- | --- |
| `get` | `lftp [-P N] -e "lcd <dir>; get -c <remote_path>; exit" <host>` | 远程路径**断点续传**下载（-c；`--no-continue` 去掉 -c） |
| `mirror` | `lftp [-P N] -e "lcd <dir>; mirror -c <remote_dir>; exit" <host>` | 目录**镜像同步**（-c 续传已完成/部分文件） |
| `eval` | `lftp [-P N] -e "<command>; exit" <host>` | 自定义 lftp 命令串原样执行（未以 `exit` 结尾自动补 `; exit`） |

* 参数白名单：`host` / `remote_path`（get）/ `remote_dir`（mirror）/ `local_dir`（缺省 `.`，写入
  `lcd`）/ `command`（eval）；白名单外 lftp **全局参数**经 `--extra-args` 透传（置于 `-e` 之前，
  如 `-u user:pass`），命令串内额外 lftp 命令经 `--extra-lftp-cmds` 追加（置于 `exit` 之前）。
* 并发：lftp 的并发旋钮是**全局 `-P N`**（最大并行连接数；多文件/镜像同时传 N 个文件，单文件
  `get` 只用 1 条连接、不拆片）。`--threads` 显式给优先，缺省取 meta
  `optimization.per_subcommand_threads`（mirror 8 / get 4 / eval 1）；有效值 ≤1 时不注入 `-P`。
* 临时目录：`--tmpdir` 覆盖 `TMPDIR`（lftp 临时文件目录）。
* 命令串经 **argv 直接传递（不经 shell）**，无 shell 注入面；含空格/特殊字符的路径建议用
  `--extra-args` 的 lftp 引号语法或 `eval` 子命令自行构造。

## 用法

```bash
# CLI 直跑（get：等价官方 `lftp -e "get -c <path>; exit" <host>`）
python main.py get --host ftp-trace.ncbi.nlm.nih.gov \
    --remote-path /sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242/SRR797242.sra \
    --local-dir ~/sra --threads 4

# mirror：目录镜像（并发 8）
python main.py mirror --host ftp.sra.ebi.ac.uk \
    --remote-dir /vol1/fastq/SRR797 --local-dir ~/fastq --threads 8

# eval：自定义命令串（自动补 "; exit"）
python main.py eval --host ftp.ncbi.nlm.nih.gov \
    --command "set net:timeout 30; get -c /genomes/ref.fa.gz"

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands

# 只打印命令不执行（调试）
python main.py get --host ftp-trace.ncbi.nlm.nih.gov \
    --remote-path /sra/.../SRR797242.sra --local-dir ~/sra --dry-run
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖；`--dry-run` 只打印构建出的命令。

## 实战示例：NCBI / ENA(EBI) 公共库大文件下载

> 以下批量/单条 lftp 用法为**录入**（来自用户部署文档，2026-09 提供；历史 CentOS6 路径已废弃，
> 见「历史留存」）；等价能力由 `native/main.py` 的 `get` / `mirror` / `eval` 子命令提供
> （见上「用法」）。容器内运行必须加 `-u $(id -u):$(id -g)`，否则下载产物归 root 持有。

### 1. NCBI SRA 单文件下载（断点续传）

```bash
mkdir -p ~/sra && cd ~/sra
# 来自用户部署文档的 NCBI SRA 下载示例：
#   -e "命令; exit"：连接后执行命令串并退出；-c：断点续传（中断后重跑续传，不重下）
#   get 下载到本地当前目录（文件名与远程 basename 一致：SRR797242.sra）
lftp -e "get -c /sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242/SRR797242.sra; exit" \
    ftp-trace.ncbi.nlm.nih.gov
# 等价 main.py：python main.py get --host ftp-trace.ncbi.nlm.nih.gov \
#   --remote-path /sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242/SRR797242.sra --local-dir ~/sra
```

### 2. NCBI SRA 批量下载（bash 循环 / xargs 并行）

```bash
# 每行一条「远程路径」（同 NCBI 布局规则；SRR 目录按 6 位前缀规则推导，勿臆造不存在条目）
cat > sra_list.txt <<'EOF'
/sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242/SRR797242.sra
/sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797243/SRR797243.sra
EOF
mkdir -p ~/sra && cd ~/sra
# 顺序下载（-c 可断点续传）；大批量建议外层用 xargs -P 并行（每进程 1 条连接，勿超服务器限制）
while read -r p; do
    lftp -e "get -c ${p}; exit" ftp-trace.ncbi.nlm.nih.gov
done < sra_list.txt
```

### 3. ENA / EBI 下载（FTP 根与布局规则）

```bash
# ENA(EBI) FTP：ftp.sra.ebi.ac.uk；FASTQ 布局 vol1/fastq/<前6位>/<Accession>/<文件>
# （示例路径按 ENA 布局规则推导，未逐文件核实——请以 ENA API/portal 返回的真实路径为准）
lftp -e "get -c /vol1/fastq/SRR797/SRR797242/SRR797242_1.fastq.gz; exit" ftp.sra.ebi.ac.uk

# 目录镜像（mirror -c 续传；-P/--parallel 并行文件数）——适用于镜像整目录
lftp -e "mirror -c /vol1/fastq/SRR797; exit" ftp.sra.ebi.ac.uk
# 等价 main.py：python main.py mirror --host ftp.sra.ebi.ac.uk \
#   --remote-dir /vol1/fastq/SRR797 --local-dir ~/fastq --threads 8
```

### 4. 参数说明

| lftp 参数 | 说明 | main.py 映射 |
| --- | --- | --- |
| `-e "<命令串>; exit"` | 连接后执行命令串并退出（非交互） | get / mirror / eval 统一形态 |
| `-c`（get/mirror） | 断点续传：中断后重跑续传不重下 | 默认开；`--no-continue` 关闭 |
| `-P N`（全局） | 最大并行连接数（多文件/镜像并行） | `--threads N`（有效值 >1 时注入） |
| `lcd <dir>` | 切换本地工作目录（下载落点） | `--local-dir <dir>`（缺省 `.`） |
| `<host>` | 远端主机（命令末位） | `--host` |
| `mirror` | 目录镜像（-e 删除远端已无文件等开关经 `--extra-lftp-cmds`/`eval` 透传） | `mirror` 子命令 |
| `pget -n N -c <file>` | 单文件分片并行（官方高级特性；未在用户部署文档内，标注备选） | 经 `eval --command "pget -n 8 -c <file>"` |

> 更细参数（断点续传开关、超时、代理、`--only-newer`、`--delete` 等）以官方 man page
> <https://lftp.yar.ru/lftp-man.html> 为准；main.py 不臆造，需用时经 `--extra-args` /
> `--extra-lftp-cmds` / `eval` 透传。

## 环境安装（官方镜像优先，不维护本地配方）

生物容器渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）均无 lftp（2026-09-08
核实：bioconda 页面 404 + api.anaconda.org HTTP 404 / quay.io/biocontainers/lftp 无（API 401，
对照已知仓库 samtools 200）/ depot.galaxyproject.org singularity `lftp:4.9.3` HTTP 404；
nf-core `modules/lftp`、snakemake-wrappers `bio/lftp` 亦 404）→ lftp 是**通用网络工具**（非生物
专用），按通用渠道安装：conda-forge / Homebrew / Debian apt / 官方源码；容器走**自建配方**
`Dockerfile` + `Apptainer.def`（debian:bookworm-slim + apt lftp，**不引入 miniconda**）。
宿主机直跑 `main.py` 时按下面 1/4 安装 lftp 与驱动环境。

### 1. Conda / brew（包管理器安装）

lftp 在 **conda-forge**（bioconda 无；2026-09-08 核实 API latest=4.9.3），conda 块：

```bash
# conda-forge（等价 native/environment.yml；lftp 本体 + python/pyyaml 驱动依赖）
mamba create -n lftp-native -c conda-forge lftp=4.9.3 python=3.11 pyyaml
conda activate lftp-native
lftp --version   # 断言（LFTP | Version 4.9.3 | ...）
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
# ⚠️ 同名核对：formulae.brew.sh desc="Sophisticated file transfer program"（确为 lftp FTP 客户端，非异义软件）
brew install lftp
lftp --version   # 断言
```

> brew 当前 stable **4.9.3**（formula JSON 2026-09-08 核实），与 meta 登记 4.9.3 一致。
> 一键安装直接 `bash native/install.sh`（现代规范：有 conda/mamba 走 conda-forge 建独立环境
> `lftp-native`，无 conda 时自动下载官方源码编译到 `~/software/lftp-4.9.3` 并写 PATH；版本默认
> 4.9.3，与 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（自建镜像；无生物官方镜像可拉）

```bash
# 自建（生物官方渠道无镜像 → 本地配方构建；amd64；apt 装 bookworm 的 lftp 4.9.2 系，见文件头）
docker build -t lftp:4.9.2 modules/lftp/native/

# 运行：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则下载产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data lftp:4.9.2 \
    -e "get -c /sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242/SRR797242.sra; exit" \
    ftp-trace.ncbi.nlm.nih.gov
# 或镜像内 lftp 直接透传参数（ENTRYPOINT=/usr/bin/lftp，缺省 CMD --version）
docker run --rm lftp:4.9.2 --version
```

### 3. Apptainer / Singularity

无 depot.galaxyproject.org 预构建 sif（生物官方渠道无 lftp），**无法 `apptainer pull` 直拉**，本地构建：

```bash
apptainer build lftp-4.9.2.sif modules/lftp/native/Apptainer.def
apptainer run -B $PWD:/data -H /data lftp-4.9.2.sif \
    -e "get -c /sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242/SRR797242.sra; exit" \
    ftp-trace.ncbi.nlm.nih.gov
```

### 4. 源码安装（官方源码归档编译，无官方预编译二进制）

lftp 官方**无预编译二进制资产**（v4.9.3 GitHub release 仅 `lftp-4.9.3.tar.gz` 源码一个资产），
官网源码归档编译到**用户前缀**（无需 root，禁 `/opt/biosoft`、`/home/train`）：

```bash
# 官方 ftp 归档（首页 get.html 下载页滞后仍列 4.9.2，但 ftp 目录已有 4.9.3 —— 2026-09-08 核实）
mkdir -p ~/software && cd ~/software
curl -fLO https://lftp.yar.ru/ftp/lftp-4.9.3.tar.xz
# 官方对该归档仅发布 .md5sum + GPG .asc（sha256 未核实）——建议做 md5/签名核对：
curl -fLO https://lftp.yar.ru/ftp/lftp-4.9.3.md5sum
grep 'lftp-4.9.3.tar.xz' lftp-4.9.3.md5sum | md5sum -c -
# （GitHub release 同源码备选：curl -fLO
#   https://github.com/lavv17/lftp/releases/download/v4.9.3/lftp-4.9.3.tar.gz
#   sha256=68116cc184ab660a78a4cef323491e89909e5643b59c7b5f0a14f7c2b20e0a29（homebrew-core 校验值））

tar -Jxf lftp-4.9.3.tar.xz
cd lftp-4.9.3
./configure --prefix=$HOME/software/lftp-4.9.3 && make -j4 && make install
echo 'export PATH=$HOME/software/lftp-4.9.3/bin:$PATH' >> ~/.bashrc && source ~/.bashrc

lftp --version   # 断言含 4.9.3
```

> 编译依赖：Debian/Ubuntu 需 `build-essential libssl-dev libidn2-dev libreadline-dev zlib1g-dev`；
> macOS 需 Xcode CLT（可 `brew install openssl libidn2 readline`，必要时按 configure 报错设置
> CPPFLAGS/LDFLAGS）。一键走 `native/install.sh --method binary`（Linux 自动用官方 .md5sum 校验、
> macOS 用 GitHub 归档 + 内嵌 sha256；`--version` 覆盖非默认版本时跳过内嵌校验并提示）。

## 历史留存（用户部署文档要点）

用户部署文档记载的 lftp 安装/用法要点（录入用；**历史 CentOS6 路径已废弃不用**）：

* **包管理器**：`dnf install lftp` / `yum install lftp`（RHEL 系；Debian/Ubuntu 对应
  `apt-get install lftp`，bookworm 为 4.9.2-2）；conda-forge 亦可（`conda install -c conda-forge lftp`）。
* **NCBI SRA 下载**：`lftp -e "get -c <远程 .sra 路径>; exit" ftp-trace.ncbi.nlm.nih.gov`
  —— `-c` 断点续传、`-e` 执行命令后退出（本模块 README「实战示例 §1」原样收录）。
* **旧 CentOS6 方案要点（已废弃）**：历史部署曾在 CentOS6 上用自带/旧版 lftp 直连
  `ftp-trace.ncbi.nlm.nih.gov` 拉取 SRA；该类旧系统 TLS/证书栈过旧，现 NCBI 已强制要求较新
  TLS，旧路径不再可用 → 一律改走本模块「环境安装」1/4（conda-forge / 官方源码 / 容器）。
* 大文件下载断点续传 + 服务端限流经验：`-c` 配合重跑即续传；大批量下载控制并发（`-P`），
  避免对 NCBI/EBI 公共服务器造成压力（源自部署文档要点）。

## 测试

```bash
bash modules/lftp/native/test/run_test.sh   # get/mirror/eval argv 构造断言（lftp 不在 PATH 时同样通过）
```

## 版本

* lftp **4.9.3**（2024-11-08 上游发布，lftp.yar.ru 首页 events；GitHub release tag v4.9.3）。
* 版本多来源差（meta `software_versions.native` 各注明）：conda-forge latest=4.9.3、brew
  stable=4.9.3、上游源码归档 4.9.3；Debian bookworm apt = **4.9.2-2**（自建 Dockerfile/Apptainer.def
  走 bookworm 4.9.2 系，与 4.9.3 有 minor 差异）、Debian stable(trixie)=4.9.2-3、testing/unstable=
  4.9.3-3（2026-09 用户核实）。
* 官网下载页 <https://lftp.yar.ru/get.html> 仍列 4.9.2（页面滞后），以首页 events / ftp 归档目录
  （`lftp-4.9.3.tar.xz`，2026-09-08 核实存在）为准。
* license：GPLv3（上游 COPYING 为 GPL v3 全文；brew/conda-forge SPDX 均记 **GPL-3.0-or-later**）。

***

## 容器与 Conda 链接

* **官方（上游）**：官网 <https://lftp.yar.ru/>（homepage；man page
  <https://lftp.yar.ru/lftp-man.html>）；下载页 <https://lftp.yar.ru/get.html>（滞后列 4.9.2）；
  ftp 归档 <https://lftp.yar.ru/ftp/>（含 lftp-4.9.3.tar.xz / .md5sum / .asc）；
  GitHub 源码与 release <https://github.com/lavv17/lftp>（v4.9.3 资产 lftp-4.9.3.tar.gz）。

* **conda-forge（有包，宿主机首选）**：<https://anaconda.org/conda-forge/lftp>（latest 4.9.3，
  2026-09-08 API 核实；覆盖 linux-64/aarch64/ppc64le、macos-64/arm64）

* **bioconda**：无 lftp 包（<https://anaconda.org/bioconda/lftp> 404 + api.anaconda.org/package/
  bioconda/lftp HTTP 404，2026-09-08 核实）

* **quay.io/biocontainers / depot.galaxyproject.org**：无 lftp（quay API 401 = 仓库不存在、对照
  biocontainers/samtools 200；depot `singularity/lftp:4.9.3` HTTP 404，2026-09-08 核实）

* **nf-core / snakemake-wrappers**：`modules/nf-core/lftp` 与 `bio/lftp` 均 404（2026-09-08）

* **Homebrew**：homebrew-core 有公式（<https://formulae.brew.sh/api/formula/lftp.json>，stable 4.9.3，
  desc="Sophisticated file transfer program" 同名核对通过；`brew install lftp`，无需 tap）

* **自建容器**：`modules/lftp/native/Dockerfile`（`docker build -t lftp:4.9.2
  modules/lftp/native/`）、`modules/lftp/native/Apptainer.def`（`apptainer build lftp-4.9.2.sif
  modules/lftp/native/Apptainer.def`）；bookworm apt lftp=4.9.2-2（linux/amd64）
