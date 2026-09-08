# aspera-connect 软件模块

> 汇总说明：IBM Aspera Connect（安装包名 **ibm-aspera-connect**，命令行工具名 **ascp**）是基于 FASP
> 协议的高速文件传输客户端，用于从 NCBI SRA / EBI ENA 等大型公共数据库高速下载（显著快于 FTP/HTTP）。
> ⚠️ **Aspera 为 IBM 专有软件（非开源）**：本模块只做「录入」——方法/命令/链接/配方（仅 amd64）
> 准确即可，**禁止真实下载/构建/安装/运行**；容器配方仅供个人/机构内部使用，使用前须阅读并遵守
> IBM 官方 EULA，不得随意再分发。
> 本模块仅实现 `native/`（ascp / version 两个技能子命令）。官方登记：**nf-core `modules/ascp` /
> `modules/aspera-connect` 404、snakemake-wrappers `bio/ascp` 404**（2026-09-08 GitHub API 核实）→
> 不建 nextflow/、snakemake/ 目录；官方容器渠道（bioconda → conda-forge → quay.io/biocontainers →
> depot.galaxyproject.org）亦全无 → `native/` 提供**自建** Dockerfile / Apptainer.def
> （debian:bookworm-slim + 官方 Connect 自解压安装器，linux/amd64，仅录入不实构建）。

***

## 官方登记（不建目录，仅说明 + 引用）

* **nf-core**：`modules/nf-core/ascp` 与 `modules/nf-core/aspera-connect` **均不存在**（2026-09-08
  抓取 <https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/ascp> 返回 404）。
  Nextflow 场景请容器化（自建镜像）后走 native `ascp` 子命令，或宿主 ascp。

* **snakemake-wrappers**：`bio/ascp` 与 `bio/aspera-connect` **均不存在**（2026-09-08 抓取
  <https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/ascp> 返回 404）。
  Snakemake 场景请在容器内 PATH 直调 `ascp` 或走 native `ascp` 子命令；确需本地规则时按 td2 式
  自建 `snakemake/` 并登记 meta。

## native 实现

# aspera-connect / native — FASP 高速下载驱动

IBM Aspera Connect 4.2.19.956（官方安装包自报版本号；`ascp` 为随包单一命令行工具，无原生子命令
体系）的本地自包含实现（`source_type: custom`、`type: native`）。本驱动把「公共数据高速下载」场景
收敛为两个技能子命令：

| 子命令 | 命令 | 作用 |
| --- | --- | --- |
| `ascp` | `ascp -T -l <rate> -i <key> [--host=H] [--user=U] [-P <port>] --mode=recv <source> <dest>` | FASP 高速下载（默认参数对齐 NCBI SRA 官方免密共享形态） |
| `version` | `ascp --version` | 冒烟 / 版本自报 |

* `ascp` 默认参数（用户实装验证形态，2026-09-08 录入）：`-T`（关加密提速度）、`-l 200M`（限速）、
  `-i ~/.aspera/connect/etc/asperaweb_id_dsa.openssh`（默认密钥）、`--host=ftp-private.ncbi.nlm.nih.gov`、
  `--user=anonftp`、`--mode=recv`；NCBI 默认形态不传 `-P`。ENA 下载用 `--host fasp.sra.ebi.ac.uk
  --user era-fasp --port 33001` 覆盖（官方示例速率常用 `300m`）。
* **`--threads` / `--tmpdir` 仅接受不注入**：ascp 是带宽型 I/O 单进程工具，无线程参数、无 tmpdir
  参数（TMPDIR 由 meta `optimization.env_vars` 声明）——技能层保留这两个选项仅为接口统一。
* 密钥提示：公共数据源密钥 `asperaweb_id_dsa.openssh` 默认位于 Connect 安装目录 `etc/`；社区报告
  Connect 4.2+ 或不再随包提供（未核实 IBM 官方说明）→ 缺失时经 `--key` 显式指定其它密钥/路径。

## 用法

