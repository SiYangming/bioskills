# prothint 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

***

## native 实现

# prothint / native — 自包含蛋白 hints 生成驱动

ProtHint 的本地自包含实现（`source_type: custom`、`type: native`；驱动 ProtHint v2.4.0）。

## 功能

ProtHint 是一个用于生成蛋白 hints 的工具，配合 GenomeThreader 使用。

三段链路对应 ProtHint 官方脚本（均为 Python 3，`main.py` 统一以 `python3 <script>` 驱动）：

| 子命令               | 命令                                                                                     | 作用                                        |
| ----------------- | -------------------------------------------------------------------------------------- | ----------------------------------------- |
| `predict`         | `prothint.py <genome.fasta> <proteins.fasta> [--workdir W] [--threads N]`               | DIAMOND 搜索 + Spaln 剪接比对，生成蛋白 hints（prothint.gff 等） |
| `high_confidence` | `print_high_confidence.py <prothint.gff>`（stdout）                                       | 按覆盖度/比对分阈值筛出高置信 `evidence.gff`          |
| `augustus_hints`  | `prothint2augustus.py <prothint.gff> <evidence.gff> <chains.gff> <output.gff>`          | 转换为 AUGUSTUS/BRAKER 兼容 hints GFF          |

## 用法

```bash
# CLI 直跑（PROTHINT_HOME 指向 ProtHint 安装目录，或脚本在 PATH 中）
python main.py predict genome.softmask.fasta homolog.fasta --workdir prothint_out --threads 8
python main.py high_confidence prothint_out/prothint.gff -o prothint_out/evidence.gff
python main.py augustus_hints prothint_out/prothint.gff prothint_out/evidence.gff \
    prothint_out/chains.gff prothint_out/prothint_augustus.gff

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`predict` 的 `--threads` 透传给 `prothint.py --threads`）。

## 实战示例：BRAKER ET 模式前的蛋白 hints 生成

ProtHint 通过将参考蛋白比对到基因组并剪接对齐，输出 intron/start/stop hints，供 GeneMark-EP+、BRAKER（`--prg=gth --prot_seq=` 的 ET 模式）与 AUGUSTUS 使用；以下为典型蛋白证据流程（BRAKER2 依赖 AUGUSTUS / bamtools / samtools / gth / ncbi-rmblast / diamond / PASA 等工具链，ProtHint 自身依赖 Python 3、Perl 模块及内置的 DIAMOND/Spaln）。等价能力由 `native/main.py` 的 `predict` / `high_confidence` / `augustus_hints` 子命令提供（见上「用法」）。

### 1. 生成蛋白 hints

```bash
# --workdir 固定输出目录；--threads 并行；-L 类长基因可调 --longGene
prothint.py genome.softmask.fasta homolog.fasta --workdir prothint_out --threads 8
# 产物：prothint_out/prothint.gff（全部 hints）、evidence.gff（高置信）、prothint_augustus.gff
```

### 2. 自定义阈值重筛高置信子集

```bash
# 默认阈值见 print_high_confidence.py；可提高 intron 覆盖度获得更严格的 evidence.gff
print_high_confidence.py prothint_out/prothint.gff --intronCoverage 95 > evidence.strict.gff
```

### 3. 参数说明

| 参数                | 说明                                                        |
| ----------------- | --------------------------------------------------------- |
| `--workdir`       | 结果与临时文件目录（默认当前目录）                                         |
| `--threads`       | 并行线程数（DIAMOND / Spaln 阶段）                                   |
| `--geneMarkGtf`   | 提供 GeneMark-ES 预测 GTF 时跳过 GeneMark-ES 运行                     |
| `--diamondPairs`  | 提供 DIAMOND seed gene-protein 命中文件时跳过 DIAMOND 搜索            |
| `--fungus`        | 真菌模式（使用真菌特异性参数）                                           |
| `--evalue`        | DIAMOND 比对 E-value 阈值（默认 0.001）                            |

## 环境安装（官方 release tarball 优先；官方容器缺失，自建 Docker/Apptainer 兜底）

官方仅以 **GitHub release 脚本 tarball** 分发 ProtHint（无 prebuilt 平台二进制包、无官方容器、无 conda 包）——2026-09 核实：bioconda（`api.anaconda.org/bioconda/prothint` 404）、quay.io/biocontainers（无仓库）、depot.galaxyproject.org（404）、brew（core/brewsci 均 404）全部无收录，故容器走自建兜底（`native/Dockerfile` / `native/Apptainer.def`）。

### 1. 官方 release tarball（官方唯一分发，首选）

```bash
# 下载并解压到用户目录（无需 root，禁 /opt/biosoft 教学硬编码）
mkdir -p ~/software && cd ~/software
wget https://github.com/gatech-genemark/ProtHint/releases/download/v2.4.0/ProtHint-2.4.0.tar.gz
tar zxf ProtHint-2.4.0.tar.gz
# ln -s /path/to/ProtHint-2.4.0/bin/* /path/to/gth-1.7.3-Linux_x86_64-64bit/bin/
export PROTHINT_HOME=~/software/ProtHint-2.4.0
export PATH="$PROTHINT_HOME/bin:$PATH"
prothint.py --version   # 断言：2.4.0
```

> 一键安装直接运行 `bash native/install.sh`（默认部署到 `~/software/ProtHint-2.4.0` 并写 PATH；无 conda/binary 双路线，官方仅 tarball 一条路线，详见脚本头注）。

### 2. 运行依赖（官方未内置于 tarball 的部分）

* **Perl 模块**：`MCE::Mutex`、`threads`、`YAML`、`Math::Utils`、`Thread::Queue`（≥3.11，Debian bookworm 已满足）。Debian/Ubuntu 可直接 `apt-get install libmce-perl libyaml-perl libmath-utils-perl libthread-queue-perl`。
* **GeneMark-ES**（可选）：需自行下载授权版并解压到 `ProtHint/dependencies/GeneMarkES`；或用 `--geneMarkGtf` 提供预测结果跳过。
* **DIAMOND / Spaln**：**已内附**在 tarball 的 `dependencies/` 目录（预编译二进制），无需单独安装。
* 若在 BRAKER2 ET 模式中使用，还需 AUGUSTUS / bamtools / samtools / GenomeThreader(gth) / ncbi-rmblast / PASA 等（属 BRAKER 工具链，见对应模块）。

### 3. Conda / brew

**无**：ProtHint 未收录 bioconda（`prothint` 404），homebrew-core 与 brewsci/bio 亦无公式（2026-09 核实）→ 不提供 conda/brew 安装块；请用上面的官方 tarball 路线（或自建容器）。

### 4. Docker（自建兜底镜像）

官方无镜像，使用本模块自建配方（`apt 最小化 + 官方 release tarball`，禁 miniconda）：

```bash
# context 必须是 modules/ 层（携带 base.py 与软件级 meta.yaml）
docker build -t bioskills/prothint:2.4.0 -f modules/prothint/native/Dockerfile modules/
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/prothint:2.4.0 \
    genome.fasta proteins.fasta --workdir prothint_out --threads 8
