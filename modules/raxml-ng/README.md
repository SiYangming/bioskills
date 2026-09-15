# raxml-ng 软件模块

> 汇总说明：本 README 合并本模块各实现（仅 native 一路，`source_type: custom`）的用法；官方 nf-core 子模块与
> snakemake-wrappers 情况记录于此（不建目录，仅说明层）。安装方式见「环境安装」节，容器与 conda 环境信息
> 记录于文末。classic RAxML 见 `modules/raxml`。

***

## native 实现

# raxml-ng / native — 最大似然建树驱动（下一代）

RAxML-NG（[官网](https://cme.h-its.org/exelixis/web/software/raxml/index.html) ・
[amkozlov/raxml-ng](https://github.com/amkozlov/raxml-ng)，RAxML Next Generation，本模块登记 **2.0.3**）是
classic RAxML 的重写版最大似然系统发育建树工具：更快、更易用、更灵活，命令行统一为
`raxml-ng --<mode> + --msa/--model/--threads`（如 `--all` 一次完成 ML 搜索 + bootstrap + 模型选择；
`--search` 拓扑搜索；`--evaluate` 评估给定拓扑；`--parse` 解析比对）。它是 14.md「五、RAxML - 物种树构建 →
方法二/三」推荐的下一代建树工具。

本实现为自包含驱动（`source_type: custom`、`type: native`），二进制由**官方容器/conda**
（quay.io/biocontainers/raxml-ng / bioconda raxml-ng）提供，登记 **2.0.3**。

## 功能

| 子命令         | 命令                                                                             | 作用                              |
| ----------- | ------------------------------------------------------------------------------ | ------------------------------- |
| `all`       | `raxml-ng --all --msa <aln> --model <m> --threads <N> [--bs-trees <n>]`        | ML 搜索 + bootstrap + 模型选择（一次完成）  |
| `ml`        | `raxml-ng --ml --msa <aln> --model <m> --threads <N>`                          | ML 树搜索                         |
| `search`    | `raxml-ng --search --msa <aln> --model <m> --threads <N>`                      | 拓扑搜索                          |
| `evaluate`  | `raxml-ng --evaluate --msa <aln> --tree <tree> --model <m> --threads <N>`      | 在给定拓扑上评估似然                    |
| `parse`     | `raxml-ng --parse --msa <aln> --model <m>`                                     | 解析/压缩比对（产物 `<prefix>.raxml.rba`；位点被压缩时另出 `<prefix>.raxml.reduced.phy`） |
| `version`   | `raxml-ng --version`                                                           | 打印版本                           |

## 用法

```bash
# CLI 直跑
python main.py all      --msa msa.phy --model GTR+G --threads 8 --bs-trees 100
python main.py ml       --msa msa.phy --model GTR+G --threads 8
python main.py search   --msa msa.phy --model GTR+G --threads 8
python main.py evaluate --msa msa.phy --tree tree.nwk --model GTR+G --threads 8
python main.py parse    --msa msa.phy --model GTR+G

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（注入 `--threads`）。**RAxML-NG 为 CPU 密集工具**，
线程优先级 `--threads` > `per_subcommand_threads`（默认 8）> `default_cpus`。

## 实战示例：RAxML-NG 建树

RAxML-NG 与 classic RAxML 同为最大似然建树工具，命令风格更统一；**等价能力由 `native/main.py` 的 `all` /
`search` / `evaluate` / `parse` 子命令提供**（见上「用法」）。

### 1. 一步建树（ML + bootstrap + 模型选择）

```bash
mkdir -p raxml_ng && cd raxml_ng

# --all：ML 搜索 + 快速 bootstrap + 模型选择；--bs-trees 指定 bootstrap 重复数
raxml-ng --all --msa allSingleCopyOrthologsAlign.Codon.phy --model GTR+G \
    --threads 8 --bs-trees 100

# 输出文件：<prefix>.raxml.bestTree（最佳树）
#           <prefix>.raxml.bestModel（最佳模型）
#           <prefix>.raxml.support（带支持度的树）
# 驱动等价写法：
python ../modules/raxml-ng/native/main.py all --msa allSingleCopyOrthologsAlign.Codon.phy \
    --model GTR+G --threads 8 --bs-trees 100
```

### 2. 解析比对（送建树前，检查/压缩）

```bash
# --parse 同样要求 --model；产物为 <prefix>.raxml.rba（+ .raxml.log），位点被压缩时另出 .reduced.phy
raxml-ng --parse --msa allSingleCopyOrthologsAlign.Codon.phy --model GTR+G
```

### 3. 参数说明

| 参数              | 说明                                          |
| --------------- | ------------------------------------------- |
| `--all`         | ML 搜索 + bootstrap + 模型选择（一次完成）              |
| `--ml`          | ML 树搜索（给定模型）                                |
| `--search`      | 拓扑搜索                                        |
| `--evaluate`    | 在给定拓扑（`--tree`）上评估似然                         |
| `--parse`       | 解析/压缩比对                                     |
| `--msa`         | 输入比对（FASTA/Phylip）                          |
| `--model`       | 进化模型（`GTR+G` / `GTR+G4` / `LG+G`；all 可用 MFP+MERGE） |
| `--tree`        | evaluate 的输入树（Newick）                       |
| `--bs-trees`    | bootstrap 重复次数                              |
| `--threads`     | 线程数（驱动注入）                                   |

## 环境安装（官方预编译二进制包优先；官方源码编译并列保留）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；
main.py 驱动在宿主机跑。官方同时提供**预编译二进制包**与**源码归档**，两条官方路线均保留（预编译优先）。

### 1. 官方预编译二进制包（首选）

官方 GitHub release <https://github.com/amkozlov/raxml-ng/releases/tag/2.0.3> 提供预编译 zip：

```bash
mkdir -p ~/software/raxml-ng-2.0.3/bin && cd ~/software
# Linux x86_64：
wget https://github.com/amkozlov/raxml-ng/releases/download/2.0.3/raxml-ng_v2.0.3_linux_x86_64.zip
# macOS：
# wget https://github.com/amkozlov/raxml-ng/releases/download/2.0.3/raxml-ng_v2.0.3_macos.zip
unzip -q raxml-ng_v2.0.3_linux_x86_64.zip
install -m 0755 raxml-ng ~/software/raxml-ng-2.0.3/bin/raxml-ng
echo 'export PATH=$PATH:~/software/raxml-ng-2.0.3/bin' >> ~/.bashrc && source ~/.bashrc
raxml-ng --version       # 断言
```

> 一键安装也可直接运行 `native/install.sh`（现代规范：有 conda/mamba 时建 bioconda 环境 `raxml-ng`，
> 无 conda 时自动下载官方 release zip 到 `~/software/raxml-ng-<ver>` 并写 PATH；版本默认 2.0.3，与下方
> `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. 官方源码编译（并列保留）

官方源码归档：`raxml-ng_v2.0.3_source.zip`（release 资产）或
`https://github.com/amkozlov/raxml-ng/archive/refs/tags/2.0.3.tar.gz`（CMake 构建，依赖 coraxlib/terraphast）：

```bash
wget https://github.com/amkozlov/raxml-ng/releases/download/2.0.3/raxml-ng_v2.0.3_source.zip
unzip -q raxml-ng_v2.0.3_source.zip && cd raxml-ng_v2.0.3
mkdir build && cd build
cmake .. && make -j 4
raxml-ng --version       # 断言
```

### 3. Conda / brew（包管理器安装，备选）

```bash
mamba create -n raxml-ng-native -c conda-forge -c bioconda raxml-ng=2.0.3
conda activate raxml-ng-native
raxml-ng --version       # 断言
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap；brew 当前 2.0.3，与 meta 登记一致）
brew install raxml-ng
raxml-ng --version       # 断言
```

### 4. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/raxml-ng:2.0.3--h870a6a7_0
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/raxml-ng:2.0.3--h870a6a7_0 \
    raxml-ng --all --msa /data/allSingleCopyOrthologsAlign.Codon.phy --model GTR+G --threads 8 --bs-trees 100
```

### 5. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull raxml-ng.sif docker://depot.galaxyproject.org/singularity/raxml-ng:2.0.3--h870a6a7_0
apptainer run -B $PWD:/data -H /data raxml-ng.sif \
    raxml-ng --all --msa /data/msa.phy --model GTR+G --threads 8 --bs-trees 100
```

## 官方实现登记（不建目录，仅说明层）

### nf-core 官方模块（Nextflow，说明层）

nf-core 官方 `modules/nf-core/raxmlng/` **存在**（2026-09 在线核实，以官方在线目录为准），为**扁平模块**
（`environment.yml` + `main.nf` + `meta.yml` + `tests/`），并新增 namespaced 子模块 `raxmlng/search`：

| 模块                | environment.yml 关键 pin        | 作用（据 nf-core）                          |
| ----------------- | ---------------------------- | ------------------------------------- |
| `raxmlng`（扁平）     | bioconda::raxml-ng=1.2.2     | ML 建树（caller 提供固定模型字符串）                |
| `raxmlng/search`  | bioconda::raxml-ng=2.0.3     | ML 树搜索 + 内置模型选择（MOOSE，写 `.raxml.bestModel`） |

> ⚠️ 本模块未建 `nextflow/` 目录：组装 Nextflow DSL2 流程时执行
> `nf modules install nf-core raxmlng`（或 `raxmlng/search`）（安装到项目自身 `modules/nf-core/`，不要直接
> include 本仓库文件），随后 `include { RAXMLNG } from '../modules/nf-core/raxmlng/main'`。

### snakemake-wrappers（官方无）

官方**无** `bio/raxml-ng`（亦无 `bio/raxmlng`；2026-09 核实返回 **404**）→ 不建目录；Snakemake 场景请用
本模块 `native/` 兜底。

## 测试

```bash
cd modules/raxml-ng/native && bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema）+ argv 构造断言（all/ml/search/
# evaluate/parse、--tree、线程优先级）必跑；PATH 含 raxml-ng 时追加 --parse 真实冒烟（断言生成 .raxml.rba / .raxml.log）。
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/raxml-ng>（现行 latest 2.0.3，与 native 登记一致）

* **Docker**：`docker pull quay.io/biocontainers/raxml-ng:2.0.3--h870a6a7_0`（bioconda 自动构建；tag 以 quay /
  depot.galaxyproject.org 页面为准）

* **Singularity**：<https://depot.galaxyproject.org/singularity/raxml-ng%3A2.0.3--h870a6a7_0>

* 安装方式（本地）：`mamba create -n raxml-ng -c conda-forge -c bioconda raxml-ng=2.0.3`（或
  `brew install raxml-ng`；或官方预编译 zip / 官方源码编译）

* 上游：<https://github.com/amkozlov/raxml-ng>（源码与 release）·
  <https://cme.h-its.org/exelixis/web/software/raxml/index.html>（官网）

## 版本

* raxml-ng **2.0.3**（bioconda::raxml-ng=2.0.3；官方容器 tag `2.0.3--h870a6a7_0`；官方预编译 zip 与源码
  zip 均提供）

* 许可：AGPL-3.0-or-later（RAxML-NG README 与源码 LICENSE；bioconda raxml-ng 包元数据）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/raxml-ng / depot.galaxyproject.org；本地不再自建容器）；
  官方另有预编译 zip 与源码 zip（两条官方路线均保留）

* 官方层：nf-core 有 `modules/nf-core/raxmlng`（扁平，pin 1.2.2）与 `raxmlng/search`（pin 2.0.3）；
  snakemake-wrappers 无 wrapper（均 2026-09 核实）
