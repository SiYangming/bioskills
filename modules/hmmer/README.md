# hmmer 软件模块（HMMER · 3.x 现行版 + 2.x 遗留版）

> 汇总说明：本模块覆盖**同一软件（HMMER）的两条版本线**——HMMER 3.x 现行版（主，`native/`，`source_type: custom`、`type: native`）与 HMMER 2.x 遗留版（`native2/`，`source_type: custom`、`type: native`）；本 README 合并两实现的用法。官方 nf-core 子模块与 snakemake-wrappers 情况记录于此（不建目录，仅说明层）。安装方式见「环境安装」节，容器与 conda 环境信息记录于文末；两条版本线差异见文末「版本差异声明」。

***

## HMMER 3.x 现行版（native 实现）

# hmmer / native — profile HMM 建库与序列检索驱动

HMMER（官网 <http://hmmer.org/>，上游 [EddyRivasLab/hmmer](https://github.com/EddyRivasLab/hmmer)）是基于 **profile hidden Markov model（profile HMM）** 做序列同源检索 / 结构域注释 / 序列谱建库的经典工具套件：`hmmbuild` 由多序列比对（MSA）训练 profile HMM，`hmmpress` 把 HMM 库按压成 `.h3m/.h3i/.h3f/.h3p` 索引便于快速检索，`hmmsearch` 用 HMM 检索蛋白序列库、`hmmscan` 用序列检索 HMM 库，另有 `phmmer`/`jackhmmer`/`nhmmer` 等同套件命令。它是生物信息教学课件（序列谱 / 结构域注释）与 **antiSMASH（新版）** 等工具的常用**运行依赖**（依赖方模块只需指向本模块安装文档，不单独分发 HMMER）。

本实现为自包含驱动（`source_type: custom`、`type: native`），二进制由**官方容器/conda**（quay.io/biocontainers/hmmer / bioconda hmmer）提供，三个子命令分别包装官方三个入口：

## 能力

| 子命令         | 包装命令                                                       | 作用                                                       | 线程              |
| ----------- | ---------------------------------------------------------- | -------------------------------------------------------- | --------------- |
| `hmmbuild`  | `hmmbuild [options] <hmmfile_out> <msafile>`                | 由多序列比对（MSA）训练 profile HMM（HMMER3/f 格式）                     | ✅ 默认 4（注入 `--cpu`） |
| `hmmpress`  | `hmmpress [-f] <hmmfile>`                                   | 把 HMM 库按压为 `<hmm>.h3f/.h3i/.h3m/.h3p` 索引（供 hmmscan 快速检索）  | 无并行（忽略 `--threads`） |
| `hmmsearch` | `hmmsearch [options] <hmmfile> <seqdb>`                     | 用 profile HMM 检索蛋白序列库（`--tblout` 表格、`-o` 主输出、`-E` 阈值）      | ✅ 默认 4（注入 `--cpu`） |

## 用法

```bash
# CLI 直跑（教学典型链路：MSA → HMM → 按压 → 检索）
python main.py hmmbuild family.hmm family.sto -n teach_family --threads 4   # MSA 训练 HMM
python main.py hmmpress family.hmm                                         # 按压生成 .h3f/.h3i/.h3m/.h3p
python main.py hmmsearch --hmm family.hmm proteins.fa \
    --tblout hits.tbl -E 10 -o search.out --threads 4                      # 检索序列库（-o 缺省 stdout）

# 只想要可解析表格（--tblout），主输出仍走 stdout（可 > 重定向）
python main.py hmmsearch --hmm family.hmm proteins.fa --tblout hits.tbl -E 1e-5

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--tmpdir` 同时注入 `TMPDIR` 环境变量）；`--threads` 映射为 HMMER 的 `--cpu N`（`hmmpress` 无并行，参数被接受但忽略）。

## 实战示例：由 MSA 建谱并检索蛋白序列库（教学典型链路）

