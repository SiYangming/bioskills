# dia-nn 软件模块

> 汇总说明：DIA-NN（DIA 质谱蛋白质组学软件）本模块仅实现 `native/`（run/lib 子命令驱动）。
> 官方登记：**nf-core modules/diann 存在**（容器 `docker.io/biocontainers/diann:v1.8.1_cv1`，模块显式禁用
> conda/mamba profile）→ 本仓库**不建 nextflow/ 目录**，用法见下文「官方登记」；snakemake-wrappers
> `bio/diann` 404（不存在）→ Snakemake 场景暂无官方 wrapper。DIA-NN 官方容器渠道
> （bioconda → quay.io/biocontainers → depot.galaxyproject.org）全无，`native/` 提供**自建**
> Dockerfile / Apptainer.def（apt 最小化）。

***

## 官方登记（不建目录，仅说明 + 引用）

* **nf-core**：`modules/nf-core/diann/` 存在（2026-09-07 抓取 GitHub API 核实；官方目录含
  `insilicolibrarygeneration/` 旧拆分子模块与顶层合并版 `main.nf` + `meta.yml` + `tests/`，以官方在线目录为准）。
  DIA-NN 无 bioconda 包，模块无 environment.yml，`-profile conda/mamba` 下直接报错，仅支持
  Docker / Singularity / Podman。执行请用 `nf modules install nf-core diann` 安装到项目自身目录，
  **不要直接引用本仓库示例 main.nf**。nf-core 容器 pin 为 `docker.io/biocontainers/diann:v1.8.1_cv1`
  （版本较旧；与下方 native 2.6.1 存在版本差）。

* **snakemake-wrappers**：`bio/diann` 不存在（2026-09-07 抓取
  <https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/diann> 返回 404）。
  Snakemake 场景目前无官方 wrapper；确需本地规则时按 td2 式自建 `snakemake/` 并登记 meta。

## native 实现

# dia-nn / native — DIA 质谱分析驱动

DIA-NN 2.6.1 的本地自包含实现（`source_type: custom`、`type: native`）。DIA-NN 官方 CLI 是单一
`diann` 二进制 + 旗标组合（无原生子命令），本驱动按**两步工作流**封装两个子命令：

| 子命令 | 命令 | 作用 |
| --- | --- | --- |
| `lib` | `diann --fasta <f> --predictor --out-lib <prefix>` | in-silico 预测谱图库生成（输出 `<prefix>.predicted.speclib`） |
| `run` | `diann [--fasta] [--lib] --dir <rawdir> --out <tsv> --qvalue ...` | DIA 数据分析（搜库 + 定量，报告 TSV + 可选矩阵） |

## 用法

```bash
# CLI 直跑（两步式：先建预测库，再分析 .raw/.d/.mzML 数据）
python main.py lib --fasta uniprot_proteome.fasta --out-lib report-lib --threads 8
python main.py run --fasta uniprot_proteome.fasta --lib report-lib.predicted.speclib \
    --dir raw/ --out report.tsv --qvalue 0.01 --matrices --threads 8

# 或一步式：无库直接搜 FASTA
python main.py run --fasta uniprot_proteome.fasta --dir raw/ --out report.tsv \
    --fasta-search --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖；`lib` 亦可用别名 `library`。

## 实战示例：两步式（生成库 → 分析）与运行注意

> 典型蛋白组 DIA 分析链路；等价能力由 `native/main.py` 的 `lib` / `run` 子命令提供（见上「用法」）。
> 容器内运行（**任意 diann 镜像**）必须加 `-u $(id -u):$(id -g)`，否则输出文件归 root 持有
> （常见报错 `ERROR: I0Error: Failed to open local file ... [errno 13] Permission denied`）。

### 1. 社区镜像容器版（quay.io/bioinfortools/diann:2.3.2，两段式 + 后台管理）

> `quay.io/bioinfortools/diann` 是社区镜像（2026-09-07 quay API 核实**仅 2.3.2 单 tag**，非官方维护；
> 官方渠道无镜像，本模块自建配方见「环境安装」）。

```bash
# 第一步：后台生成预测库（-d 后台 + --name 便于管理；挂载父目录简化路径）
docker run -d --name diann_gen_lib \
   --user $(id -u):$(id -g) \
   -v /data1/users/siyangming/lv-test/diann_analysis:/data \
   -w /data/results \
   quay.io/bioinfortools/diann:2.3.2 \
   diann --fasta /data/fasta_db/uniprotkb_proteome_UP000059680_2026_03_06.fasta \
         --predictor --fasta-search --threads 120
docker logs -f diann_gen_lib        # 出现 "Finished" 后 Ctrl+C，进入下一步