```bash
# CLI 直跑（等价官方命令；main.py 的 ascp 只构造/执行 ascp --mode=recv …）
python main.py ascp /sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242 ./
python main.py ascp /sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242 ./ \
    --rate 300M --key ~/.aspera/connect/etc/asperaweb_id_dsa.openssh
python main.py version            # ascp --version

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
python main.py ascp <远端路径> . --dry-run   # 只打印构建出的命令，不执行
```

## 实战示例：NCBI SRA / EBI ENA 高速下载

> 公共数据库官方推荐的 FASP 高速下载形态（NCBI SRA、ENA 文档）；等价能力由 `native/main.py` 的
> `ascp` 子命令提供（见上「用法」）。容器内运行必须加 `-u $(id -u):$(id -g)`，否则产物归 root。

### 1. NCBI SRA（用户实装验证的完整命令，原样录入）

```bash
# 前置：ascp 已安装（官方 Connect 安装包 → ~/.aspera/connect/bin/ascp；安装见「环境安装」）
export PATH="$HOME/.aspera/connect/bin:$PATH"

# 下载单个 SRA run（SRR797242）到当前目录（.sra 格式）
ascp -T -l 200M -i ~/.aspera/connect/etc/asperaweb_id_dsa.openssh \
    --host=ftp-private.ncbi.nlm.nih.gov --user=anonftp --mode=recv \
    /sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242 ./

# 等价技能驱动
python modules/aspera-connect/native/main.py ascp \
    /sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242 ./
```

### 2. EBI ENA（host/user/port 覆盖形态，ENA 官方示例）

```bash
# ENA 下载（fastq.gz 示例；密钥同上，ERA 公共共享密钥）
ascp -T -l 300m -P 33001 -i ~/.aspera/connect/etc/asperaweb_id_dsa.openssh \
    era-fasp@fasp.sra.ebi.ac.uk:vol1/fastq/ERR164/ERR164407/ERR164407.fastq.gz ./
# 或等价 --host/--user/--mode=recv 形态：
ascp -T -l 300m -i <密钥> --host=fasp.sra.ebi.ac.uk --user=era-fasp \
    -P 33001 --mode=recv vol1/fastq/ERR164/ERR164407/ERR164407.fastq.gz ./
```

### 3. 参数说明

| 参数 | 说明 | 默认 |
| --- | --- | --- |
| `-T` | 关闭传输加密（提速度；公共数据非敏感时用） | 固定注入 |
| `-l <rate>` | 限速（200M/300m 等速率串，原样透传） | `200M` |
| `-i <key>` | 认证密钥（NCBI/EBI 公共共享密钥 `asperaweb_id_dsa.openssh`） | `~/.aspera/connect/etc/asperaweb_id_dsa.openssh` |
| `--host` | FASP 主机 | `ftp-private.ncbi.nlm.nih.gov`（ENA 用 `fasp.sra.ebi.ac.uk`） |
| `--user` | 远端用户 | `anonftp`（ENA 用 `era-fasp`） |
| `-P <port>` | 远端端口 | 不传（ENA 需 `33001`） |
| `--mode=recv` | 接收（下载）模式 | 固定注入 |
| `<source>` | 远端源路径 | 必填 |
| `<dest>` | 本地目标目录/文件 | `.` |
| `--threads` / `--tmpdir` | 技能层选项（ascp 无对应参数 → 仅接受不注入） | — |

> 其余 ascp 参数（断点续传 `-k 1`、`--overwrite=diff`、`-L` 日志等）经 `--extra-args` 原样透传；
> 具体以 `ascp --help` / IBM 文档为准，本模块不臆造。

## 环境安装（无官方镜像，自建容器配方 + 官方安装包）

官方容器渠道（bioconda → conda-forge → quay.io/biocontainers → depot.galaxyproject.org）均无
Aspera Connect（2026-09-08 逐条核实：api.anaconda.org 的 bioconda/conda-forge 下
aspera-connect/aspera/ascp 全 404；quay.io/biocontainers/aspera-connect 不存在；depot
`singularity/aspera-connect:4.2.19.956` HTTP 404）→ 无官方镜像可直拉，`native/` 提供**自建配方**
`Dockerfile` + `Apptainer.def`（debian:bookworm-slim，官方 Connect tar.gz 自解压 .sh 部署，
**不引入 miniconda**）。宿主机直跑 `main.py` 时按下面 1/4 安装 ascp 与驱动环境。
⚠️ 官方下载页未公布安装包 sha256（2026-09-08 核实）→ 以下均不内嵌伪造校验和。

