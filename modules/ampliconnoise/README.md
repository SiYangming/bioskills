# ampliconnoise 软件模块

> 汇总说明：本 README 合并各实现的用法；安装方式见下方各节，容器与依赖信息记录于此。
> AmpliconNoise 是 **454 焦磷酸测序时代（2011）** 的扩增子去噪 / 嵌合体检测程序集，官方渠道（bioconda / quay.io/biocontainers / depot.galaxyproject.org）**均无**，原 Google Code 站已死，仅归档发布包可达。

***

## native 实现（说明型 / MPI 命令构造，`source_type: custom` / `type: native`）

本实现为「说明型 + 命令构造」：`native/main.py` 按 AmpliconNoise V1.27 各程序用法构造命令行
（默认补 `mpirun -np <N>`）并打印，**不实际执行**（历史工具 + MPI）。覆盖发布包内 12 个程序：

| 子命令 | 作用 |
| ---- | ---- |
| `PyroNoise` | 454 焦磷酸测序数据去噪主程序 |
| `PyroNoiseM` | PyroNoise 改进版（含待测序错误模型） |
| `PyroDist` | 计算去噪序列间距离 |
| `SeqNoise` | 去噪后序列的进一步去噪 |
| `SeqDist` | 计算去噪后序列距离 |
| `NDist` | 计算核苷酸级距离 |
| `FCluster` | 按距离阈值聚类 |
| `FastaUnique` | FASTA 去冗余 / 统计唯一序列 |
| `SplitClusterEven` | 均分策略拆分聚类 |
| `SplitClusterClust` | 按聚类拆分 |
| `Perseus` | 嵌合体检测（基于距离） |
| `PerseusD` | 嵌合体检测（de novo） |

```bash
# CLI 直跑（构造 MPI 命令，仅供复现；先编译安装，见「环境安装」）
python main.py PyroNoise -s reads.sff -d Data -o out --threads 8
python main.py PerseusD clustered.fna --threads 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads`（即 MPI 进程数 `mpirun -np N`）与 `--tmpdir`。构造命令通过 stderr
打印历史工具提示，stdout 只输出命令本身。

### 历史流程

QIIME 1 早期通过 `qiime-deploy` 把 AmpliconNoise 作为 454 去噪后端一并部署（`AmpliconNoiseV1.27`
解压到 `qiime/ampliconnoise-1.27-release`，`make && make install`）。典型 454 去噪/嵌合体链路：

```bash
# 1) 454 去噪（PyroNoise 主程序，MPI 并行）
mpirun -np 8 PyroNoise -s 454Reads.sff -d Data -o out

# 2) 去噪序列距离 + 聚类 + 嵌合体检测（PerseusD）
mpirun -np 8 PyroDist -d out -o dist
mpirun -np 8 FCluster -d dist -o clusters
mpirun -np 8 PerseusD clusters.fna
```

> 等价能力由 `native/main.py` 的同名程序子命令提供（见上「用法」）；先 CLI 后 main.py。
> ⚠️ 新项目请直接用 **DADA2 / Deblur**（ASV 去噪，见本仓库 `qiime2` 模块）。

## 测试

```bash
bash test/run_test.sh   # MPI 命令构造/线程(=进程数)/parser/CLI stub 自省为常驻断言（不下载/不编译/不执行真实分析）
```

## 环境安装（官方归档源码编译优先；自建容器配方兜底）

> 官方现状（2026-09 核实，如实记录）：**官方渠道全无** —— bioconda `ampliconnoise` 404、
> quay.io/biocontainers 无、depot.galaxyproject.org 无；**原 Google Code 站
> `code.google.com/p/ampliconnoise` 已死**（curl 000），仅 **Google Code 归档发布包**可达
> （`AmpliconNoiseV1.27.tar.gz`，HTTP 200，content-length 1379908）→ 唯一官方路线 = 归档源码
> `make && make install`（依赖 MPI）。本模块同时提供自建 `Dockerfile`/`Apptainer.def` 兜底。

### 1. 官方归档源码编译（首选；依赖 MPI）