# 第二步：后台分析数据（--lib 指向第一步产出的预测库）
docker run -d --name diann_analysis \
   --user $(id -u):$(id -g) \
   -v /data1/users/siyangming/lv-test/diann_analysis:/data \
   -w /data/results \
   quay.io/bioinfortools/diann:2.3.2 \
   diann --fasta /data/fasta_db/uniprotkb_proteome_UP000059680_2026_03_06.fasta \
         --lib /data/results/report-lib.predicted.speclib \
         --dir /data/input_data --out /data/results/rice_diann_leaf_root.tsv \
         --threads 120 --qvalue 0.01 --matrices --relaxed-prot-inf --reanalyse
docker logs -f diann_analysis

# 管理：docker ps 查看状态；docker stop/rm diann_gen_lib diann_analysis 停止与清理
```

### 2. 等价 native 直跑（2.6.1 官方 zip）

```bash
mkdir -p results && cd results
python ../native/main.py lib --fasta ../db/uniprot_proteome.fasta --out-lib report-lib --threads 32
python ../native/main.py run --fasta ../db/uniprot_proteome.fasta --lib report-lib.predicted.speclib \
    --dir ../raw/ --out rice_diann_leaf_root.tsv --threads 32 \
    --qvalue 0.01 --matrices --relaxed-prot-inf
```

### 3. 参数说明

| 参数 | 说明 |
| --- | --- |
| `--fasta` | 蛋白 FASTA 数据库（搜库/生成库用） |
| `--lib` | 谱图库 `.speclib`（跳过库生成的分析；配合第一步产物） |
| `--out-lib` | 预测库输出前缀（实际产出 `<prefix>.predicted.speclib`） |
| `--dir` | 质谱原始数据目录（.raw / Bruker .d / .mzML） |
| `--out` | 输出报告 TSV |
| `--qvalue` | Q-value 阈值（默认 0.01） |
| `--predictor` / `--fasta-search` | 深度学习预测器 / 直接 FASTA 搜索（无库分析） |
| `--matrices` | 输出定量矩阵（pg/pr/gg/unique_genes_matrix.tsv） |
| `--threads` / `--tmpdir` | 线程 / 临时目录（main.py 自动注入） |

## 环境安装（无官方镜像，自建 apt 最小化配方）

官方容器渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）均无 DIA-NN
（2026-09-07 核实），故 `native/` 提供自建配方 `Dockerfile` + `Apptainer.def`（debian:bookworm-slim +
apt `--no-install-recommends` + 清理四连；.NET 8 Runtime 来自 packages.microsoft.com 的
`dotnet-runtime-8.0`，**勿装 SDK**）。宿主机直跑 `main.py` 时按下面 1/4 安装 diann。

### 1. Conda / brew（包管理器安装）

DIA-NN **不在 bioconda**（404）；仅个人频道 YangmingSi 有 `dia-nn=2.3.2`（linux-64，2026-02 上传）。
brew 两源均无（homebrew-core `diann.json` 404、brewsci/bio `diann.rb` 404，2026-09-07 核实），故不提供 brew 块。

```bash
# conda（仅 2.3.2；2.6.1 请走官方 zip / 容器）
conda create -n dia-nn -c conda-forge -c yangmingsi dia-nn=2.3.2
conda activate dia-nn
diann --help   # 冒烟（banner 见 DIA-NN 2.3.2）
```

> 一键安装直接 `bash native/install.sh`（linux-x64 默认走官方 zip **2.6.1** binary 路线并写
> `.NET 8 Runtime` 检查；conda 路线仅支持 2.3.2；`bash native/install.sh --help` 看参数）。

### 2. Docker（自建镜像；社区镜像备选）

```bash
# 自建（官方渠道无镜像 → 本地配方构建；zip 下载约 360 MB + .NET runtime）
docker build -t dia-nn:2.6.1 modules/dia-nn/native/

# 运行：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data dia-nn:2.6.1 \
    diann --fasta /data/db/uniprot.fasta --dir /data/raw --out /data/report.tsv --threads 8
```

社区镜像备选（非官方维护、仅 2.3.2）：`docker pull quay.io/bioinfortools/diann:2.3.2`，运行同上
（两段式示例见「实战示例 §1」）。

### 3. Apptainer / Singularity

无 depot.galaxyproject.org 预构建 sif（官方渠道无 DIA-NN），**无法 `apptainer pull` 直拉**，本地构建：

```bash
apptainer build dia-nn-2.6.1.sif modules/dia-nn/native/Apptainer.def
apptainer run -B $PWD:/data -H /data dia-nn-2.6.1.sif \
    diann --fasta /data/db/uniprot.fasta --dir /data/raw --out /data/report.tsv --threads 8
