# prottest 软件模块

> 汇总说明：本 README 说明 native 实现的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# prottest / native — 自包含蛋白质模型选择驱动

ProtTest3（ProtTest）的本地自包含实现（`source_type: custom`、`type: native`；Java 工具）。

## 功能

ProTest - 蛋白质替代模型选择工具。

| 子命令   | 命令                                                                                                                               | 作用                        |
| ----- | -------------------------------------------------------------------------------------------------------------------------------- | ------------------------- |
| `run` | `java <JAVA_OPTS> -jar prottest-3.4.2.jar -i <aln> [-t <tree>] -all-distributions -F -AIC -BIC -tc <x> -o <out> -threads N`        | 序列版模型选择（14.md 4.5）        |
| `hpc` | `bash runProtTestHPC.sh <np> -i <aln> [-t <tree>] -all-distributions -F -AIC -BIC -tc <x>`（需 MPJ Express）                          | MPJ 并行模型选择（大规模比对）         |

JVM 堆内存与临时目录经 `JAVA_OPTS`（`-Xmx6g -Djava.io.tmpdir=<tmpdir>`）透传。

## 用法

```bash
# CLI 直跑
python main.py run allSingleCopyOrthologsAlign.phy -all-distributions -F -AIC -BIC -tc 0.5 --threads 4 -o prottest.out
python main.py hpc allSingleCopyOrthologsAlign.phy -all-distributions -F -AIC -BIC --processes 4

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`hpc` 用 `--processes` 指定 MPI 进程数）。

## 实战示例：ProTest 选择最佳蛋白质模型

ProTest 对氨基酸比对逐一拟合替换矩阵（JTT/LG/WAG/DCMut/…）与位点异质性（+I/+G/+I+G）组合，按 AIC/BIC 给出最佳模型，再交给 RAxML / IQ-TREE / FastTree 建树。以下为 14.md 的典型流程；等价能力由 `native/main.py` 的 `run` 子命令提供（见上「用法」）。

```bash
# 用 ProTest 选择最佳模型（计算量较大：14.md 记 ~1472 分钟）
java -jar $PROTTEST_HOME/prottest-3.4.2.jar \
    -i allSingleCopyOrthologsAlign.phy -all-distributions -F -AIC -BIC \
    -tc 0.5 -threads 4 -o prottest.out

# 依据 prottest.out 的最佳模型（如 LG+G）驱动 IQ-TREE 建树
iqtree -s allSingleCopyOrthologsAlign.Protein.phy -m LG+G -bb 1000 -T 8
```

### 参数说明

| 参数                   | 说明                                    |
| -------------------- | ------------------------------------- |
| `-i`                 | 氨基酸多序列比对文件（PHYLIP/NEXUS/FASTA）         |
| `-t`                 | 起始树文件（可选；缺省由 ProTest 生成 NJ 树）          |
| `-o`                 | 结果输出文件（缺省 stdout）                     |
| `-all-distributions` | 纳入 +G 与 +I+G 速率异质性模型                  |
| `-F`                 | 纳入经验氨基酸频率估计模型                         |
| `-AIC` / `-BIC`      | 按 AIC / BIC 排序输出                     |
| `-tc`                | 共识树阈值（0.5~1.0；输出共识树）                  |
| `-threads`           | 序列版线程数（`hpc` 用 `--processes` 指定 MPI 进程数） |

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

ProtTest3 **无官方 conda/容器渠道**（bioconda 404 → quay 无 → depot 404，2026-09 核实），官方以 GitHub release 分发**预编译 Java 包**并公开源码；因此两条官方路线（预编译包 / 源码编译）均保留，本模块另提供**自建容器兜底**。

### 1. 官方预编译二进制包（首选）

```bash
# 下载官方预编译包（GitHub release 3.4.2-release）
wget https://github.com/ddarriba/prottest3/releases/download/3.4.2-release/prottest-3.4.2-20160508.tar.gz -P ~/software/

# 解压到用户级前缀（无需 root；禁 /opt/biosoft、/home/train）
mkdir -p ~/software/prottest-3.4.2
tar zxf ~/software/prottest-3.4.2-20160508.tar.gz -C ~/software/prottest-3.4.2 --strip-components=1

# 设置 PROTTEST_HOME 并运行（tar 内 jar 名为 prottest-3.4.2.jar）
export PROTTEST_HOME=~/software/prottest-3.4.2
java -jar $PROTTEST_HOME/prottest-3.4.2.jar -h
```

> 一键安装可直接运行 `native/install.sh`（下载官方预编译包到 `~/software/prottest-3.4.2`，生成 `prottest` 包装脚本、写 PATH 并设 `PROTTEST_HOME`；版本默认 3.4.2，与下方 `software_versions` 对齐，内嵌官方 tarball sha256。用法：`bash native/install.sh --help`）。

### 2. 官方源码编译（并列保留）

```bash
# 官方源码归档（tag 3.4.2-release）
wget https://github.com/ddarriba/prottest3/archive/refs/tags/3.4.2-release.tar.gz -P ~/software/
tar zxf ~/software/3.4.2-release.tar.gz -C ~/software/

# 依赖 Apache Ant + JDK（官方 INSTALL：ant jar → dist/）
cd ~/software/prottest3-3.4.2-release
ant jar
java -jar dist/prottest-3.4.2.jar -h
```

### 3. Conda / brew

**未提供**：bioconda（`anaconda.org/bioconda/prottest` 404）、homebrew-core、brewsci/bio 均无 prottest 公式（2026-09 核实）；宿主安装请走上方官方预编译包或源码编译，容器走下方自建配方。

### 4. Docker（自建兜底配方）

```bash
# context 必须是 modules/ 层（携带 base.py 与软件级 meta.yaml）
docker build -t bioskills/prottest:3.4.2 -f modules/prottest/native/Dockerfile modules/

# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/prottest:3.4.2 run aln.phy -all-distributions -F -AIC -BIC -tc 0.5 -threads 4 -o prottest.out
```

### 5. Apptainer / Singularity（自建 def）

```bash
apptainer build prottest.sif modules/prottest/native/Apptainer.def
apptainer run -B $PWD:/data -H /data prottest.sif run /data/aln.phy -o /data/prottest.out
```

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（ProtTest 真实计算量极大，不做真实模型选择）
```

## 版本

* prottest 3.4.2（ProtTest3；官方 GitHub release `prottest-3.4.2-20160508.tar.gz`，jar 名 `prottest-3.4.2.jar`）

* 构建路线：无官方 conda/容器 → 自建兜底（`native/Dockerfile` / `native/Apptainer.def`：debian:bookworm-slim + apt openjdk-17-jre-headless + 官方预编译 tarball）

* 官方层：nf-core / snakemake-wrappers 均无 prottest（2026-09 核实 404）

## 容器与 Conda 链接

* **Bioconda**：无 prottest 包（<https://anaconda.org/bioconda/prottest> 404，2026-09 核实）

* **Docker**：无官方镜像 → 自建 `bioskills/prottest:3.4.2`（配方 `native/Dockerfile`）

* **Singularity**：无官方镜像 → 自建 `prottest.sif`（配方 `native/Apptainer.def`）

* **官方来源**：预编译包 <https://github.com/ddarriba/prottest3/releases/download/3.4.2-release/prottest-3.4.2-20160508.tar.gz>；源码 <https://github.com/ddarriba/prottest3>

* 安装方式（本地）：`bash native/install.sh`（默认官方预编译包 → `~/software/prottest-3.4.2`）
