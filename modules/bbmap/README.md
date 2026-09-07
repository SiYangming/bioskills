# bbmap 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake）的用法；官方 snakemake-wrappers 与 nf-core 子模块信息记录于此（不建目录，仅说明层）。安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# bbmap / native

自包含的 bbmap 驱动实现（`source_type: custom`），二进制由**官方容器/conda**（quay.io/biocontainers/bbmap / bioconda bbmap）提供（Java 工具，`JAVA_TOOL_OPTIONS` 已声明 Xmx 上限）。

## 能力

| 子命令 | 说明 | 线程 |
|--------|------|------|
| `index` | bbmap.sh：参考 FASTA → path= 索引目录（索引落盘，供 align 复用） | ✅（默认 8） |
| `align` | bbmap.sh：reads 比对到参考/索引，out/outm/outu 分流输出 | ✅（默认 8） |

`align` 参数对齐 bbmap key=value 风格：`--in`(in=)、`--ref`(ref=)、`--path`(path=)、`--out`(out=)、`--outm`(outm=)、`--outu`(outu=)、`--ambiguous`(best/toss/all)、`--nodisk`(nodisk=t)、`--trimreaddescription`(trimreaddescription=t) 及 `--extra-args` 透传。

## 快速开始

### 1. 安装环境

```bash
# 路线 A：官方容器/conda（bioconda bbmap → quay.io/biocontainers/bbmap；官方镜像内只含 bbmap 工具，main.py 驱动在宿主机跑）
docker pull quay.io/biocontainers/bbmap:<tag>        # tag 见文末「容器与 Conda 链接」
# 路线 B：本机二进制（macOS/Linux 包管理或官方 zip，见文末链接）
# 路线 C：conda 兜底（HPC 无 root 时）
mamba create -n bbmap-native -c conda-forge -c bioconda bbmap=39.52   # 或文末「Conda 环境」配方另存为 yml 离线使用
conda activate bbmap-native
```

### 2. CLI 调用

```bash
# 建立索引（参考 FASTA -> idx 目录；bbmap 会把参考索引写入 path 目录）
python main.py index --ref refs.fa --path idx --threads 8
# 比对（复用已有索引；outm/outu 分流 mapped/unmapped reads）
python main.py align --in reads.fq.gz --path idx \
    --out out.sam --outm mapped.fq.gz --outu unmapped.fq.gz --threads 8
# 比对（直接给参考、不落盘索引——rRNA/tRNA 滤比场景）
python main.py align --in reads.fq.gz --ref rRNA.fa \
    --outm rRNA.fq.gz --outu non_rRNA.fq.gz \
    --nodisk --ambiguous best --trimreaddescription --threads 8
```

### 3. Agent / Schema 自省

```bash
python main.py --schema              # 输出 JSON Schema
python main.py --list-commands       # 列出支持的子命令
```

### 4. 容器运行（官方镜像优先，不维护本地配方）

官方已维护（bioconda → quay.io/biocontainers → depot.galaxyproject.org），直接拉取官方镜像运行工具二进制：

```bash
# Docker：工具直跑（官方镜像内只含 bbmap，main.py 驱动在宿主机运行）
docker pull quay.io/biocontainers/bbmap:<tag>        # tag 见 quay 页面 / 文末链接
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data quay.io/biocontainers/bbmap:<tag> bbmap.sh \
  ref=/data/refs.fa path=/data/idx threads=8
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data quay.io/biocontainers/bbmap:<tag> bbmap.sh \
  in=/data/reads.fq.gz path=/data/idx \
  out=/data/out.sam outm=/data/mapped.fq.gz outu=/data/unmapped.fq.gz threads=8

# Singularity/Apptainer
apptainer pull bbmap.sif docker://quay.io/biocontainers/bbmap:<tag>
# 或直链 depot.galaxyproject.org/singularity/bbmap%3A<tag>（与 quay 同 build tag）
```

> 容器内为原生工具入口（bbmap.sh）；需要 Schema/自省/参数注入时在**宿主机**（conda 装 bbmap 或官方镜像同款 env）运行 `python main.py <subcommand> ...`。

### 5. 测试

```bash
bash test/run_test.sh
```

## 性能优化约定

- **线程**：`index`/`align` 默认 8 线程；用户显式 `--threads` 永远优先。
- **内存**：bbmap 为 Java 工具，`JAVA_TOOL_OPTIONS=-Xmx8g` 已在容器与 `meta.yaml.optimization.env_vars` 声明；`default_mem_mb` 供上层调度器读取。
- **临时目录**：通过 `TMPDIR`（含 `-Djava.io.tmpdir`，占位符 `{tmpdir}`）注入，避免污染工作目录。


---

## snakemake 实现

# bbmap / snakemake（本地规则 + 官方 wrappers 参考）

### 本地拆分规则（td2 式：每 rule 一个 .smk，config 驱动）

`snakemake/` 内规则按子命令拆为单规则文件（不依赖流程 `common.smk`/`samples`/`config["paths"]`，可独立 dry-run）：

| 文件 | 规则 | 作用 |
|------|------|------|
| `snakemake/bbmap_index.smk` | `bbmap_index` | 参考 FASTA → BBMap 索引目录（path=） |
| `snakemake/bbmap_align.smk` | `bbmap_align` | reads（SE/PE）→ SAM（ref= 或 path= 索引二选一） |

