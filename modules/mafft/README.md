# mafft 软件模块（多序列比对）

> 汇总说明：本 README 合并本模块各实现（仅 native 一路，`source_type: custom`）的用法；官方 nf-core 子模块与 snakemake-wrappers 情况记录于此（不建目录，仅说明层）。安装方式见「环境安装」节，容器与 conda 环境信息记录于文末。

***

## native 实现

# mafft / native — 多序列比对驱动

MAFFT（[mafft.cbrc.jp](https://mafft.cbrc.jp/alignment/software/)，Multiple Alignment using Fast Fourier Transform）是**多序列比对（MSA）的行业标准工具**：以快速傅里叶变换加速的渐进式/迭代精化算法，把多条核酸或氨基酸序列**比对为等长比对**（默认 FASTA，`--clustalout` 可切 clustal），支持 `--auto`（按序列数与长度自动选择策略）与 `linsi / einsi / ginsi` 等高精度模式。它是 **RepeatModeler 的 LTR 结构流程**（经 LTR_retriever 调用）与**通用基因/注释流程**的常见依赖，也常用于 rRNA/基因序列集比对与进化树构建的前置步骤——**依赖方文档只需指向本模块「环境安装」小节即可复用其安装方式**。

本实现为自包含驱动（`source_type: custom`、`type: native`），二进制由**官方容器/conda**（quay.io/biocontainers/mafft / bioconda mafft）提供；两个子命令分别包装官方 `mafft` 主程序：

## 能力

| 子命令       | 包装命令                                                                 | 作用                                                       | 线程                     |
| --------- | -------------------------------------------------------------------- | -------------------------------------------------------- | ---------------------- |
| `align`   | `mafft --thread N [--auto \| <linsi/einsi/ginsi 组合>] input.fa`（结果走 stdout） | 多序列比对：输入 FASTA → **等长比对 FASTA**（缺省 stdout，`-o` 写文件）      | ✅ 默认 8（注入 `--thread`）  |
| `version` | `mafft --version`                                                    | 打印 MAFFT 版本信息（stdout）                                     | 接受 `--threads`，不注入     |

## 用法

```bash
# CLI 直跑（教学/常规链路；mafft 本体无 -o，-o 由驱动把捕获的 stdout 写盘）
python main.py align input.fa --threads 8                       # 默认 --auto，结果 FASTA 走 stdout
python main.py align input.fa --threads 8 -o aligned.fa          # 写文件
python main.py align -i input.fa -o aligned.fa --threads 8       # -i/--input 与位置参数等价
python main.py align input.fa --method linsi --threads 8 -o ali.fa      # 高精度 L-INS-i
python main.py align input.fa --method ginsi --extra-args "--reorder" -o ali.fa
python main.py version                                          # 打印 mafft --version

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖（`--tmpdir` 同时注入 `TMPDIR` 环境变量）。

> 💡 **参数注**：MAFFT 的线程参数是 **`--thread N`（单数，不是 --threads）**——驱动对外的运行期选项仍叫 `--threads`，构建命令行时自动翻译为 `--thread`。MAFFT 输出**默认按 60 列换行**（多行 FASTA），下游解析请按记录拼接序列行。

> 💡 **依赖语境**：MAFFT 是 RepeatModeler（LTR 结构流程，经 LTR_retriever 调用）等流程的依赖；这些流程的安装文档指向本模块「环境安装」即可，本模块不承载它们的其它依赖说明。

## 实战示例：多序列比对（教学典型链路）

MAFFT 教学典型命令为 `mafft --auto input.fa > aligned.fa` 与高精度模式 `linsi/einsi/ginsi`；以下为原生 CLI 的典型批量用法，**等价能力由 `native/main.py` 的 `align` 子命令提供**（见上「用法」）。

### 1. 单序列集自动比对（--auto，最常用）

```bash
mkdir -p mafft_out && cd mafft_out
# --auto：按序列数与长度自动在 FFT-NS-2 / L-INS-i 等策略中选择（默认推荐）
mafft --auto --thread 8 ../input.fa > aligned.fa
# 等价驱动调用：python ../modules/mafft/native/main.py align ../input.fa --threads 8 -o aligned.fa
```

### 2. 高精度模式（linsi / ginsi / einsi）——按精度与耗时权衡

```bash
# 高精度（<~200 序列 × <~2000 aa/nt）：L-INS-i（局部比对）/ G-INS-i（全局）/ E-INS-i（含长 gap）
mafft --maxiterate 1000 --localpair  --thread 8 input.fa > align_linsi.fa   # == linsi
mafft --maxiterate 1000 --globalpair --thread 8 input.fa > align_ginsi.fa   # == ginsi
mafft --maxiterate 1000 --genafpair  --thread 8 input.fa > align_einsi.fa   # == einsi

# 驱动等价写法：--method linsi|ginsi|einsi（自动映射到上面的选项组合）
```

### 3. 批量多样本比对（每样本一个结果文件）

```bash
for fa in ../seqsets/*.fa; do
    name=$(basename "$fa" .fa)
    mafft --auto --thread 8 "$fa" > ${name}.aligned.fa
done
# 产物：<name>.aligned.fa（等长比对，可直接送入进化树构建/一致性分析）
```

### 4. 参数说明

| 参数                | 说明                                                                       |
| ----------------- | ------------------------------------------------------------------------ |
| `--auto`          | 自动按序列数与长度选择策略（驱动默认注入）；`--no-auto` 关闭，走默认 FFT-NS-2                      |
| `--method`（驱动层）   | 高精度模式 `linsi`/`einsi`/`ginsi` → 映射为 `--maxiterate 1000` + `localpair`/`genafpair`/`globalpair`；写 `auto` 等价 `--auto`；其它取值按原始选项透传 |
| `--thread N`      | CPU 线程数（驱动由 `--threads` 注入；mafft 原生默认 1，`--thread -1` 用全部核）              |
| `-i` / `-o`（驱动层） | `-i` 输入 FASTA（与位置参数等价）；`-o` 写比对结果文件（缺省 stdout，`-o` 由驱动落盘）             |
| `--maxiterate N`  | 迭代精化次数（高精度模式常用 1000）                                                     |
| `--localpair` / `--globalpair` / `--genafpair` | 局部 / 全局 / 含长 gap 的成对比对策略（对应 L-/G-/E-INS-i）                             |
| `--reorder` / `--clustalout` / `--adjustdirection` 等 | 常用项经 `--extra-args` 透传（如 `--reorder` 按比对结果重排、`--clustalout` 输出 clustal） |

## 环境安装（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制；main.py 驱动在宿主机跑。

### 1. Conda / brew（包管理器安装）

```bash
mamba create -n mafft-native -c conda-forge -c bioconda mafft=7.525
conda activate mafft-native
mafft --version      # 断言（v7.525）
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 homebrew-core，无需额外 tap）
# brew 当前 7.526，与 meta 登记 7.525 略有差异（版本以 formula 为准）
brew install mafft
mafft --version      # 断言（v7.526）
```

### 2. Docker（官方镜像）

```bash
docker pull quay.io/biocontainers/mafft:7.525--h031d066_1
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    quay.io/biocontainers/mafft:7.525--h031d066_1 \
    mafft --auto --thread 8 /data/input.fa > /data/aligned.fa
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 已预构建好 sif，直接拉取现成镜像即可（无需本地从 docker 转换）：

```bash
# galaxyproject 预构建 sif（等价直链见文末「容器与 Conda 链接」）
apptainer pull mafft.sif docker://depot.galaxyproject.org/singularity/mafft:7.525--h031d066_1
apptainer run -B $PWD:/data -H /data mafft.sif mafft --auto --thread 8 /data/input.fa > /data/aligned.fa
```

### 4. 二进制包安装（官方源码归档，无通用预编译资产）

MAFFT 官方以**源码分发**（官网 source 页 / GitLab 镜像 tag），无面向 Linux / macOS 的通用预编译资产——**常规请走上方 Conda 或官方容器**；确需源码路线时拉对应 tag 归档到用户前缀自编译：

```bash
wget https://gitlab.com/sysimm/mafft/-/archive/v7.525/mafft-v7.525.tar.gz -P ~/software/
tar zxf ~/software/mafft-v7.525.tar.gz -C ~/software/     # -> ~/software/mafft-v7.525/
cd ~/software/mafft-v7.525
make -C core install PREFIX=$HOME/software/mafft-7.525
make -C extensions install PREFIX=$HOME/software/mafft-7.525
echo 'export PATH=$PATH:~/software/mafft-7.525/bin' >> ~/.bashrc && source ~/.bashrc
mafft --version      # 断言
```

> 官网源码下载页：<https://mafft.cbrc.jp/alignment/software/source.html>（版本与 `software_versions` 对齐 v7.525）。

## 测试

```bash
cd modules/mafft/native && bash test/run_test.sh
# 任何环境下 exit 0 并打印 ALL TESTS PASSED：自省（--list-commands/--schema）+ 参数契约（align/version --help）必跑；
# PATH 含 mafft 时追加真跑最小链路（合成多序列 → align --auto/-i/stdout/--method linsi + version；
#   真跑失败仅 [WARN] 提示不阻断）；无 mafft 时 [SKIP]。
```

## 版本

* mafft **7.525**（bioconda::mafft=7.525，linux-64 build `h031d066_1`；其他 build 见 anaconda；conda_platforms linux-64 / linux-aarch64 / osx-64）

* 构建路线：官方镜像/conda 提供（quay.io/biocontainers/mafft / depot.galaxyproject.org；本地不再自建容器）

* nf-core 官方子模块 align 当前 pin mafft=**7.520**（低于 native 的 7.525），guidetree pin 7.525（见下「版本差异声明」）

***

## 官方实现登记（不建目录，仅说明层）

### nf-core 官方模块（Nextflow，说明层）

nf-core 官方 `modules/nf-core/mafft/` **存在**（两个子模块：`align` + `guidetree`；2026-09 在线核实，以官方在线目录为准）：

| 子模块         | environment.yml 关键 pin                              | 作用（据 nf-core meta）                          |
| ----------- | --------------------------------------------------- | ----------------------------------------- |
| `align`     | bioconda::mafft=7.520（+ conda-forge::pigz=2.8）       | 输入 fasta（可 gz）→ 多序列比对（MAFFT）             |
| `guidetree` | bioconda::mafft=7.525                               | 输入 fasta → 渲染 guide tree（`*.dnd`）         |

> ⚠️ 执行请用 `nf modules install nf-core mafft align guidetree`（安装到项目自身 `modules/nf-core/`，
> 不要直接引用本仓库示例），随后：
>
> ```nextflow
> include { MAFFT_ALIGN as MAFFT }      from '../modules/nf-core/mafft/align/main'
> include { MAFFT_GUIDETREE as GUIDETREE } from '../modules/nf-core/mafft/guidetree/main'
> ```
>
> 抓取命令：`curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/mafft | python3 -c "import json,sys; [print(x['name']) for x in json.load(sys.stdin)]"`

### snakemake-wrappers（官方缺失说明）

官方 snakemake-wrappers **无** `bio/mafft`（2026-09 抓取 `https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/mafft` 返回 404，登记「官方无」）。Snakemake 场景暂无官方 wrapper 可登记；需要时以 `mafft_native` 为兜底（或参照同库其它模块自建本地 `snakemake/` 规则）。

## 版本差异声明（native / nf-core / snakemake-wrappers / brew）

| 实现                 | mafft 版本                     | 来源                                                                                        |
| ------------------ | ---------------------------- | ----------------------------------------------------------------------------------------- |
| native（官方容器/conda） | **7.525**                    | official biocontainer：quay.io/biocontainers/mafft:7.525--h031d066\_1 / bioconda mafft=7.525 |
| nf-core master     | align **7.520** / guidetree 7.525 | bioconda::mafft=7.520 / 7.525（modules/nf-core/mafft/{align,guidetree}/environment.yml）      |
| snakemake-wrappers | 官方无 wrapper                  | bio/mafft 404（2026-09）                                                                    |
| brew（homebrew-core） | 7.526                        | homebrew-core `mafft` 公式（`brew install mafft`）                                              |

> nf-core align 子模块 pin 7.520 低于 bioconda 现行 7.525：两者可共存（不同环境），用 Nextflow 时以 nf-core 子模块 pin 为准、待 nf-core bump 后同步刷新；用 native（Agent/CLI）时以 7.525 为准；brew 为 7.526（宿主直装，差异极小）。

***

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# mafft native Conda 环境配方（HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 mafft-native.yml 后 mamba env create -f mafft-native.yml；
# 在线推荐上方 mamba create 直装命令。
name: mafft-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - mafft=7.525
  - pyyaml>=6.0
```

## 容器与 Conda 链接

* **Bioconda 页面**：<https://anaconda.org/bioconda/mafft>

* **Docker**：`docker pull quay.io/biocontainers/mafft:7.525--h031d066_1`（bioconda 自动构建；tag 以 quay / depot.galaxyproject.org 页面为准）

* **Singularity**：<https://depot.galaxyproject.org/singularity/mafft%3A7.525--h031d066_1>

* 安装方式（本地）：`mamba create -n mafft-native -c conda-forge -c bioconda mafft=7.525`（或 `brew install mafft`）

* 上游：官网 <https://mafft.cbrc.jp/alignment/software/> · 源码页 <https://mafft.cbrc.jp/alignment/software/source.html> · GitLab 镜像 <https://gitlab.com/sysimm/mafft>