序列谱分析教学典型命令为 `hmmbuild <hmm> <msa>` → `hmmpress <hmm>` → `hmmsearch <hmm> <seqdb>`；以下为原生 CLI 的典型批量用法，**等价能力由 `native/main.py` 的 `hmmbuild` / `hmmpress` / `hmmsearch` 子命令提供**（见上「用法」）。

### 1. 由多序列比对训练 profile HMM（hmmbuild）

```bash
mkdir -p hmmer_out && cd hmmer_out

# 单家族：MSA（Stockholm/afa/clustal 均可，自动判定氨基酸/核酸字母表）→ HMM
hmmbuild -n teach_family family.hmm ../family.sto
# -o 把汇总结构（序列数目、平均长度等）写入文件，默认 stdout
hmmbuild --cpu 4 -o family.hmmbuild.log family.hmm ../family.sto

# 多样本批量（每个 MSA 一个 HMM）
for sto in ../msa/*.sto; do
    name=$(basename "$sto" .sto)
    hmmbuild --cpu 4 ${name}.hmm "$sto"
done
```

### 2. 按压 HMM 库（hmmpress；hmmscan 前置）

```bash
# 生成 <hmm>.h3f / .h3i / .h3m / .h3p（供 hmmscan 快速检索；hmmsearch 不要求按压）
hmmpress family.hmm
hmmpress -f family.hmm     # -f 强制覆盖已有按压文件
```

### 3. 用 HMM 检索蛋白序列库（hmmsearch）

```bash
# 单库检索；-E 报告阈值（默认 10.0），--tblout 出每命中一行的可解析表格，-o 主输出
hmmsearch --cpu 4 -E 1e-5 --tblout hits.tbl -o search.out family.hmm proteins.fa

# 多样本批量（每个序列库一份表格）
for fa in ../db/*.faa; do
    name=$(basename "$fa" .faa)
    hmmsearch --cpu 4 --tblout ${name}.hits.tbl -o ${name}.search.out family.hmm "$fa"
done

# 取表格中的命中行（跳过 # 注释行）
grep -v '^#' hits.tbl | awk '{print $1, $5, $6}' | head
```

### 4. 参数说明

| 参数                | 说明                                                                   |
| ----------------- | -------------------------------------------------------------------- |
| `-n <s>`（hmmbuild）  | HMM 命名（缺省取 MSA 名）                                                     |
| `-o <f>`          | hmmbuild：汇总结构输出文件（缺省 stdout）；hmmsearch：主输出文件（缺省 stdout）               |
| `--tblout <f>`（hmmsearch） | 每命中一行的可解析表格（首行注释 `# target name …`）                                  |
| `-E <x>`（hmmsearch） | 报告序列的 E-value 阈值（HMMER 3.4 默认 10.0）                                   |
| `-f`（hmmpress）    | 强制覆盖已存在的 `.h3f/.h3i/.h3m/.h3p` 按压文件                                   |
| `--threads N`     | 线程数（本驱动由 `--threads` 注入 `--cpu N`；`hmmpress` 忽略）                        |
| `--domtblout` / `-A` / `--cut_ga` 等 | 其它常用项经 `--extra-args` 透传（高级用法，慎用）                                    |

## HMMER 2.x 遗留版（native2 实现）

# hmmer / native2 — HMMER 2.x legacy profile HMM 驱动

HMMER 2.x 是基于 **profile hidden Markov model（profile HMM）** 的序列同源检索 / 序列谱建库经典工具套件（2003 年前后的**遗留版本**）：`hmmbuild` 由多序列比对（MSA）训练 profile HMM、`hmmsearch` 用 HMM 检索序列库，另含 `hmmpfam` / `hmmalign` / `hmmcalibrate` / `hmmemit` / `hmmfetch` / `hmmindex` 等同套件命令。