```

### 4. 二进制包安装（官方 release）

* **GitHub**：<https://github.com/vdemichev/DiaNN>（Academia Linux zip 挂于 release **tag=2.0** 下）

```bash
# 前提：.NET 8 Runtime（diann-linux 为 .NET 8 框架依赖程序）
#   Debian 12：wget https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb \
#                && sudo dpkg -i packages-microsoft-prod.deb \
#                && sudo apt-get update && sudo apt-get install -y dotnet-runtime-8.0
#   （勿装 dotnet-sdk；其它发行版见 https://learn.microsoft.com/dotnet/core/install/linux）

mkdir -p ~/software && cd ~/software
wget https://github.com/vdemichev/DiaNN/releases/download/2.0/DIA-NN-2.6.1-Academia-Linux.zip
echo "f98e396af791f1903168b365a83fc2cc72208cc133281b9ce6ebe3a794b999ba  DIA-NN-2.6.1-Academia-Linux.zip" | sha256sum -c -
unzip DIA-NN-2.6.1-Academia-Linux.zip        # 解出 DIA-NN-2.6.1-Academia-Linux/diann-2.6.1/

# 写 wrapper（LD_LIBRARY_PATH 指向程序目录：libtorch/libgomp 等随包 .so）
cat > ~/software/bin/diann <<'EOF'
#!/usr/bin/env bash
export LD_LIBRARY_PATH="$HOME/software/DIA-NN-2.6.1-Academia-Linux/diann-2.6.1${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$HOME/software/DIA-NN-2.6.1-Academia-Linux/diann-2.6.1/diann-linux" "$@"
EOF
chmod +x ~/software/bin/diann && export PATH="$HOME/software/bin:$PATH"
diann --help   # 冒烟：banner 含 DIA-NN 2.6.1
```

> 💡 一键脚本走 `native/install.sh`（binary 路线完成下载/解压/校验/wrapper/PATH + 版本断言）。
> 许可证：Academia 版学术/非营利免费，商用需官方许可（使用者自行负责合规）。

## 测试

```bash
bash modules/dia-nn/native/test/run_test.sh   # run/lib 为 argv 构造断言（无 .raw 无法真实跑）
```

## 版本

* DIA-NN 2.6.1（Academia Linux；官方 zip，release tag=2.0，sha256 见上）；conda 兜底 2.3.2（YangmingSi 频道）。

* 构建路线：无官方容器 → **自建 apt 最小化**（native/Dockerfile + Apptainer.def）；社区镜像
  `quay.io/bioinfortools/diann:2.3.2` 与 nf-core 容器 pin `v1.8.1_cv1` 均与 2.6.1 存在版本差
  （三方差异逐条记录于软件级 `meta.yaml` `software_versions`）。

* 运行依赖：.NET 8 Runtime（packages.microsoft.com `dotnet-runtime-8.0`）+ `LD_LIBRARY_PATH`
  指向解压目录；`diann-stats.py`（随包统计脚本）需要 python3 + polars/numpy/matplotlib。

## conda-recipe 留存

DIA-NN 官方无 conda 包，历史 2.3.2 配方打包上传至 YangmingSi 频道（2026-02）；
conda-build 配方按 AGENT.md 规范归档于 `native/conda-recipe/linux-64/meta.yaml`（仅 linux-64，
官方无 macOS 分发）。重建/升级到 2.6.1：先下载官方 zip 解压到本地 → 按配方头注改 `source.path`
→ `conda build conda-recipe/linux-64` → `anaconda upload`。

***

## 容器与 Conda 链接

* **官方**：GitHub <https://github.com/vdemichev/DiaNN>；release tag=2.0：
  <https://github.com/vdemichev/DiaNN/releases/download/2.0/DIA-NN-2.6.1-Academia-Linux.zip>

* **bioconda**：无（<https://anaconda.org/bioconda/dia-nn> 404）

* **quay.io/biocontainers / depot.galaxyproject.org**：无 DIA-NN（2026-09-07 核实）

* **社区镜像（补充登记）**：`quay.io/bioinfortools/diann:2.3.2`

* **个人 conda 频道（补充登记）**：<https://anaconda.org/channels/YangmingSi/packages/dia-nn/overview>
  （`conda install -c yangmingsi dia-nn=2.3.2`；配方 `native/conda-recipe/linux-64/meta.yaml`）

* **自建容器**：`modules/dia-nn/native/Dockerfile`（`docker build -t dia-nn:2.6.1 modules/dia-nn/native/`）、
  `modules/dia-nn/native/Apptainer.def`（`apptainer build dia-nn-2.6.1.sif modules/dia-nn/native/Apptainer.def`）