### 1. Conda / brew（包管理器安装）

aspera-connect / aspera / ascp **不在 bioconda，也不在 conda-forge**（2026-09-08 核实，api 全 404）；
homebrew 两源均无（homebrew-core `aspera-connect.json`/`aspera.json` HTTP 404、brewsci/bio
`aspera-connect.rb`/`aspera.rb` HTTP 404，2026-09-08 核实）→ **无 conda/brew 包可装，不提供对应安装块**。
conda 只能建 python 驱动环境（ascp 本体仍走官方安装包 / 容器）：

```bash
# conda 驱动 env（python=3.11 + pyyaml，供 main.py 自省/Schema；等价 native/environment.yml）
mamba create -n aspera-connect-native -c conda-forge python=3.11 pyyaml
# ascp 本体：无 conda 包 → 见下方 §4 官方安装包（或容器镜像）
```

> 一键安装直接 `bash native/install.sh`（默认 binary 路线装官方 4.2.19.956 到
> `${HOME}/.aspera/connect` 并写 PATH；`--method conda` 只建驱动 env；`bash native/install.sh --help`
> 看参数）。注意：IBM 官方手册**勿以 root 运行** Connect 安装器，请用普通用户执行。

### 2. Docker（自建镜像；无官方镜像可拉）

```bash
# 自建（官方渠道无镜像 → 本地配方构建；amd64；latest 指针更新后用 ARG 覆盖 URL）
docker build -t aspera-connect:4.2.19.956 modules/aspera-connect/native/
#   docker build --build-arg ASCP_URL=<官方页面最新直链> -t aspera-connect:<版本> \
#       modules/aspera-connect/native/

# 运行：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
#   密钥：镜像内默认位于 /opt/aspera/.aspera/connect/etc/（4.2+ 随包若有 asperaweb_id_dsa.openssh）；
#   若缺失 → 把宿主密钥挂载进容器后 -i 指向挂载路径
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    -v $HOME/.aspera/connect/etc/asperaweb_id_dsa.openssh:/key/asperaweb_id_dsa.openssh \
    aspera-connect:4.2.19.956 \
    ascp -T -l 200M -i /key/asperaweb_id_dsa.openssh \
    --host=ftp-private.ncbi.nlm.nih.gov --user=anonftp --mode=recv \
    /sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242 .
```

> 镜像 ENTRYPOINT 为 `ascp`（缺省 CMD `--help`）；容器内 ENV `HOME=/opt/aspera`，使技能驱动默认密钥
> 路径（`~/.aspera/connect/etc/...`）与安装位置一致。

### 3. Apptainer / Singularity

无 depot.galaxyproject.org 预构建 sif（官方渠道无 Aspera Connect），**无法 `apptainer pull` 直拉**，
本地构建：

```bash
apptainer build aspera-connect-4.2.19.956.sif modules/aspera-connect/native/Apptainer.def
apptainer run -B $PWD:/data -H /data \
    -B $HOME/.aspera/connect/etc/asperaweb_id_dsa.openssh:/key/asperaweb_id_dsa.openssh \
    aspera-connect-4.2.19.956.sif \
    ascp -T -l 200M -i /key/asperaweb_id_dsa.openssh \
    --host=ftp-private.ncbi.nlm.nih.gov --user=anonftp --mode=recv \
    /sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242 .
```

### 4. 二进制包安装（官方 release）

官方下载页：<https://www.ibm.com/aspera/connect/>（产品页 <https://www.ibm.com/products/aspera>；
2025-07 起 IBM 以「Aspera for desktop」接替 Connect，Connect 仍在维护）。Linux x86_64 直链
（2026-09-08 抓取 + HEAD 实测 HTTP 200）：

```
https://d3gcli72yxqn2z.cloudfront.net/downloads/connect/latest/bin/ibm-aspera-connect_4.2.19.956-HEAD_linux_x86_64.tar.gz
```