⚠️ **这是 HMMER 2.x 遗留版，不是 HMMER 3.x**：2.x 的 CLI、二进制命名与输出格式均与 3.x 不同（详见文末「版本差异声明」）。HMMER 2.x 是 **RNAmmer 1.2**（HMM 法 rRNA 基因预测，<https://services.healthtech.dtu.dk/services/RNAmmer-1.2/>，模块见 `modules/rnammer`）与**旧版 antiSMASH** 等工具的**必需运行依赖**（这些工具对 HMMER 版本敏感，须用 2.x）。**HMMER 3.x 用法见上「HMMER 3.x 现行版（native 实现）」章节。**

本实现为自包含驱动（`source_type: custom`、`type: native`，位于本模块 `native2/`），二进制由**官方容器/conda**（quay.io/biocontainers/hmmer2 / bioconda hmmer2）或官方源码自编译提供。

### 能力

| 子命令       | 包装命令                                                                 | 作用                                     | 线程 |
| --------- | -------------------------------------------------------------------- | -------------------------------------- | -- |
| `hmmbuild` | `hmmbuild [options] <hmmfile> <alignfile>`（`-n` 命名、`-F` 覆盖）           | 由多序列比对（MSA）训练 HMMER2 profile HMM        | 协议位（HMMER2 hmmbuild 无并行，不注入） |
| `hmmsearch` | `hmmsearch [options] <hmmfile> <seqfile>`（`-E`/`-T` 阈值、`-A` 比对条数、`--cpu N`） | 用 profile HMM 检索序列库（输出走 stdout；**2.x 无 `--tblout`**） | ✅ 默认 4（注入 `--cpu`） |

### 用法

（以下命令在本模块 `native2/` 目录下执行。）

```bash
# 建谱：MSA（Stockholm/SELEX/afa…）→ HMMER2 profile HMM
python main.py hmmbuild family.hmm family.sto -n teach_family
python main.py hmmbuild family.hmm family.sto -F          # -F 覆盖已存在的 HMM

# 搜索：profile HMM 检索序列库（HMMER2 无 --tblout，主输出走 stdout，可直接重定向）
python main.py hmmsearch family.hmm proteins.fa -E 10 --threads 4
python main.py hmmsearch family.hmm proteins.fa -T 5 -A 0 --threads 4 > hits.txt

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--tmpdir` 注入 `TMPDIR` 环境变量）。`--threads` 对 `hmmsearch` 注入 `--cpu N`；**HMMER2 `hmmbuild` 无线程参数**，`--threads` 仅作协议位不注入。

> 💡 **二进制命名（关键）**：**bioconda hmmer2 包内所有工具带 `2` 后缀**——`hmmbuild2` / `hmmsearch2` / `hmmalign2` / `hmmcalibrate2` / `hmmconvert2` / `hmmemit2` / `hmmfetch2` / `hmmindex2` / `hmmpfam2`（bioconda recipe 用 `Makefile.in.patch` 把安装名改为 `<prog>2`，以避免与 HMMER3 冲突）；上游源码自编译为**无后缀**（`hmmbuild` / `hmmsearch`），Debian 包为 **`hmm2` 前缀**（`hmm2build` / `hmm2search`）。本驱动按**多候选名探测**：`hmmbuild2→hmmbuild→hmm2build`、`hmmsearch2→hmmsearch→hmm2search`，三条命名均可用（并校验 `-h` 输出确为 `HMMER 2.`，避免误用同名的 HMMER3）。

> 也可跳过 main.py 直接调用原生 CLI（注意按安装来源选用正确二进制名）：
>
> ```bash
> hmmbuild2 family.hmm family.sto -n teach_family       # bioconda 命名
> hmmsearch2 family.hmm proteins.fa -E 10 --cpu 4        # HMMER2 无 --tblout
> ```

### 实战示例：RNAmmer / 旧版 antiSMASH 场景（HMMER2 遗留链路）

HMMER 2.x 的现代主要用途是**为依赖它的遗留工具提供 HMM 引擎**——RNAmmer 1.2 的 rRNA 预测内部调用 HMMER2 `hmmsearch`（官网 <https://services.healthtech.dtu.dk/services/RNAmmer-1.2/>，安装见 `modules/rnammer`），旧版 antiSMASH 亦需要 2.x。以下为 HMMER2 原生 CLI 的典型用法；**等价能力由 `native2/main.py` 的 `hmmbuild` / `hmmsearch` 子命令提供**（先 CLI 后 main.py，见上「用法」）。

