# fusionmap 软件模块

> 汇总说明：本 README 合并 native 实现的用法；安装方式见下方「环境安装」节，容器渠道信息记录于此（2026-09 逐渠道核实）。
> FusionMap 是基于 RNA-seq（也可 gDNA-seq）数据的融合基因检测工具，把 junction-spanning reads 直接比对到基因组，无需先验融合信息即可在碱基分辨率上检测单端/双端数据的融合事件。
> ⚠️ **商业/许可受限**：官方声明 **free for noncommercial use**（非商业免费），商业用途需向 OmicSoft（omicsoft.com）获取授权。

***

## native 实现

# fusionmap / native — FusionMap 融合检测驱动

FusionMap 的本地自包含实现（`source_type: custom`、`type: native`），命令逻辑对齐教学文档
「3.14.1 FusionMap」与「12.1 FusionMap」。软件用 C# 编写，Windows 版为 `FusionMap.exe`（Linux 下用
`mono` 运行），官方另有 Linux 直接可执行的构建；驱动按可执行文件后缀自动选择是否前置 `mono`。

## 功能

| 子命令 | 命令 | 作用 |
| --- | --- | --- |
| `detect` | `FusionMap --fusion DetectFusion --input <fastq...> --ref <Ref> --output <out_dir> --thread N` | 融合基因检测（单/双端 RNA-seq） |

参数说明：

| 参数 | 说明 |
| --- | --- |
| `--fusion` | 操作模式，默认 `DetectFusion` |
| `--input` | 输入 FASTQ（单端一个 / 双端两个，可多个） |
| `--ref` | 参考数据目录（官方包内 `Data/Ref`，或自建索引目录） |
| `--output` | 输出目录 |
| `--thread` | 线程数（自动注入；默认 8） |

> 驱动按可执行形态选择：原生 `FusionMap` 直接调用；`FusionMap.exe` 前置 `mono`。
> 可用环境变量 `FUSIONMAP_BIN` 显式指定可执行文件路径。

## 用法

```bash
# CLI 直跑（文档 12.1 示例参数，路径改为通用形式）
python main.py detect --input reads.fastq --ref /path/FusionMap/Data/Ref --output ./ --thread 8
python main.py detect --input reads_1.fastq reads_2.fastq --ref Data/Ref --output out/ --thread 8

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：RNA-seq 融合基因检测

以下为教学文档「12.1 FusionMap」的典型用法（把硬编码的 `/opt/biosoft/FusionMap_2015-03-31/`
改写为通用安装目录；等价能力由 `native/main.py` 的 `detect` 子命令提供，见上「用法」）。

```bash
mkdir -p fusion_detection && cd fusion_detection

# Linux 直接可执行构建
FusionMap --fusion DetectFusion \
    --input ../fastq/sample.fastq \
    --ref ~/software/fusionmap-2015-03-31/Data/Ref \
    --output ./ \
    --thread 8

# 若仅有 Windows 版 FusionMap.exe，则用 mono 运行
mono ~/software/fusionmap-2015-03-31/FusionMap.exe \
    --fusion DetectFusion \
    --input ../fastq/sample.fastq \
    --ref ~/software/fusionmap-2015-03-31/Data/Ref \
    --output ./ \
    --thread 8
```

> 桥接 native 驱动：`python main.py detect --input ../fastq/sample.fastq --ref ~/software/fusionmap-2015-03-31/Data/Ref --output ./ --thread 8`
> （驱动会自动识别原生/`.exe` 形态并注入 `--thread`）。

## 环境安装（自建兜底：FusionMap 无官方镜像 / conda 包，apt 最小化 + 官方预编译包）

> ⚠️ **版本现状（2026-09 逐渠道核实）**：官方渠道 bioconda → quay.io/biocontainers →
> depot.galaxyproject.org **全部没有** FusionMap（`api.anaconda.org/package/bioconda/fusionmap` → 404；
> quay `biocontainers/fusionmap` 未授权/不存在；`depot.../fusionmap:2015-03-31` → 404）；
> nf-core / snakemake-wrappers 无模块；Homebrew（core + brewsci/bio）无公式。
> 官方发布为 OmicSoft 预编译 tar.gz（`FusionMap_2015-03-31.tar.gz`），因此走**自建兜底**：
> `native/Dockerfile` + `native/Apptainer.def`（debian:bookworm-slim + apt 最小化 + mono-runtime +
> 官方预编译包，禁 miniconda），宿主机本地部署见「### 3」。
>
> ⚠️ **商业/许可受限**：FusionMap 官方声明 free for noncommercial use，商业用途需授权；自建镜像/
> 软件本体**不得再分发**，仅供本地非商业使用。

### 1. Conda / brew（包管理器安装）

**不提供 conda / brew 路线，理由（2026-09 核实）**：

```bash
# ❌ bioconda 无 fusionmap 包（api.anaconda.org/package/bioconda/fusionmap → 404）
# ❌ Homebrew：homebrew-core（formulae.brew.sh/api/formula/fusionmap.json → 404）与
#    brewsci/bio（Formula/fusionmap.rb → 404）均无公式
```

### 2. Docker（自建镜像，官方渠道无）

```bash
# 构建（context=modules/ 层，携带 base.py + 软件级 meta.yaml）
# 官方下载经 Cloudflare/许可页，自动化 curl 多返回 403 → 若构建失败，用可访问 URL 覆盖 FUSIONMAP_URL
docker build -t bioskills/fusionmap:2015-03-31 -f modules/fusionmap/native/Dockerfile modules/
# 或：docker build -t bioskills/fusionmap:2015-03-31 \
#         --build-arg FUSIONMAP_URL=<可访问的 FusionMap_2015-03-31.tar.gz URL> \
#         -f modules/fusionmap/native/Dockerfile modules/
# 运行：注意必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data bioskills/fusionmap:2015-03-31 \
    --fusion DetectFusion --input /data/reads.fastq --ref /data/Ref --output /data/out --thread 8