```

### 5. Apptainer / Singularity（本地构建）

官方无预构建 sif（depot.galaxyproject.org 404），用本模块配方本地构建：

```bash
apptainer build prothint.sif modules/prothint/native/Apptainer.def
apptainer run -B $PWD:/data -H /data prothint.sif \
    /data/genome.fasta /data/proteins.fasta --workdir /data/prothint_out --threads 8
```

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（monkeypatch 脚本解析）；ProtHint 已安装时额外冒烟 --version
```

## 版本

* prothint 2.4.0（GitHub release `v2.4.0`：`ProtHint-2.4.0.tar.gz`）
* 构建路线：官方 release tarball（无官方容器/conda）→ 本地 `native/Dockerfile` / `native/Apptainer.def` 自建兜底
* 与本模块登记一致：`software_versions.prothint_native.prothint = 2.4.0`

## 容器与 Conda 链接

* **官方 release**：<https://github.com/gatech-genemark/ProtHint/releases/tag/v2.4.0>
* **Bioconda**：无（<https://api.anaconda.org/package/bioconda/prothint> 404，2026-09 核实）
* **Docker（官方）**：无；自建：`bioskills/prothint:2.4.0`（`native/Dockerfile`）
* **Singularity（官方）**：无（depot 404）；自建：`apptainer build prothint.sif native/Apptainer.def`
* 安装方式（本地）：`bash native/install.sh`（官方 release tarball → `~/software/ProtHint-2.4.0`）