#### 1. 从 MSA 训练 profile HMM（hmmbuild）

```bash
mkdir -p hmmer2_out && cd hmmer2_out
# bioconda 命名用 hmmbuild2；源码自编译用 hmmbuild
hmmbuild2 rRNA_family.hmm rRNA_family.sto -n rRNA_family
```

#### 2. 用 HMM 检索序列库（hmmsearch）

```bash
# HMMER2 无 --tblout：报告直接写 stdout，用重定向落盘
hmmsearch2 --cpu 4 -E 10 rRNA_family.hmm genome_proteins.fa > rRNA_family.hits.txt
```

#### 3. 批量为多个序列库检索（bash 循环）

```bash
for fa in proteomes/*.fa; do
    name=$(basename "$fa" .fa)
    hmmsearch2 --cpu 4 -E 10 rRNA_family.hmm "$fa" > "${name}.hmmsearch.txt"
done
```

#### 4. 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `-n <s>` | `hmmbuild`：给 HMM 命名（缺省取 MSA 名） |
| `-F` | `hmmbuild`：强制覆盖已存在的 HMM 文件（否则 HMMER 拒绝覆盖） |
| `-E <x>` | `hmmsearch`：序列 E-value 阈值（HMMER2 默认 10.0） |
| `-T <x>` | `hmmsearch`：序列位分阈值（默认负无穷，仅由 `-E` 控制） |
| `-A <n>` | `hmmsearch`：限制比对输出的最优结构域条数（`-A0` 关闭比对输出） |
| `--cpu <n>` | `hmmsearch`：CPU 并行数（HMMER2 专家选项；本驱动由 `--threads` 注入） |
| `--threads` | 协议位：`hmmsearch` 注入 `--cpu N`；`hmmbuild`（2.x 无并行）不注入 |
| `--tmpdir` | 协议位：注入 `TMPDIR` 环境变量 |

> 💡 **HMMER2 无 `--tblout`**（表格输出是 HMMER3 新增）；需要结构化结果时解析 stdout，或改用本模块 HMMER 3.x（`native/`）。
> 桥接句：以上 CLI 用法等价于 `python main.py hmmbuild <hmmfile> <alignfile> -n <name>` 与 `python main.py hmmsearch <hmmfile> <seqfile> -E <x> --threads <n>`。

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制（镜像含整套 HMMER 3.4 命令与 gsl/openmpi 等依赖）；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n hmmer-native -c conda-forge -c bioconda hmmer=3.4
conda activate hmmer-native
hmmsearch -h 2>&1 | head -n 2     # 断言：打印 "HMMER 3.4 (Aug 2023)"
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
# brew 当前 hmmer 3.4，与 meta 登记 3.4 一致（desc: Build profile HMMs and scan against sequence databases）
brew install hmmer
hmmsearch -h 2>&1 | head -n 2     # 断言
```

> 一键安装可直接 `bash native/install.sh`（auto：有 conda/mamba 走 bioconda；否则拉官方源码归档到用户前缀自编译）。

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/hmmer:3.4--h7d74f8d_5
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/hmmer:3.4--h7d74f8d_5 \
    hmmsearch --cpu 4 --tblout /data/hits.tbl -o /data/search.out \
    /data/family.hmm /data/proteins.fa
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull hmmer.sif docker://depot.galaxyproject.org/singularity/hmmer:3.4--h7d74f8d_5
apptainer run -B $PWD:/data -H /data hmmer.sif \
    hmmbuild --cpu 4 /data/family.hmm /data/family.sto
```

### 4. 二进制包安装（官方 release 源码归档，无预编译资产）

HMMER 为 **C 源码程序**，官方**无预编译二进制资产**（bioconda / homebrew 亦从源码构建）——教学/常规使用请走上方 Conda / brew 或官方容器；确需源码路线时拉对应 tag 源码归档到用户前缀自编译：