```bash
# 1) 下载 + 解压 + 运行内层自解压安装器（勿以 root 运行！按用户安装到 $HOME/.aspera/connect）
mkdir -p ~/downloads && cd ~/downloads
curl -fL -O \
  https://d3gcli72yxqn2z.cloudfront.net/downloads/connect/latest/bin/ibm-aspera-connect_4.2.19.956-HEAD_linux_x86_64.tar.gz
tar -zxvf ibm-aspera-connect_4.2.19.956-HEAD_linux_x86_64.tar.gz
./ibm-aspera-connect_4.2.19.956-HEAD_linux_x86_64.sh

# 2) PATH + 冒烟（ascp 自报版本号与包版本 4.2.19.956 的对应未核实，输出以实际为准）
export PATH="$HOME/.aspera/connect/bin:$PATH"
ascp --version
ascp --help | head -n 5

# 3)（可选）写 shell profile 免每次 export：
#    echo 'export PATH="$HOME/.aspera/connect/bin:$PATH"' >> ~/.bashrc
```

> 💡 一键脚本走 `native/install.sh`（binary 路线完成下载/解压/安装/PATH + 断言；`--url` 可覆盖
> latest 指针更新后的新直链）。官方页面未公布安装包 sha256 → 脚本与文档均不内嵌校验和，HTTPS
> 下载完整性请自行核对。密钥若随包缺失（实机核查 4.2.13 macOS 已无 DSA 密钥，见上「native 实现」），
> 请自行准备 `asperaweb_id_dsa.openssh` 等密钥并 `-i` 显式指定。
> `ascp --version` 实机输出示例（本机 Connect 4.2.13，2026-09-08）：首行
> `IBM Aspera Connect version 4.2.13 (820)`，次行 `ascp version 4.4.3.820 529a938b9` —— ascp 自报
> 版本号与 Connect 包版本**不一致**（4.4.3.820 ≠ 4.2.13），属正常现象，断言以「ascp version」字样为准。

## 许可与免责

* **Aspera 为 IBM 专有软件（非开源）**，受 IBM 许可条款/EULA 约束（见官方产品页与安装包内文档）；
  本模块/容器配方**仅供个人或机构内部使用**，不得随意再分发（不随镜像分发 EULA 文本）。
* 本模块所有方法/命令/链接/配方为「录入」性质，**未经真实下载/构建/安装/运行验证**；`ascp` 参数
  细节（含 4.2.x 密钥随包情况、ascp 自报版本格式）以官方文档与 `ascp --help` 实际输出为准，
  凡未核实项均已标注。
* 下载公共数据请遵守 NCBI / ENA 等数据源的使用政策与出口管制要求。

## 历史留存（旧版 3.x 与 CentOS6 时代说明）

* **用户历史参照包**：`ibm-aspera-connect-3.9.6.177839-linux-g2.12-64.tar.gz`（tar 解包后
  `./ibm-aspera-connect-3.9.6.177839-linux-g2.12-64.sh` 安装到 `~/.aspera/connect`，ascp 位于
  `bin/ascp`，密钥 `etc/asperaweb_id_dsa.openssh` —— 密钥路径即由此实装验证）。其旧式直链
  `https://d3gcli72yxqn2z.cloudfront.net/connect/bin/ibm-aspera-connect-3.9.6.177839-linux-g2.12-64.tar.gz`
  **2026-09-08 实测已 404**（cloudfront 旧路径下线；同类 `3.11.1.61` 旧式直链亦 404）→ 仅供参照，
  勿再使用；装新版本请走官方下载页 latest 直链（见「环境安装 §4」）。
* **更早的 3.6.0 / 3.8.3（CentOS6 时代）**：旧教程常引 `downloads.asperasoft.com/connect2/` 与
  `aspera-connect-3.6.0.117418-linux-64.tar.gz` 一类包（当时默认装到 `~/.aspera/connect` 同构）；
  该站点 2026-09-08 已不可达（curl 000），CentOS6 亦早已 EOL → 仅作历史背景，**勿再使用**。
