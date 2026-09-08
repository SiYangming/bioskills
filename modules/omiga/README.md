# omiga 软件模块

> 汇总说明：OmiGA（OmiGA/Omics Genetic Analysis，华南农业大学 SCAU-AnimalGenetics 实验室）是面向
> 组学遗传分析的 QTL 定位与全基因组关联分析套件：主程序为**单一大命令 + `--mode` 子模式**
> （cis / cis_independent / cis_interaction / cis_mt / trans / GWAS(gwas) / her_est / enrich /
> plot 等），覆盖 cis-QTL / trans-QTL / 全基因组关联 / 遗传力估计 / 富集与绘图等分析。官方**仅**
> 分发 Linux x86_64 预编译二进制（tar.xz，自带运行时），源码在 GitHub
> <https://github.com/SCAU-AnimalGenetics/OmiGA>（仅源码 + src zip，无二进制 release）；
> 引用论文 Nature Communications 2026（10.1038/s41467-026-68978-0）。
> 本模块仅实现 `native/`（run / init / update 三个技能子命令，对齐官方大命令顶层 flag）。
> 官方登记：**nf-core `modules/omiga` 404、snakemake-wrappers `bio/omiga` 404**（2026-09-08
> GitHub API 核实）→ 不建 nextflow/、snakemake/ 目录，官方渠道（bioconda → quay.io/biocontainers →
> depot.galaxyproject.org）亦无维护镜像 → `native/` 提供**自建** Dockerfile / Apptainer.def
> （debian:bookworm-slim + 官方 tar.xz 多阶段部署，linux/amd64，仅录入不实构建）。

***

## 官方登记（不建目录，仅说明 + 引用）

* **nf-core**：`modules/nf-core/omiga/` **不存在**（2026-09-08 抓取
  <https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/omiga> 返回 404）。
  Nextflow 场景请容器化（自建镜像）后走 native `run` 子命令。

* **snakemake-wrappers**：`bio/omiga` **不存在**（2026-09-08 抓取
  <https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/omiga> 返回 404）。
  Snakemake 场景请在容器内 PATH 直调 `omiga` 或走 native `run` 子命令；确需本地规则时按 td2 式
  自建 `snakemake/` 并登记 meta。

## native 实现

# omiga / native — QTL 定位套件驱动

OmiGA 1.8.17 的本地自包含实现（`source_type: custom`、`type: native`）。上游是单一大命令形态
（`omiga --mode <MODE> --threads N ...`），本驱动把官方顶层 flag 收敛为三个技能子命令：

| 子命令 | 命令 | 作用 |
| --- | --- | --- |
| `run` | `omiga --mode <MODE> --threads N [--genotype <plink前缀>] [--phenotype <file>] [--covariates <file>] [--prefix <p>] [--output-dir <dir>]` | 转发分析模式（cis 族 / trans / GWAS / her_est / enrich / plot 等）；白名单参数给出才转发 |
| `init` | `omiga --init` | 首跑前初始化（产出 OK 自检文件） |
| `update` | `omiga --update` | 联网自升级（1.8.14+ 支持；官方亦记载 `omiga update` 形态） |

* `run` 的 `--threads` **自动注入**：显式 `--threads` 优先，缺省取 meta `optimization` 默认（4）；
  对齐官方 `--mode cis --threads N` 调用形态。
* 已知 `--mode` 值：cis / cis_independent / cis_interaction / cis_mt / trans / GWAS（gwas）/
  her_est / enrich / plot **等**（以 `omiga --help` 实际清单为准；本驱动不臆造模式内专属 flag，
  `--mode` 原样放行未知值）。
* 白名单外上游参数（如其它 `--mode` 专属参数）经 `--extra-args` 原样透传追加到命令末尾。

## 用法

```bash
# CLI 直跑（等价官方命令；main.py 的 run 只构造/执行 omiga --mode …）
python main.py run --mode cis --genotype geno --phenotype pheno.txt \
    --covariates cov.txt --prefix out --output-dir res --threads 8
python main.py run --mode trans --genotype geno --phenotype pheno.txt \
    --prefix t_out --output-dir res --threads 16
python main.py init            # omiga --init（首跑前初始化）
python main.py update          # omiga --update（1.8.14+ 联网自升级）

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands

# 只打印命令不执行（调试）
python main.py run --mode cis --genotype geno --phenotype pheno.txt --dry-run
```