**官网下载页**：<http://hmmer.org/download.html> · **源码直链**：<http://eddylab.org/software/hmmer/hmmer-3.4.tar.gz>

**GitHub**：<https://github.com/EddyRivasLab/hmmer>（release tag `hmmer-3.4`，与 `software_versions` 对齐）

```bash
wget http://eddylab.org/software/hmmer/hmmer-3.4.tar.gz -P ~/software/
tar zxf ~/software/hmmer-3.4.tar.gz -C ~/software/     # -> ~/software/hmmer-3.4/
cd ~/software/hmmer-3.4
./configure --prefix=$HOME/software/hmmer-3.4
make && make install                                   # 需 C 编译器（gcc/clang）与 make
echo 'export PATH=$PATH:~/software/hmmer-3.4/bin' >> ~/.bashrc && source ~/.bashrc
hmmsearch -h 2>&1 | head -n 2                          # 断言：打印 "HMMER 3.4 (Aug 2023)"
```

### 5. HMMER 2.x 遗留版安装（native2 实现）

HMMER 2.x 遗留版同样由官方镜像/conda 覆盖（bioconda `hmmer2` → quay.io/biocontainers/hmmer2 → depot.galaxyproject.org）；镜像/tag 与 3.x 不同，安装后二进制带 `2` 后缀（`hmmsearch2`/`hmmbuild2`）。

```bash
# (1) Conda（bioconda，推荐）
mamba create -n hmmer2 -c conda-forge -c bioconda hmmer2=2.3.2
conda activate hmmer2
hmmsearch2 -h 2>&1 | head -n1    # 断言：HMMER 2.3.2
hmmbuild2 -h 2>&1 | head -n1     # 断言
# 或一键：bash native2/install.sh   （auto：有 conda/mamba 走 bioconda；否则官方源码自编译到用户前缀）

# (2) Docker（官方镜像；-u $(id -u):$(id -g) 必带，否则产物归 root）
docker pull quay.io/biocontainers/hmmer2:2.3.2--h87e0c26_12
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/hmmer2:2.3.2--h87e0c26_12 \
    hmmsearch2 --cpu 4 -E 10 family.hmm proteins.fa > hits.txt

# (3) Apptainer / Singularity（depot 预构建 sif 直拉，无需本地从 docker 转换）
apptainer pull hmmer2.sif docker://depot.galaxyproject.org/singularity/hmmer2:2.3.2--h87e0c26_12

# (4) 官方源码归档自编译（无现代预编译二进制；产出无后缀二进制 hmmsearch/hmmbuild，与 HMMER3 同名，注意 PATH 顺序）
mkdir -p ~/software && cd ~/software
wget http://eddylab.org/software/hmmer/2.3.2/hmmer-2.3.2.tar.gz
tar zxf hmmer-2.3.2.tar.gz && cd hmmer-2.3.2
./configure --enable-threads --prefix=$HOME/software/hmmer2-2.3.2
make && make install
export PATH="$HOME/software/hmmer2-2.3.2/bin:$PATH"
hmmsearch -h 2>&1 | head -n1     # 断言：HMMER 2.3.2（源码自编译产出无后缀二进制）
```

> **Homebrew 无可登记公式**：homebrew-core（`formulae.brew.sh/api/formula/hmmer2.json`）与 brewsci/bio（`.../Formula/hmmer2.rb`）两源均 **404**（2026-09 核实）——homebrew-core 的 `hmmer` 公式是 **HMMER3**，非 HMMER2；故 HMMER 2.x 仅 conda / 官方容器 / 源码自编译，或本仓库 `native2/install.sh`（等价上述第 (1)/(4) 条的用户级版本，含 sha256 校验 + PATH 写入）。

## 测试