# 驱动 main.py（镜像内已放 base.py + 软件级 meta；--entrypoint 切到 python3）
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    --entrypoint /usr/bin/python3 bioskills/fusionmap:2015-03-31 \
    /opt/skill/main.py detect --input /data/reads.fastq --ref /data/Ref --output /data/out --thread 8
```

### 3. Apptainer / Singularity

depot.galaxyproject.org 无预构建 fusionmap sif（`fusionmap:2015-03-31` → 404）→ 本地自建：

```bash
cd modules && apptainer build ../fusionmap.sif fusionmap/native/Apptainer.def && cd ..
apptainer run -B $PWD:/data -H /data fusionmap.sif \
    --fusion DetectFusion --input /data/reads.fastq --ref /data/Ref --output /data/out --thread 8
```

### 4. 官方预编译包 + 本地部署（宿主机，免 root）

官方预编译包需从官方下载页获取并接受许可（自动化 curl 多返回 403）：

```bash
# 1) 从官方下载页获取预编译包（需接受许可；文件名 FusionMap_2015-03-31.tar.gz）
#    官方下载页：https://www.omicsoft.com/download/fusionmap/
# 2) 本地部署到用户前缀（~/software/fusionmap-2015-03-31），launcher 自动识别原生/.exe 形态
bash native/install.sh --tarball ~/Downloads/FusionMap_2015-03-31.tar.gz
# 或尝试直接下载（多会因 Cloudflare/许可页 403 失败）：
bash native/install.sh

# Windows 版 .exe 需 mono（Debian/Ubuntu: apt install mono-runtime；macOS: brew install mono）
```

## 测试

```bash
bash test/run_test.sh   # 自省 + argv 构造断言（含原生 / .exe→mono 两种形态）恒跑
```

## 版本与来源（2026-09 逐渠道核实，禁止臆造）

| 渠道 | 状态 | 说明 |
| --- | --- | --- |
| OmicSoft 官方下载页（官方） | ✅ 最新 `FusionMap_2015-03-31.tar.gz` | 2015-03-31 后停止更新（并入 Oshell/OmicScript）；Windows 版 .exe（需 mono）/ Linux 直接可执行 |
| bioconda | ❌ 404 | `api.anaconda.org/package/bioconda/fusionmap` |
| quay.io/biocontainers | ❌ 无 | 未授权/不存在（biocontainers 由 bioconda 自动构建，bioconda 无包） |
| depot.galaxyproject.org | ❌ 404 | `singularity/fusionmap:2015-03-31` |
| nf-core modules | ❌ 404 | `modules/nf-core/fusionmap` |
| snakemake-wrappers | ❌ 404 | `bio/fusionmap` |
| Homebrew（core / brewsci/bio） | ❌ 两源均 404 | 无公式 |
| 许可 | ⚠️ 商业/许可受限 | free for noncommercial use；商业用途需授权 |

* 判定：官方渠道（bioconda → quay biocontainers → depot）全无 →「无官方维护」→ 自建配方
  （版本差异与依据在 `meta.yaml software_versions` 中声明）。
* 参考文献：Ge H, et al. Bioinformatics 27(14):1922-1928 (2011)。

## 容器与 Conda 链接

* **官方主页 / 下载页**：<https://www.omicsoft.com/fusionmap/> · <https://www.omicsoft.com/download/fusionmap/>
* **Bioconda 页面（无此包）**：<https://anaconda.org/bioconda/fusionmap>（404）
* **自建配方**：`modules/fusionmap/native/Dockerfile` + `Apptainer.def`（debian:bookworm-slim + mono-runtime + 官方预编译包）
* **宿主一键安装**：`bash modules/fusionmap/native/install.sh --help`（`--tarball` 本地部署到 `~/software/fusionmap-2015-03-31`）
* ⚠️ 商业/许可受限：非商业免费；本仓库不再分发软件本体，镜像/包仅供本地非商业使用

## 版本

* FusionMap 2015-03-31（官方 OmicSoft 预编译包；无官方镜像/conda 包，自建兜底）
* 构建路线：自建（native/Dockerfile + Apptainer.def，debian:bookworm-slim + apt 最小化 + mono-runtime + 官方预编译包）