## 实战示例：批量 cis-QTL 定位

> 官方 Quick Start / 手册（<https://omiga.bio/Installation.md> 与官网文档）里的典型链路：
> 每个性状（phenotype 列 / 文件）跑一次 `omiga --mode cis ...`；
> 等价能力由 `native/main.py` 的 `run` 子命令提供（见上「用法」）。
> 容器内运行必须加 `-u $(id -u):$(id -g)`，否则输出文件归 root 持有。

### 1. 输入准备

```bash
# 基因型：PLINK 前缀（geno.bed / geno.bim / geno.fam 三者同名前缀）
# 表型 / 协变量：官方手册格式（FID/IID + 性状列；本模块 test/generate_data.py 生成占位示例）
mkdir -p cis_results
```

### 2. 批量 cis-QTL（bash 循环模板）

```bash
# 对多个表型文件逐一跑 cis（结果各入独立输出目录 / 前缀）
for trait in height weight milk; do
    python main.py run --mode cis \
        --genotype geno --phenotype ${trait}.txt \
        --covariates cov.txt \
        --prefix ${trait} --output-dir cis_results/${trait} \
        --threads 8
done
# 等价 CLI（不经 main.py）：
# omiga --mode cis --threads 8 --genotype geno --phenotype height.txt \
#   --covariates cov.txt --prefix height --output-dir cis_results/height
```

### 3. 参数说明（cis 官方形态；main.py run 白名单与之一致）

| 参数 | 说明 | 默认 |
| --- | --- | --- |
| `--mode <MODE>` | 分析模式（cis 族 / trans / GWAS / her_est / enrich / plot 等） | 必填 |
| `--threads <N>` | 线程数（main.py 自动注入；显式给优先） | 4 |
| `--genotype <前缀>` | 基因型 PLINK 前缀（.bed/.bim/.fam） | —（分析模式需要时必给） |
| `--phenotype <文件>` | 表型文件 | —（分析模式需要时必给） |
| `--covariates <文件>` | 协变量文件 | 无 |
| `--prefix <串>` | 输出结果前缀 | — |
| `--output-dir <目录>` | 输出目录 | — |

> 各 `--mode` 内具体 flag 以官方 `omiga --help` / 手册为准；main.py 不臆造，需用时经
> `--extra-args` 透传。

## 环境安装（官方镜像优先，不维护本地配方）

官方容器渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）均无 OmiGA（2026-09-08
核实：bioconda 页面 404 + api.anaconda.org HTTP 404 / quay.io/biocontainers/omiga 无 /
depot.galaxyproject.org singularity `omiga:1.8.17` HTTP 404；社区 quay.io/bioinfortools/omiga
仓库名存在但 **0 tags** 无可拉镜像）→ 无官方镜像可直拉，`native/` 提供**自建配方**
`Dockerfile` + `Apptainer.def`（debian:bookworm-slim，多阶段部署官方 tar.xz，**不引入
miniconda/Julia**；官方预编译包自带运行时，GPU/Julia 路线仅加速用，见官方 Installation.md）。
宿主机直跑 `main.py` 时按下面 1/4 安装 omiga 与驱动环境。

### 1. Conda / brew（包管理器安装）

OmiGA **不在 bioconda**（2026-09-08 核实 404）；homebrew 两源均无（homebrew-core `omiga.json`
HTTP 404、brewsci/bio `Formula/omiga.rb` HTTP 404，2026-09-08 核实），故**不提供 brew 块**。
conda 只能建 python 驱动环境（本体仍走官方二进制 / 容器）：

```bash
# conda 驱动 env（python=3.11 + pyyaml，供 main.py 自省/Schema；等价 native/environment.yml）
mamba create -n omiga-native -c conda-forge python=3.11 pyyaml
# omiga 本体：无 conda 包 → 见下方 §4 官方二进制（或容器镜像）
```

> 一键安装直接 `bash native/install.sh`（默认 binary 路线装官方 1.8.17 并写
> OMIGA_PATH/PATH；`--method conda` 只建驱动 env；`bash native/install.sh --help` 看参数）。