```bash
# HMMER 3.x（native）
cd modules/hmmer/native && bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema）与子命令参数契约
# （hmmbuild/hmmpress/hmmsearch 均含 --threads/--tmpdir）必跑；PATH 含 hmmer 时追加真跑最小链路
# （合成蛋白 MSA + 序列库 → hmmbuild → hmmpress 断言 .h3f/.h3i/.h3m/.h3p → hmmsearch 断言
#   --tblout/-o 产物）；无 hmmer 时 [SKIP]。

# HMMER 2.x 遗留版（native2）
cd modules/hmmer/native2 && bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema）与子命令 --help 契约必跑；
# 按多候选名探测 HMMER2 二进制（hmmbuild2/hmmbuild/hmm2build、hmmsearch2/hmmsearch/hmm2search），
# PATH 命中 HMMER 2.x 时追加真跑最小链路（hmmbuild 建谱 → 断言 HMMER 头 → hmmsearch 检索）；
# 无 HMMER2 时 [SKIP]（仅跑自省/契约）。
```

## 版本

* hmmer **3.4**（HMMER 3.x 现行版，默认实现；上游 2023-08 发布；bioconda 现行 `hmmer=3.4`，linux-64 build `h7d74f8d_5`，2026-08 起发布）

* hmmer2 **2.3.2**（HMMER 2.x 遗留版，`native2/`；bioconda 现行/唯一版本，linux-64 build `h87e0c26_12`，2017-05 起发布；二进制带 `2` 后缀）

* 构建路线：官方镜像/conda 提供（3.x → quay.io/biocontainers/hmmer；2.x → quay.io/biocontainers/hmmer2；depot.galaxyproject.org；本地不再自建容器）

* 许可：3.x 为 **BSD-3-Clause**；2.x 遗留版为 **GPL-2.0-or-later**（版本差异，见下）

* nf-core 官方子模块与 snakemake-wrappers 当前均 pin hmmer=**3.4**（与 native 一致）；HMMER2 官方层均无（见下「版本差异声明」与官方登记）

***

## 官方实现登记（不建目录，仅说明层）

### nf-core 官方模块（Nextflow，说明层）

nf-core 官方 `modules/nf-core/hmmer/` **存在**（多子模块结构；2026-09 在线核实，以官方在线目录为准）：`eslalimask`、`eslalipid`、`eslreformat`、`eslsfetch`、`eslsfetchindex`、`hmmalign`、`hmmbuild`、`hmmemit`、`hmmfetch`、`hmmlogo`、`hmmpress`、`hmmrank`、`hmmsearch`、`hmmstat`、`jackhmmer`（共 **15** 个子模块，各子模块 `environment.yml` 均 pin `bioconda::hmmer=3.4`）。

| 子模块（节选）    | environment.yml pin      | 作用（据 nf-core meta）                            |
| ---------- | ------------------------ | ------------------------------------------- |
| `hmmbuild` | bioconda::hmmer=3.4      | MSA（Stockholm）→ profile HMM                  |
| `hmmpress` | bioconda::hmmer=3.4      | HMM 库 → `.h3f/.h3i/.h3m/.h3p` 按压索引（hmmscan 前置） |
| `hmmsearch`| bioconda::hmmer=3.4      | HMM 检索蛋白序列库 → 表格 / 主输出                       |
| `jackhmmer`| bioconda::hmmer=3.4      | 迭代式 jackhmmer 检索                            |

> ⚠️ 本模块未建 `nextflow/` 目录：组装 Nextflow DSL2 流程时执行
> `nf modules install nf-core hmmer hmmbuild hmmpress hmmsearch …`（安装到项目自身 `modules/nf-core/`，不要直接 include 本仓库文件），随后：
>
> ```nextflow
> include { HMMER_HMMSEARCH } from '../modules/nf-core/hmmer/hmmsearch/main'
> ```
>
> 抓取命令：`curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/hmmer | python3 -c "import json,sys; [print(x['name']) for x in json.load(sys.stdin)]"`

### snakemake-wrappers（官方存在，子目录 wrapper）