* IBM 方向：2025-07 官方博客宣布「Aspera for desktop」接替 Connect（桌面产品线），CLI ascp 生态
  （NCBI/ENA）仍以 Connect 安装包为分发形态，社区亦有 IBM aspera-cli 容器（`ibmcom/aspera-cli`，
  属 Aspera CLI 产品线；本网络核实 Docker Hub API 超时 000 → 未确认，标注未核实）。

## 测试

```bash
bash modules/aspera-connect/native/test/run_test.sh   # ascp/version argv 构造断言（ascp 不在 PATH 时同样通过）
```

## 版本

* **aspera-connect 4.2.19.956**：IBM 官方下载页（2026-09-08 抓取）Linux x86_64 latest 直链，文件名
  `ibm-aspera-connect_4.2.19.956-HEAD_linux_x86_64.tar.gz`（带 -HEAD 滚动标签；latest 为滚动指针，
  版本号可能继续更新，重建前以官方页面为准）。官方页面未公布 sha256（未核实到 → 不内嵌，杜绝编造）。
* 构建路线：官方渠道无维护容器 → **自建容器**（native/Dockerfile + Apptainer.def，debian:bookworm-slim，
  linux/amd64，官方 tar.gz 自解压 .sh + runuser nobody，仅录入不实构建）；宿主一键
  `bash native/install.sh`（binary 默认）。
* 用法形态：单一大命令 `ascp`（--mode=recv 等旗标组合，非多子命令）；`--threads`/`--tmpdir` 仅接受
  不注入（ascp 无对应参数）。参数细节以官方 `ascp --help` 为准。
* 版本自报：`ascp --version` 实机输出（本机 Connect 4.2.13）为两行 —— `IBM Aspera Connect version
  4.2.13 (820)` 与 `ascp version 4.4.3.820 529a938b9`；ascp 自报版本号与 Connect 包版本号不一致属
  正常现象 → 安装断言只查「ascp version / Usage: ascp」字样，不断言具体数字（官方页面亦未公布
  包 sha256 → 全程不内嵌校验和）。

***

## 容器与 Conda 链接

* **官方**：下载页 <https://www.ibm.com/aspera/connect/>；产品页 <https://www.ibm.com/products/aspera>
  （下载小节 <https://www.ibm.com/products/aspera/downloads>）；Linux x86_64 直链
  <https://d3gcli72yxqn2z.cloudfront.net/downloads/connect/latest/bin/ibm-aspera-connect_4.2.19.956-HEAD_linux_x86_64.tar.gz>
  （2026-09-08 HEAD 200）；IBM 手册 <https://www.ibm.com/docs/aspera-connect>
* **bioconda**：无（api.anaconda.org/package/bioconda/{aspera-connect,aspera,ascp} 全 404，2026-09-08）
* **conda-forge**：无（api.anaconda.org/package/conda-forge/{aspera-connect,aspera} 404，2026-09-08）
* **quay.io/biocontainers / depot.galaxyproject.org**：无（quay API 401 = 无此公开仓库；depot
  `singularity/aspera-connect:4.2.19.956` HTTP 404，2026-09-08）
* **nf-core / snakemake-wrappers**：`modules/nf-core/{ascp,aspera-connect}` 与 `bio/{ascp,aspera-connect}`
  均 404（2026-09-08）
* **Homebrew**：homebrew-core `aspera-connect.json`/`aspera.json` 404、brewsci/bio
  `aspera-connect.rb`/`aspera.rb` 404（2026-09-08）→ 无公式，不提供 brew 安装
* **补充线索（未核实）**：Docker Hub `ibmcom/aspera-cli`（IBM 官方 aspera-cli 容器，属 Aspera CLI
  产品线而非 Connect；本网络核实 hub.docker.com API 超时 000 → 未确认，仅登记说明）
* **自建容器**：`modules/aspera-connect/native/Dockerfile`（`docker build -t aspera-connect:4.2.19.956
  modules/aspera-connect/native/`）、`modules/aspera-connect/native/Apptainer.def`（`apptainer build
  aspera-connect-4.2.19.956.sif modules/aspera-connect/native/Apptainer.def`）