- 配套文件（均平铺 `snakemake/`，`.smk` 同目录相对引用）：`bbmap.yaml`（bioconda bbmap==39.52）、`bbtools.py`（command=bbmap.sh，docker/native/conda 三模式分派依赖共享 `modules/docker_wrapper.py`）。
- Ribo-seq 的 rRNA→tRNA→PC 分层滤比：以多组 config（不同 `bbmap_ref`/`bbmap_index_dir`/`bbmap_extra`）多次 include `bbmap_align.smk` 在流程层展开，模块层只提供通用单规则。
- 独立运行示例与 config 契约见各 `.smk` 头注，例如：
  ```bash
  snakemake -s modules/bbmap/snakemake/bbmap_align.smk \
      --config bbmap_read1=s.fastq.gz bbmap_ref=ref.fa bbmap_sam=out.sam --cores 8 --use-conda
  ```

### 官方 snakemake-wrappers（说明层，运行时靠 `wrapper:` 句柄解析）

> ⚠️ 官方仓库**没有 `bio/bbmap` 子目录**：BBMap 全家桶由 **`bio/bbtools`**（BBMAP-SUITE）单个 wrapper 覆盖，用 `params.command=` 指定要运行的工具（如 `bbmap.sh`）。本模块**不重写官方 wrapper 源码**。官方 `bio/bbtools` 内容（2026-09 抓取 v3.13.0，以官方在线目录为准）：

| wrapper | wrapper 句柄 | 环境 pin |
|---------|--------------|----------|
| bbtools（BBMAP-SUITE，`command=bbmap.sh` 等） | `vX.Y.Z/bio/bbtools` | v3.13.0：bbmap=39.06, snakemake-wrapper-utils=0.6.2, pigz=2.8；master：bbmap=40.02, utils=0.9.0 |

引用示例（Snakefile）：

```python
rule bbmap_align:
    input:
        reads="reads_1.fastq.gz",
        ref="ref.fa"
    output:
        "mapped.fq.gz"
    log: "logs/bbmap_align.log"
    params:
        command="bbmap.sh",
        extra="ambiguous=best nodisk"
    threads: 8
    wrapper: "v3.13.0/bio/bbtools"
```

> ⚠️ 本模块未内置官方 wrapper 的 wrapper.py：Snakemake 运行时按 `wrapper:` 句柄解析（联网拉取中央 wrapper 缓存）；离线/私有环境缺失时请改用本模块 `snakemake/bbmap_{index,align}.smk` 本地规则。
> 更新子模块清单的抓取命令：
> `curl -s https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/bbtools | python3 -c "import json,sys; [print(x['name']) for x in json.load(sys.stdin)]"`

### nf-core 官方参考（Nextflow，说明层）

本模块未建 `nextflow/` 目录；nf-core 官方 `modules/nf-core/bbmap/` 子模块（2026-09 抓取 master，以官方在线目录为准）：

| 子模块 | environment.yml 关键 pin（master） |
|--------|-------------------------------------|
| align | bioconda::bbmap=39.18, pigz=2.8 |
| index / bbduk / bbmerge / bbnorm / bbsplit / clumpify / filterbyname / pileup / repair / sendsketch | 各子模块自持 environment.yml，版本以官方在线目录为准 |

组装 Nextflow DSL2 流程时执行 `nf modules install nf-core bbmap align index ...`（安装到项目自身 `modules/nf-core/`，不要直接 include 本仓库文件），随后：

```nextflow
include { BBMAP_ALIGN } from '../modules/nf-core/bbmap/align/main'
```

> 抓取命令：`curl -s https://api.github.com/repos/nf-core/modules/contents/modules/nf-core/bbmap | python3 -c "import json,sys; [print(x['name']) for x in json.load(sys.stdin)]"`


---

## 版本差异声明（native / snakemake-wrappers / nf-core / riboseq）

| 实现 | bbmap 版本 | 来源 |
|------|-----------|------|
| native（官方容器/conda） | **39.52** | official biocontainer：quay.io/biocontainers/bbmap:39.52--he5f24ec_0 / bioconda bbmap=39.52（riboseq 流程同款） |
| snakemake 本地规则 env | 39.52 | bioconda（本模块 `snakemake/bbmap.yaml`，与 riboseq 流程一致） |
| snakemake-wrappers v3.13.0（bio/bbtools） | 39.06 | bioconda（bio/bbtools/environment.yaml） |
| snakemake-wrappers master | 40.02 | bioconda（autobump） |
| nf-core master（bbmap/align） | 39.18 | bioconda（modules/nf-core/bbmap/align/environment.yml） |
| riboseq 容器 | 39.52 | quay.io/biocontainers/bbmap:39.52--he5f24ec_0 |

> native 与 riboseq 流程统一 39.52（官方容器 quay.io/biocontainers/bbmap:39.52--he5f24ec_0 / conda bbmap=39.52）；原 apt 打包 39.01+dfsg-2 的历史差异已随本地容器移除。


---

## Conda 环境（离线 / 非容器兜底备选）

```yaml
# bbmap native Conda 环境配方（HPC 无 root / 非容器兜底）
# 离线兜底：可另存为 bbmap-native.yml 后 mamba env create -f bbmap-native.yml；在线推荐上方 mamba create 直装命令
name: bbmap-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - bbmap=39.52     # 与 riboseq 流程一致；如需 apt 同款 39.01 请装 Debian 包/官方 zip
  - pyyaml>=6.0
```

## 容器与 Conda 链接

- **Bioconda 页面**：https://anaconda.org/bioconda/bbmap
- **Docker**：`docker pull quay.io/biocontainers/bbmap:39.52--he5f24ec_0`（riboseq 流程同款）
- **Singularity**：https://depot.galaxyproject.org/singularity/bbmap%3A39.52--he5f24ec_0
- 安装方式（本地）：`mamba create -n bbmap -c conda-forge -c bioconda bbmap=39.52`（官方镜像/conda 提供，本地不再自建容器）
- 上游 GitHub：https://github.com/BioInfoTools/BBMap ；官方下载页：https://sourceforge.net/projects/bbmap/
