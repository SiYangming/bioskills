# go_class 软件模块

> 汇总说明：本 README 合并各实现（native）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。
>
> ⚠️ **无官方渠道（2026-09 核实）**：bioconda `go_class` / `go-class` **404**（检索无结果）· quay.io/biocontainers 无（bioconda 无包 → 自动构建链不存在）· depot.galaxyproject.org/singularity/go-class **404** · biocontainers.pro **404** · nf-core 404 · snakemake-wrappers 404 → 走自建容器兜底。
>
> ⚠️ **分发方式**：分发介质为**本地 tar 包**（`go_class.tar.gz`），**未给出官方下载页与版本号**（本模块如实登记版本为「未标注」）；容器配方消费用户自备的 tar 包，**不伪造下载链接**。依赖 **Perl**。

***

## native 实现

# go_class / native — GO 功能分类 / WEGO 图驱动

GO class（Perl 脚本集）的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

六个子命令覆全链路：

| 子命令          | 命令                                                                                          | 作用                          |
| ------------ | ------------------------------------------------------------------------------------------- | --------------------------- |
| `config`     | `make_go_class_config.pl <go.obo>`                                                          | 用 GO 本体初始化 go_class 配置        |
| `annot2wego` | `annot2wego.pl <go.annot>`                                                                  | GO 注释 → WEGO 格式（写 stdout/`-o`） |
| `classify`   | `get_Genes_From_GO.pl <go.obo> <go.wego>`                                                   | GO 分类统计（写 stdout/`-o`）        |
| `svg`        | `go_svg.pl --outdir <d> --name <n> [--color] [--mark] [--note] <go.wego>`                    | 生成 WEGO-SVG 图                |
| `distribute` | `distributing_svg.pl <out.lst> <out.svg>`                                                   | 组合图元清单为完整 SVG                |
| `resize`     | `changsvgsize.pl <out.svg> <width> <height>`                                                | 调整 SVG 尺寸                   |

> go_class 为 **Perl 脚本集**（无统一二进制），各子命令按名解析对应脚本：优先 `PATH`，其次 `$GO_CLASS_HOME/{bin,svg}`。`--threads` 为统一接口保留（脚本单线程，仅供上层调度器读取），不注入命令行。

## 用法

```bash
# CLI 直跑（GO 功能分类 / WEGO 图）
python main.py config     go.obo
python main.py annot2wego go.annot -o go.wego
python main.py classify   go.obo go.wego -o go_class.tab
python main.py svg        go.wego --outdir ./ --name out --color green \
    --mark "Whole Genome Genes" --note "GO Class of whole genome genes"
python main.py distribute out.lst out.svg
python main.py resize     out.svg 150 -100

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 实战示例：WEGO 分类图

在 GO 注释整理（`go.annot`，由 eggNOG/InterPro 整合而来）之后，生成 WEGO 格式并绘制 GO 分类图：

```bash
mkdir -p go/go_class && cd go/go_class

# 1) 注释 -> WEGO 格式
annot2wego.pl ../go.annot > go.wego

# 2) GO 分类统计（BP/MF/CC 三大类计数）
get_Genes_From_GO.pl /opt/biosoft/go_class/bin/go.obo go.wego > go_class.tab

# 3) 生成 WEGO-SVG 图（--color/--mark/--note 控制配色与图注）
go_svg.pl --outdir ./ --name out --color "green" \
    --mark "Whole Genome Genes" --note "GO Class of whole genome genes of Malassezia sympodialis" go.wego

# 4) 调整图元间距并组合为完整 SVG，再调整尺寸
perl -p -i -e 's/MovePer:0.125/MovePer:0.5/' out.lst
/opt/biosoft/go_class/svg/distributing_svg.pl out.lst out.svg
changsvgsize.pl out.svg 150 -100
convert out.svg out.png   # 可选：ImageMagick 转位图（流程侧工具，不在本模块内）
```

> 等价能力由 `native/main.py` 的 `config` / `annot2wego` / `classify` / `svg` / `distribute` / `resize` 子命令提供（见上「用法」）。`convert`（ImageMagick）与 `go_from_eggNOG_and_interpro.pl` 等属流程侧脚本，不在本模块内。

## 环境安装（无官方渠道，自建容器 / 自备 tar 包）

GO class 官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）**全无**，分发介质为本地 tar 包（无官方下载页）→ 本模块走**自建兜底**（`native/Dockerfile`、`native/Apptainer.def`），构建须提供用户自备的 `go_class.tar.gz`。

### 1. Docker（自建镜像）

```bash
# 无官方下载页；用自托管/本地副本作为构建输入
docker build --build-arg GO_CLASS_URL=https://<your-mirror>/go_class.tar.gz \
    -t bioskills/go_class:latest modules/go_class/native
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/go_class:latest annot2wego.pl /data/go.annot > go.wego
```

### 2. Apptainer / Singularity

无官方 sif（depot 无 go-class，2026-09 核实 404），从本模块自建配方构建（与 Docker 同一 apt 路线）：

```bash
export GO_CLASS_URL=https://<your-mirror>/go_class.tar.gz   # 或解开 Apptainer.def %files 放本地 tar 包
apptainer build go_class.sif modules/go_class/native/Apptainer.def
apptainer run --bind $PWD:/data go_class.sif annot2wego.pl /data/go.annot
```

### 3. 官方发行包（无官方下载页，需自备 tar 包）

* 来源：本地 tar 包 `go_class.tar.gz`（**无官方下载页**，2026-09 未找到）。
* 用 `native/install.sh` 部署到 `~/software/go_class`（可用 `--obo` 顺带初始化配置）：

```bash
bash modules/go_class/native/install.sh --archive ~/software/go_class.tar.gz --obo ~/data/go.obo
```

### 4. Conda / brew（均不可用，已核实）

* **conda**：`anaconda.org/bioconda/go_class` 返回 **404**，无包可装（检索无结果）。
* **brew**：homebrew-core 与 brewsci/bio 均**无** go-class 公式（2026-09 核实 404）→ 不写 brew 块。

## 测试

```bash
bash test/run_test.sh   # 用 stub 脚本验证 argv 与 stdout→-o 重定向
```

## 容器与 Conda 链接

* **Bioconda 页面**：无（`anaconda.org/bioconda/go_class` 404）

* **Docker**：无官方镜像；自建配方 `modules/go_class/native/Dockerfile`（`bioskills/go_class:latest`）

* **Singularity**：无官方 sif；自建配方 `modules/go_class/native/Apptainer.def`

* **官方渠道核实（2026-09）**：bioconda 404 · quay.io/biocontainers 无 · depot.galaxyproject.org 404 · biocontainers.pro 404 · nf-core 404 · snakemake-wrappers 404

* 安装方式（本地）：无官方路线；`native/install.sh --archive <go_class.tar.gz>` 或自建容器

## 版本

* go_class：**未标注**（本地 tar 包 `go_class.tar.gz`，无版本号/无官方下载页）

* 构建路线：无官方 conda/容器 → 自建容器（`debian:bookworm-slim` + apt perl 运行时 + 用户自备 tar 包）

* 依赖：Perl（`annot2wego.pl` / `get_Genes_From_GO.pl` / `go_svg.pl` / `distributing_svg.pl` / `changsvgsize.pl` / `make_go_class_config.pl`）
