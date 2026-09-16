# signalp 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
>
> ⚠️ **许可限制（重要）**：SignalP 5.0 由 DTU（丹麦技术大学）授权，**需用 edu 邮箱在官方软件页申请下载链接，禁止商用**。官方 tarball 为许可受限资产，本模块**不提供、也不伪造任何官方直链**；容器配方消费用户自备的授权发行包。
>
> ⚠️ **官方渠道核实（2026-09）**：bioconda `signalp` **404**（仅第三方频道 `predector/signalp3..6`，非官方）· quay.io/biocontainers 无（bioconda 无包 → 自动构建链不存在）· depot.galaxyproject.org/singularity/signalp **404** · biocontainers.pro **404** → 走自建容器兜底。

***

## native 实现

# signalp / native — SignalP 5.0 信号肽预测驱动

SignalP 5.0 的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

SignalP 是用于预测蛋白质信号肽及其剪切位点的工具，广泛应用于分泌蛋白预测。支持真核生物、革兰氏阳性菌和革兰氏阴性菌。

两个子命令覆盖 信号肽分析：

| 子命令       | 命令                                                                             | 作用                       |
| --------- | ------------------------------------------------------------------------------ | ------------------------ |
| `predict` | `signalp -org <euk\|gram+\|gram-\|archaea> -fasta <in> [-batch N] [-gff3] [-prefix P]` | 蛋白质 FASTA → 信号肽预测（产出汇总表 + 成熟序列） |
| `mature`  | 同上并追加 `-mature`                                                                 | 对成熟蛋白/已去信号肽序列预测           |

> SignalP 5.0 本体**单线程**（`-batch` 分批处理），`--threads` 为统一接口保留（仅供上层调度器读取），不注入命令行；`TMPDIR` 由 `optimization.env_vars` 透传。

## 用法

```bash
# CLI 直跑（分泌蛋白步骤1）
python main.py predict ../../proteins.fasta -org euk -batch 30000 --gff3 -prefix proteins
python main.py mature  proteins.fasta -org euk -prefix proteins

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：分泌蛋白预测（SignalP → TMHMM）

分泌蛋白预测流程的两步串联：先用 SignalP 预测信号肽并导出成熟蛋白，再用 TMHMM 排除跨膜蛋白。

```bash
mkdir -p secreted_protein/singalp
cd secreted_protein/singalp

# 步骤1：信号肽分析（-org euk 真核；-batch 30000 分批；-gff3/-mature 导出成熟序列）
signalp -batch 30000 -org euk -fasta ../../proteins.fasta -gff3 -mature
# 产出 proteins_mature.fasta（下游 TMHMM 步骤输入）与 proteins_summary.signalp5

cd ..
mkdir TMHMM && cd TMHMM
# 步骤2：跨膜区分析（见 modules/tmhmm）
tmhmm ../singalp/proteins_mature.fasta > tmhmm.out
grep "Number of predicted TMHs:  0" tmhmm.out | perl -p -e 's/#\s+(\S+).*/$1/' > genes_without_TMHs.list
```

> 等价能力由 `native/main.py` 的 `predict` / `mature` 子命令提供（见上「用法」）；步骤2 的 TMHMM 见 `modules/tmhmm`。

## 环境安装（无官方渠道，自建容器 / 自备官方授权 tarball）

SignalP 官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）**全无**，且官方 tarball **许可受限**（需 edu 邮箱向 DTU 申请）→ 本模块走**自建兜底**（`native/Dockerfile`、`native/Apptainer.def`），构建须提供用户自备的授权包。

### 1. Docker（自建镜像）

```bash
# 官方直链需 edu 邮箱申请；用自托管/本地副本作为构建输入
docker build --build-arg SIGNALP_URL=https://<your-mirror>/signalp-5.0.Linux.tar.gz \
    -t bioskills/signalp:5.0 modules/signalp/native
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/signalp:5.0 -org euk -fasta /data/proteins.fasta -gff3 -mature
```

### 2. Apptainer / Singularity

无官方 sif（depot 无 signalp，2026-09 核实 404），从本模块自建配方构建（与 Docker 同一 apt 路线）：

```bash
export SIGNALP_URL=https://<your-mirror>/signalp-5.0.Linux.tar.gz   # 或解开 Apptainer.def %files 放本地 tarball
apptainer build signalp.sif modules/signalp/native/Apptainer.def
apptainer run --bind $PWD:/data signalp.sif -org euk -fasta /data/proteins.fasta -gff3 -mature
```

### 3. 官方预编译二进制包（许可受限，需自备授权 tarball）

* 官网：<https://services.healthtech.dtu.dk/services/SignalP-5.0/>

* 官方软件页（需 edu 邮箱申请下载链接）：<https://services.healthtech.dtu.dk/services/software.php>

* 取得授权 `signalp-5.0.Linux.tar.gz` 后，用 `native/install.sh` 部署到 `~/software/signalp-5.0`：

```bash
bash modules/signalp/native/install.sh --archive ~/software/signalp-5.0.Linux.tar.gz
```

### 4. Conda / brew（均不可用，已核实）

* **conda**：`anaconda.org/bioconda/signalp` 返回 **404**，无官方包可装（第三方频道 `predector/signalp*` 非官方，不登记）；教程提到的 `conda install -c bioconda signalp` 在当前频道已不可用。
* **brew**：homebrew-core 与 brewsci/bio 均**无** signalp 公式（2026-09 核实 404）→ 不写 brew 块。

## 测试

```bash
bash test/run_test.sh   # 需授权模型，退化为 argv 构造验证（monkeypatch 二进制解析）
```

## 容器与 Conda 链接

* **Bioconda 页面**：无（`anaconda.org/bioconda/signalp` 404）

* **Docker**：无官方镜像；自建配方 `modules/signalp/native/Dockerfile`（`bioskills/signalp:5.0`）

* **Singularity**：无官方 sif；自建配方 `modules/signalp/native/Apptainer.def`

* **官方渠道核实（2026-09）**：bioconda 404 · quay.io/biocontainers 无 · depot.galaxyproject.org 404 · biocontainers.pro 404 · nf-core 404 · snakemake-wrappers 404

* 安装方式（本地）：许可受限，需自备授权 tarball → `native/install.sh --archive <signalp-5.0.Linux.tar.gz>` 或自建容器

## 版本

* signalp 5.0（官方预编译包 `signalp-5.0.Linux.tar.gz`）

* 构建路线：无官方 conda/容器 → 自建容器（`debian:bookworm-slim` + apt perl 运行时 + 用户自备授权 tarball）

* 许可：Proprietary（DTU 学术许可；需 edu 邮箱申请，非商业）