官方 snakemake-wrappers **有** `bio/hmmer`（**子目录 wrapper**：`hmmbuild` / `hmmpress` / `hmmscan` / `hmmsearch` / `jackhmmer`，各含 `wrapper.py` + `environment.yaml` + `meta.yaml` + `test/`；2026-09 在线核实，v9.17.1 tag 含该 wrapper；`environment.yaml` pin `hmmer=3.4`）。params 契约（据各 `wrapper.py`）：

| wrapper  | 输入 / 输出 / 参数契约                                                                                     |
| -------- | --------------------------------------------------------------------------------------------------------- |
| `hmmbuild`  | `input`（MSA 单文件）/ `output`（HMM，单个）；`params.extra`；`threads`→`--cpu`                                |
| `hmmpress`  | `input`（HMM 单文件，自动 `-f` 覆盖）；无额外参数                                                              |
| `hmmsearch` | `input.profile`（`.hmm`，可按压后 `.h3m`）+ `input.fasta`；`output.outfile`/`tblout`/`domtblout`/`alignment_hits` 可选；`params.evalue_threshold`（默认 1e-5）或 `params.score_threshold`（用 `-T`，与前者互斥）；`params.extra`；`threads`→`--cpu` |

可直接粘贴的规则示例：

```python
rule hmmer_hmmsearch:
    input:
        profile="family.hmm",
        fasta="proteins.fa",
    output:
        outfile="search.out",
        tblout="hits.tbl",
    params:
        evalue_threshold=1e-5,       # 或 score_threshold（互斥）
        extra="",                    # 如 "--domtblout hits.domtbl -A hits.sto"
    threads: 4
    wrapper: "v9.17.1/bio/hmmer/hmmsearch"
```

> ⚠️ 运行时靠 Snakemake 在线解析 `wrapper:` 句柄（`v9.17.1/bio/hmmer/<sub>`），不要把本地示例当 wrapper_path；本模块未建 `snakemake/` 目录。

### HMMER 2.x 官方层（nf-core / snakemake-wrappers 均无，2026-09 核实 404）

HMMER 2.x 遗留版**无官方 nf-core 模块与 snakemake-wrappers**：

* nf-core 官方**无** `modules/nf-core/hmmer2`（2026-09 在线核实 404；nf-core 仅登记 HMMER3 的 `modules/nf-core/hmmer`）。抓取：`curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/hmmer2` → `{"message":"Not Found","status":"404"}`。Nextflow 场景直接调用 `native2/main.py` 兜底。
* snakemake-wrappers 官方**无** `bio/hmmer2`（2026-09 在线核实 404；`bio/` 仅有 HMMER3 的 `bio/hmmer`）。抓取：`curl -s https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/hmmer2` → 404。Snakemake 场景以 `native2/` 宿主机驱动兜底。

> 本模块未建 `nextflow/`、`snakemake/` 目录；HMMER2 无官方引擎层，两引擎场景均由 `native2/` 驱动兜底。

## 版本差异声明（两条版本线 + 各引擎实现）

| 实现                      | 版本行     | 版本      | 来源 / 说明                                                                        |
| ----------------------- | ------- | ------- | ------------------------------------------------------------------------------ |
| `hmmer_native`（native/）   | HMMER 3.x | **3.4** | official biocontainer：quay.io/biocontainers/hmmer:3.4--h7d74f8d\_5 / bioconda hmmer=3.4；默认实现 |
| `hmmer2_native`（native2/）| HMMER 2.x | **2.3.2** | official biocontainer：quay.io/biocontainers/hmmer2:2.3.2--h87e0c26\_12 / bioconda hmmer2=2.3.2 |
| nf-core master          | HMMER 3.x | 3.4     | bioconda::hmmer=3.4（modules/nf-core/hmmer/*/environment.yml，15 个子模块）；HMMER2 官方无（404）        |
| snakemake-wrappers      | HMMER 3.x | 3.4     | bioconda hmmer=3.4（bio/hmmer/*/environment.yaml，5 个子目录 wrapper；v9.17.1 tag）；HMMER2 官方无（404）  |

**HMMER 3.x vs 2.x 版本差异（关键）**：