### 2. Docker（自建镜像；无官方镜像可拉）

```bash
# 自建（官方渠道无镜像 → 本地配方构建；amd64）
docker build -t omiga:1.8.17 modules/omiga/native/
# ARG 可覆盖（efile token 直链随发版失效，重建前重抓 https://omiga.bio/releases/latest.json）：
#   docker build --build-arg OMIGA_URL=<新url> --build-arg OMIGA_SHA256=<新sha256> \
#       --build-arg OMIGA_VERSION=<新版本> -t omiga:<版本> modules/omiga/native/

# 运行：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data omiga:1.8.17 \
    --mode cis --threads 8 --genotype geno --phenotype pheno.txt \
    --prefix out --output-dir res
```

> 镜像 ENTRYPOINT 为 `tini -- omiga`（缺省 CMD `--help`）；运行时直接传 omiga 顶层参数
> （`--mode …` / `--init` / `--update`），与 docker run 追加的 argv 一一对应。

### 3. Apptainer / Singularity

无 depot.galaxyproject.org 预构建 sif（官方渠道无 OmiGA），**无法 `apptainer pull` 直拉**，本地构建：

```bash
apptainer build omiga-1.8.17.sif modules/omiga/native/Apptainer.def
apptainer run -B $PWD:/data -H /data omiga-1.8.17.sif \
    --mode cis --threads 8 --genotype geno --phenotype pheno.txt \
    --prefix out --output-dir res
```

### 4. 二进制包安装（官方 release）

官方**仅**分发 Linux x86_64 预编译 tar.xz；单一数据源
<https://omiga.bio/releases/latest.json>（发版更新该文件；官网首页 Download 按钮滞后显示
v1.8.14，以 latest.json 为准）。安装手册：<https://omiga.bio/Installation.md>：

```bash
# 0) 抓取最新发布信息（filename / sha256 / url 三字段；url 为 efile111.hpccube.com 一次性 token 直链）
curl -s https://omiga.bio/releases/latest.json
#   2026-09-07 时点：release=1.8.17，filename=OmiGA-build-v1.8.17-x86_64.tar.xz，
#   sha256=6cfbed0b52085489d5a4b4b549c2343e6ae53921474087cdf28876c2c214ea23

# 1) 下载 + 校验 + 解压（官方摘要与下载文件一一核对）
mkdir -p ~/software && cd ~/software
curl -fL -O https://efile111.hpccube.com:65014/efile/s/d/YWNyZHBkcXZieQ==/08410635d771c08d
echo "6cfbed0b52085489d5a4b4b549c2343e6ae53921474087cdf28876c2c214ea23  \
  OmiGA-build-v1.8.17-x86_64.tar.xz" | sha256sum -c -
tar -Jxf OmiGA-build-v1.8.17-x86_64.tar.xz      # 解压出 OmiGA-build-v1.8.17-x86_64/
export OMIGA_PATH="$HOME/software/OmiGA-build-v1.8.17-x86_64/bin"   # OMIGA_PATH 指向 bin（官方手册）
export PATH="$OMIGA_PATH:$PATH"

# 2) 可执行 + 首跑前初始化 + 版本断言
chmod +x "$OMIGA_PATH/omiga"
omiga --init            # 首跑前初始化（产出 OK 自检文件）
omiga --version         # 断言输出含 1.8.17

# 3)（可选）写 shell profile 免每次 export；1.8.14+ 支持 omiga --update 联网自升级
```

> 💡 一键脚本走 `native/install.sh`（binary 路线内嵌官方 sha256 校验、写 OMIGA_PATH/PATH、
> `omiga --version` 断言；`--version` 覆盖非默认版本时跳过内嵌 sha 并提示从 latest.json 核对）。
> 官方只提供 `latest.json` 摘要且 token 直链一次性 → 重建镜像 / 覆盖版本前务必重抓 latest.json。

## 历史留存（旧 v1.8.10 Dockerfile 与镜像源要点）

本模块早期含两份旧式根级 `Dockerfile` / `Dockerfile_omiga`（多阶段 alpine 下载 v1.8.10 +
distroless/base-debian12 runtime），已于标准化时**删除**（v1.8.10 过旧；构建要点并入新版
`native/Dockerfile` / `Apptainer.def`，版本对齐 latest.json 的 1.8.17）。要点保留如下：