```bash
# 依赖：gcc/make（build-essential）+ MPI（apt: mpich 或 openmpi；macOS: brew install mpich）
apt-get install -y build-essential mpich  # 或 sudo

curl -fsSL -o /tmp/AmpliconNoiseV1.27.tar.gz \
    https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/ampliconnoise/AmpliconNoiseV1.27.tar.gz
tar -xzf /tmp/AmpliconNoiseV1.27.tar.gz -C ~/software/
cd ~/software/AmpliconNoiseV1.27
make && make install          # 产物在 bin/（PyroNoise 等），Data/ 为运行时资源
export PATH="$HOME/software/AmpliconNoiseV1.27/bin:$PATH"
```

> 一键安装直接 `bash native/install.sh`（默认从 Google Code 归档源码编译到 `~/software/ampliconnoise-1.27`，
> 含 `bin/` 与 `Data/`；需 `mpicc`）。可用 `--source-url <tarball_or_git_url>` 指向自备归档。

> 说明：AmpliconNoise **无预编译二进制包**（40 年前时代的 C+MPI 源码，官方仅发布源码 tar.gz），
> 故无「预编译包」小节；唯一官方路线即源码编译。**conda / brew 均无包**（bioconda 404、homebrew-core
> 与 brewsci/bio 无 formula，2026-09 核实）→ 不登记 conda / brew 安装块。

### 2. Docker（自建配方）

无官方镜像；本地构建自建配方（bookworm-slim + apt `build-essential`/`mpich` + 官方归档源码 make）：

```bash
docker build -t bioskills/ampliconnoise:1.27 native/
# 必须 -u $(id -u):$(id -g)，否则产物归 root；AmpliconNoise 为 MPI 程序，用 mpirun 启动
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/ampliconnoise:1.27 \
    mpirun -np 4 PyroNoise -s /data/reads.sff -d /opt/ampliconnoise-1.27/Data -o /data/out
```

### 3. Apptainer / Singularity

depot.galaxyproject.org **无** ampliconnoise 预构建 sif，只能本地 `build`：

```bash
apptainer build ampliconnoise-1.27.sif native/Apptainer.def
apptainer run -B $PWD:/data -H /data ampliconnoise-1.27.sif \
    mpirun -np 4 PyroNoise -s /data/reads.sff -d /opt/ampliconnoise-1.27/Data -o /data/out
```

## 替代建议（新项目请直接使用）

| 替代 | 说明 | 入口 |
| ---- | ---- | ---- |
| **DADA2** | ASV 去噪（扩增子错误模型），QIIME 2 `dada2 denoise-single/paired` | 本仓库 `qiime2` 模块 / <https://benjjneb.github.io/dada2/> |
| **Deblur** | 16S 单端去噪，QIIME 2 `deblur denoise-16S` | 本仓库 `qiime2` 模块 / <https://github.com/biocore/deblur> |

## 容器与 Conda 链接

* **官网（已死）**：<https://code.google.com/p/ampliconnoise/>（2026-09 探测 curl 000）
* **官方归档发布包**：<https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/ampliconnoise/AmpliconNoiseV1.27.tar.gz>（200）
* **本地自建配方**：`native/Dockerfile` + `native/Apptainer.def`（官方渠道全无时的兜底）
* **bioconda**：无包（`api.anaconda.org/package/bioconda/ampliconnoise` 404）｜ **quay / depot**：无
* **brew**：无公式（homebrew-core 与 brewsci/bio 均无，2026-09 核实）
* **社区镜像（非官方，未逐一核实版本）**：GitHub `lanzen/ampliconnoise`、`fhcrc/ampliconnoise`（Python 重实现）

## 版本

* AmpliconNoise **V1.27**（Quince C, Lanzen A, Davenport RJ, Turnbaugh PJ. *Removing noise from
  pyrosequenced amplicons.* BMC Bioinformatics 2011;12:38. doi:10.1186/1471-2105-12-38）
* 依赖：MPI（`mpicc`/`mpirun`，如 mpich/openmpi）、gcc、make；运行时需发布包 `Data/` 资源
* License：**未核实**（原始发布包内未见 LICENSE/COPYING 文件；同类社区镜像标 GPL-3.0，2026-09 未能逐字复核）
* nf-core / snakemake-wrappers：无官方模块（2026-09 核实 `modules/nf-core/ampliconnoise`、`bio/ampliconnoise` 均 404）→ 不登记官方说明层