| 维度 | HMMER **3.x**（`native/`，默认实现） | HMMER **2.x** 遗留版（`native2/`） |
| ---- | -------------------------------- | ------------------------------ |
| 版本 | 3.4 | 2.3.2 |
| 许可 | **BSD-3-Clause** | **GPL-2.0-or-later**（与 3.x 不同） |
| 二进制命名 | `hmmbuild` / `hmmpress` / `hmmsearch` 等（无后缀） | bioconda 带 **`2` 后缀**（`hmmbuild2`/`hmmsearch2`）；源码自编译无后缀；Debian `hmm2` 前缀 |
| 子命令 | `hmmbuild` / `hmmpress` / `hmmsearch`（+ hmmscan/phmmer/jackhmmer 等） | `hmmbuild` / `hmmsearch`（+ hmmpfam/hmmalign/hmmcalibrate…） |
| 表格输出 | `--tblout <f>`（每命中一行） | **无 `--tblout`**（报告走 stdout，需自行解析） |
| 建库按压 | `hmmpress` → `.h3f/.h3i/.h3m/.h3p` | **无 `hmmpress`**（2.x 无按压索引流程） |
| 并行（建谱） | `hmmbuild --cpu N` | `hmmbuild` **无并行**（`hmmsearch` 支持 `--cpu N`） |
| 典型场景 | 新项目一律优先；新版 antiSMASH、通用 HMM 建库检索 | 复现 RNAmmer 1.2 / 旧版 antiSMASH 等依赖 HMMER2 的遗留流程 |

> 3.x 三路（native / nf-core / snakemake-wrappers）版本一致（hmmer=3.4），可直接跨引擎迁移；后续任一渠道 bump（如 bioconda 升级 build）时同步刷新本表。
> 选择建议：新场景优先 HMMER 3.x（`native/`）；仅当依赖方（RNAmmer 1.2、旧版 antiSMASH 等）明确要求 HMMER 2.x 时才用 `native2/`。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# hmmer native Conda 环境配方（HMMER 3.x，HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 hmmer-native.yml 后 mamba env create -f hmmer-native.yml；
# 在线推荐上方 mamba create 直装命令。hmmer=3.4 会把 gsl/openmpi 等运行依赖一并装入。
name: hmmer-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - hmmer=3.4
  - pyyaml>=6.0
```

```yaml
# hmmer2 native2 Conda 环境配方（HMMER 2.x 遗留版，HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 hmmer2-native.yml 后 mamba env create -f hmmer2-native.yml；在线推荐上方 mamba create 直装命令。
name: hmmer2-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - hmmer2=2.3.2          # 二进制带 2 后缀（hmmsearch2/hmmbuild2）
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：3.x <https://anaconda.org/bioconda/hmmer> · 2.x 遗留版 <https://anaconda.org/bioconda/hmmer2>

* **Docker**：3.x `docker pull quay.io/biocontainers/hmmer:3.4--h7d74f8d_5`；2.x `docker pull quay.io/biocontainers/hmmer2:2.3.2--h87e0c26_12`（bioconda 自动构建；tag 以 quay / depot.galaxyproject.org 页面为准）

* **Singularity**：3.x <https://depot.galaxyproject.org/singularity/hmmer%3A3.4--h7d74f8d_5>；2.x <https://depot.galaxyproject.org/singularity/hmmer2%3A2.3.2--h87e0c26_12>

* 安装方式（本地）：3.x `mamba create -n hmmer-native -c conda-forge -c bioconda hmmer=3.4`（或 `brew install hmmer`）；2.x `mamba create -n hmmer2 -c conda-forge -c bioconda hmmer2=2.3.2`（或 `bash native2/install.sh`）

* 上游 GitHub：<https://github.com/EddyRivasLab/hmmer>（release 为源码 tag 归档）· 官网：<http://hmmer.org/>（源码下载页 <http://hmmer.org/download.html>）· HMMER 2.x 源码归档 <http://eddylab.org/software/hmmer/2.3.2/hmmer-2.3.2.tar.gz>
