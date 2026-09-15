# tmhmm 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
>
> ⚠️ **许可限制（重要）**：TMHMM 2.0c 由 DTU（丹麦技术大学）授权，**需用 edu 邮箱在官方软件页申请下载链接，禁止商用**。官方 tarball 为许可受限资产，本模块**不提供、也不伪造任何官方直链**；容器配方消费用户自备的授权发行包。
>
> ⚠️ **官方渠道核实（2026-09）**：bioconda `tmhmm` **404**（仅第三方频道 `predector/tmhmm` 等，非官方）· quay.io/biocontainers 无（bioconda 无包 → 自动构建链不存在）· depot.galaxyproject.org/singularity/tmhmm **404** · biocontainers.pro **404** → 走自建容器兜底。

***

## native 实现

# tmhmm / native — TMHMM 2.0c 跨膜区预测驱动

TMHMM 2.0c 的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

TMHMM（Transmembrane Helices Hidden Markov Model）是基于隐马尔可夫模型预测蛋白质跨膜螺旋的工具，常用于分泌蛋白筛选（排除具有跨膜结构域的蛋白）。

两个子命令覆盖跨膜区分析：

| 子命令       | 命令                    | 作用                                  |
| --------- | --------------------- | ----------------------------------- |
| `predict` | `tmhmm [-mature] <fasta>` | 预测跨膜螺旋数量与拓扑（默认写 stdout，可 `-o` 落盘）    |
| `plot`    | `tmhmm -plot <fasta>` | 生成跨膜拓扑图（需 gnuplot/X11）               |

> TMHMM 2.0c 为 **Perl 脚本**（安装后需修正 `/usr/local/bin/perl → /usr/bin/perl`，见 13.md），本体**单线程**；`--threads` 为统一接口保留（仅供上层调度器读取），不注入命令行。

## 用法

```bash
# CLI 直跑（13.md 分泌蛋白步骤2；tmhmm 默认写 stdout，用 -o 落盘）
python main.py predict ../singalp/proteins_mature.fasta -o tmhmm.out
python main.py plot    proteins.fasta -o proteins.plot

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：跨膜区分析（TMHMM 筛选无跨膜蛋白）

承接 `modules/signalp` 步骤1 导出的成熟蛋白序列（`proteins_mature.fasta`），用 TMHMM 排除具有跨膜结构域的蛋白：

```bash
mkdir -p secreted_protein/TMHMM
cd secreted_protein/TMHMM

# 预测跨膜螺旋（结果逐蛋白输出到 stdout）
tmhmm ../singalp/proteins_mature.fasta > tmhmm.out

# 筛选「无跨膜螺旋」的蛋白（Number of predicted TMHs: 0）
grep "Number of predicted TMHs:  0" tmhmm.out | perl -p -e 's/#\s+(\S+).*/$1/' > genes_without_TMHs.list
# 再从全蛋白序列中抽取候选分泌蛋白（需 pipeline 提供的 fasta_extract_subseqs_from_list.pl）
fasta_extract_subseqs_from_list.pl ../../proteins.fasta genes_without_TMHs.list > ../candidate_secreted_proteins.fasta
```

> 等价能力由 `native/main.py` 的 `predict` / `plot` 子命令提供（见上「用法」）；步骤1 的 SignalP 见 `modules/signalp`。`fasta_extract_subseqs_from_list.pl` 属流程侧脚本，不在本模块内。

## 环境安装（无官方渠道，自建容器 / 自备官方授权 tarball）

TMHMM 官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）**全无**，且官方 tarball **许可受限**（需 edu 邮箱向 DTU 申请）→ 本模块走**自建兜底**（`native/Dockerfile`、`native/Apptainer.def`），构建须提供用户自备的授权包。

### 1. Docker（自建镜像）

```bash
# 官方直链需 edu 邮箱申请；用自托管/本地副本作为构建输入
docker build --build-arg TMHMM_URL=https://<your-mirror>/tmhmm-2.0c.Linux.tar.gz \
    -t bioskills/tmhmm:2.0c modules/tmhmm/native
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/tmhmm:2.0c /data/proteins_mature.fasta
```

### 2. Apptainer / Singularity

无官方 sif（depot 无 tmhmm，2026-09 核实 404），从本模块自建配方构建（与 Docker 同一 apt 路线）：

```bash
export TMHMM_URL=https://<your-mirror>/tmhmm-2.0c.Linux.tar.gz   # 或解开 Apptainer.def %files 放本地 tarball
apptainer build tmhmm.sif modules/tmhmm/native/Apptainer.def
apptainer run --bind $PWD:/data tmhmm.sif /data/proteins_mature.fasta
```

### 3. 官方预编译二进制包（许可受限，需自备授权 tarball）

* 官网：<https://services.healthtech.dtu.dk/services/TMHMM-2.0/>（新官网）· <http://www.cbs.dtu.dk/services/TMHMM/>（旧官网）

* 官方软件页（需 edu 邮箱申请下载链接）：<https://services.healthtech.dtu.dk/services/software.php>

* 取得授权 `tmhmm-2.0c.Linux.tar.gz` 后，用 `native/install.sh` 部署到 `~/software/tmhmm-2.0c`（自动修正 Perl 路径）：

```bash
bash modules/tmhmm/native/install.sh --archive ~/software/tmhmm-2.0c.Linux.tar.gz
```

### 4. Conda / brew（均不可用，已核实）

* **conda**：`anaconda.org/bioconda/tmhmm` 返回 **404**，无官方包可装（第三方频道 `predector/tmhmm` 等非官方，不登记）；13.md 提到的 `conda install -c bioconda tmhmm` 在当前频道已不可用。
* **brew**：homebrew-core 与 brewsci/bio 均**无** tmhmm 公式（2026-09 核实 404）→ 不写 brew 块。

## 测试

```bash
bash test/run_test.sh   # 需授权模型；argv 构造 + stub 二进制验证 stdout→-o 重定向
```

## 容器与 Conda 链接

* **Bioconda 页面**：无（`anaconda.org/bioconda/tmhmm` 404）

* **Docker**：无官方镜像；自建配方 `modules/tmhmm/native/Dockerfile`（`bioskills/tmhmm:2.0c`）

* **Singularity**：无官方 sif；自建配方 `modules/tmhmm/native/Apptainer.def`

* **官方渠道核实（2026-09）**：bioconda 404 · quay.io/biocontainers 无 · depot.galaxyproject.org 404 · biocontainers.pro 404 · nf-core 404 · snakemake-wrappers 404

* 安装方式（本地）：许可受限，需自备授权 tarball → `native/install.sh --archive <tmhmm-2.0c.Linux.tar.gz>` 或自建容器

## 版本

* tmhmm 2.0c（官方预编译包 `tmhmm-2.0c.Linux.tar.gz`）

* 构建路线：无官方 conda/容器 → 自建容器（`debian:bookworm-slim` + apt perl 运行时 + 用户自备授权 tarball；构建期修正 Perl 路径）

* 许可：Proprietary（DTU 学术许可；需 edu 邮箱申请，非商业）

* 依赖：Perl（`bin/tmhmm*` 需将 `/usr/local/bin/perl` 修正为 `/usr/bin/perl`）