* **cn / 官方镜像源变体**：旧两份 Dockerfile 内容相同、仅 builder 基础镜像源不同（一个用
  `docker.1ms.run/ghcr.1ms.run` 国内加速、一个用官方 Docker Hub / gcr.io）。新配方只用
  `debian:bookworm-slim`（无镜像源变体需求）；国内网络拉不动 Docker Hub 时可按旧经验改用
  `docker.1ms.run/library/debian:bookworm-slim`（加速通道，仅备用）。
* **efile token 直链随版本变化**：官方历史 release 的 url 均为 `efile111.hpccube.com` 一次性
  token 直链（旧 v1.8.10 token `b3ae3da…`、1.8.17 token `08410635d771c08d`），会随发版失效/更换；
  官方历史里**仅 stable 版本提供 sha**（1.8.16 sha=3df80e…）→ 一切以
  <https://omiga.bio/releases/latest.json> 为准，重建容器 / 安装脚本前重新抓取 filename/sha256/url。
* 自建路线**不默认引入 miniconda**：官方预编译 CPU 包自带运行时；GPU/Julia v1.12+JuliaC 路线仅
  加速用（见官方 Installation.md），不进基础镜像。

## 测试

```bash
bash modules/omiga/native/test/run_test.sh   # run/init/update argv 构造断言（omiga 不在 PATH 时同样通过）
```

## 版本

* OmiGA **1.8.17**：latest.json（2026-09-07 抓取）release=1.8.17，官方 sha256
  `6cfbed0b52085489d5a4b4b549c2343e6ae53921474087cdf28876c2c214ea23`；官网首页按钮滞后显示
  v1.8.14（以 latest.json 为准）。源码仓库 GitHub SCAU-AnimalGenetics/OmiGA（仅源码 + src zip，
  无二进制 release）；Nature Communications 2026（10.1038/s41467-026-68978-0）。
* 构建路线：无官方容器 → **自建容器**（native/Dockerfile + Apptainer.def，debian:bookworm-slim，
  linux/amd64，官方 tar.xz + sha256sum 校验，仅录入不实构建）；宿主一键 `bash native/install.sh`
  （binary 默认）。
* 用法形态：单一大命令 + `--mode`（非多子命令）；`omiga --init` 首跑初始化、1.8.14+ 支持
  `omiga --update` 自升级。参数细节以官方手册 / `omiga --help` 为准。

***

## 容器与 Conda 链接

* **官方**：官网 <https://omiga.bio/>（docsify；homepage）；安装手册
  <https://omiga.bio/Installation.md>；发行单源 <https://omiga.bio/releases/latest.json>；
  GitHub 源码 <https://github.com/SCAU-AnimalGenetics/OmiGA>（仅源码，无二进制 release）；
  引用论文 Nature Communications 2026（10.1038/s41467-026-68978-0）。

* **bioconda**：无 omiga 包（<https://anaconda.org/bioconda/omiga> 404 + api.anaconda.org
  HTTP 404，2026-09-08 核实）

* **quay.io/biocontainers / depot.galaxyproject.org**：无 omiga（quay API 401 = 仓库不存在、
  depot `singularity/omiga:1.8.17` HTTP 404，2026-09-08 核实）

* **nf-core / snakemake-wrappers**：`modules/nf-core/omiga` 与 `bio/omiga` 均 404（2026-09-08）

* **社区镜像（补充登记）**：`quay.io/bioinfortools/omiga` 仓库名存在但 **0 个 tag**
  （quay API `tags: {}`，2026-09-08 核实）→ 无可拉镜像，仅登记说明

* **Homebrew**：homebrew-core `omiga.json` 404、brewsci/bio `omiga.rb` 404（2026-09-08）→
  无公式，不提供 brew 安装

* **自建容器**：`modules/omiga/native/Dockerfile`（`docker build -t omiga:1.8.17
  modules/omiga/native/`）、`modules/omiga/native/Apptainer.def`（`apptainer build
  omiga-1.8.17.sif modules/omiga/native/Apptainer.def`）
