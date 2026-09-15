# blast2go 软件模块

> 汇总说明：Blast2GO 是基因功能注释与富集分析工具；本模块合并 native 实现（客户端 3.3 +
> 命令行 b2g4pipe v2.5）的用法，安装方式见「环境安装」，容器与许可信息记录于此。
>
> ⚠️ **Blast2GO 许可受限**（需在官网注册/订阅后获取发行包），且**不在 bioconda /
> quay.io/biocontainers / depot.galaxyproject.org 分发**（2026-09 已核实：bioconda 404、
> quay 无仓库、depot 404），故本模块以**用户自备发行包**部署，并提供自建容器兜底配方
> （容器配方消费用户自备发行包，不伪造下载链接）。

***

## native 实现

# blast2go / native — 自包含功能注释驱动（Java）

Blast2GO 的本地自包含实现（`source_type: custom`、`type: native`）：封装命令行 GO 注释
（b2g4pipe）、本地注释库安装（local_b2g_db）与图形客户端启动。

## 功能

| 子命令 | 命令（驱动构造） | 作用 |
| ---- | ---- | ---- |
| `annot` | `java -cp <b2g-dir>/*:<b2g-dir>/ext/* es.blast2go.prog.B2GAnnotPipe -in <xml> -out <前缀> -prop <props> -annot -dat -annex` | b2g4pipe 命令行 GO 注释（最常用） |
| `install_db` | `perl <db-home>/install_blast2goDB.sh`（cwd=db-home） | 安装 Blast2GO 本地注释库（依赖 MySQL/Perl） |
| `client` | `<blast2go-home>/Blast2GO` | 启动 Blast2GO 3.3 图形客户端 |

> 入口定位：b2g4pipe 目录优先 `--b2g-dir` / `B2G4PIPE_HOME`；客户端优先 `--blast2go-home` /
> `BLAST2GO_HOME`；`java` 经 PATH 惰性解析。**Java 工具**：JVM 参数经 `JAVA_OPTS` 环境变量透传
> （默认 `-Xmx6g -Djava.io.tmpdir={tmpdir}`；`--java-opts` 覆盖）。

## 用法

```bash
# 1) b2g4pipe 命令行 GO 注释（输入 BLAST outfmt 5 XML）
python main.py annot -in nr.xml -out go --b2g-dir ~/software/b2g4pipe

# 2) 安装本地注释库（local_b2g_db：install_blast2goDB.sh，依赖 MySQL/Perl）
python main.py install_db --db-home ~/software/blast2go-db

# 3) 启动图形客户端（桌面环境）
python main.py client --blast2go-home ~/software/Blast2GO

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` / `--java-opts` 运行期覆盖（b2g4pipe 单线程，
`--threads` 仅契约）。

## 实战示例：BLAST 结果 → GO 注释 → 本地库建库

文档「安装 Blast2GO」（§安装 Blast2GO 本地数据库 / 客户端）与「b2g4pipe 命令行版本」给出
经典流程；等价能力由 `native/main.py` 的 `annot` / `install_db` / `client` 子命令提供（见上「用法」）。

### 1. 安装（自备发行包）

```bash
# Blast2GO 许可受限，需在官网注册/订阅下载发行包后部署
bash native/install.sh --b2g4pipe-zip ~/software/b2g4pipe_v2.5.zip \
                       --client-zip   ~/software/Blast2GO_unix_3_3_x64.zip
# 可选：本地注释库
bash native/install.sh --b2g4pipe-zip ~/software/b2g4pipe_v2.5.zip \
                       --db-tarball   ~/software/local_b2g_db.tar.gz --db-name b2gdb --db-host localhost
```

### 2. 命令行 GO 注释（b2g4pipe）

```bash
# 先准备 BLAST XML（outfmt 5；如 diamond/ncbi-blast 输出 nr.xml）
python main.py annot -in nr.xml -out go --b2g-dir ~/software/b2g4pipe
# 产物：go.annot / go.dat 等（阈值/输出格式等高级参数经 --extra-args 透传）
```

### 3. 安装本地注释库

```bash
# 下载 GO/NCBI/idmapping 数据后用 local_b2g_db 的 install_blast2goDB.sh 建库（MySQL + Perl DBI/DBD::mysql）
python main.py install_db --db-home ~/software/blast2go-db
```

### 4. 参数说明

| 参数 | 说明 |
| ---- | ---- |
| `-in` / `-out` | b2g4pipe 输入 BLAST XML / 输出前缀 |
| `--b2g-dir` | b2g4pipe 安装目录（含 `B2GAnnotPipe` 类与 `ext/`） |
| `--prop` | b2g4pipe 配置（`b2gPipe.properties`，含 `Dbacces.dbname/dbhost`） |
| `-annot/-dat/-annex` | B2GAnnotPipe 输出开关（`--no-annot/--no-dat/--no-annex` 关闭） |
| `--db-home` | 本地注释库目录（含 `install_blast2goDB.sh`） |
| `--blast2go-home` | Blast2GO 客户端安装目录（含 `Blast2GO` 启动器） |
| `--java-opts` | 覆盖 `JAVA_OPTS`（JVM 内存/临时目录，如 `-Xmx8g`） |

## 环境安装（许可受限，需注册/订阅自备发行包；官方无镜像/conda → 自建兜底配方）

**已核实（2026-09）**：Blast2GO 在官方渠道 bioconda / quay.io/biocontainers /
depot.galaxyproject.org **均无**（bioconda 404、quay 无仓库、depot 404），也没有 nf-core
modules / snakemake-wrappers / homebrew 公式；官方分发物为**需注册/订阅获取的发行包**
（客户端 `Blast2GO_unix_3_3_x64.zip`、命令行 `b2g4pipe_v2.5.zip`、注释库 `local_b2g_db.tar.gz`），
无公开直链、无官方 sha256。故既不能走官方镜像直拉，也无法用 conda 安装，本模块提供
**自建 apt 最小化容器配方**兜底（消费用户自备发行包）。

### 1. 官方预编译包（需注册/订阅，唯一路线）

1. 打开下载/许可页：<https://www.biobam.com/download-blast2go/>（官网 <https://www.blast2go.com/>）
2. 注册/订阅后获取发行包：`Blast2GO_unix_3_3_x64.zip`（客户端 3.3）、`b2g4pipe_v2.5.zip`（命令行）、`local_b2g_db.tar.gz`（本地注释库）
3. 用一键脚本部署到用户目录（免 root；禁 `/opt/biosoft`）：

```bash
bash native/install.sh --b2g4pipe-zip ~/software/b2g4pipe_v2.5.zip \
                       --client-zip   ~/software/Blast2GO_unix_3_3_x64.zip \
                       --db-tarball   ~/software/local_b2g_db.tar.gz
# 部署到 ~/software/blast2go-3.3（b2g4pipe/ + Blast2GO/ + blast2go-db/），并写 B2G4PIPE_HOME / BLAST2GO_HOME
```

**依赖**：Java（推荐 JDK/JRE 11/17；`java -version` 断言）；本地注释库需 MySQL 5.7+ 与
Perl（DBI/DBD::mysql）。

### 2. 官方源码编译（已核实：无此路线）

Blast2GO 官方仅以**预编译发行包**分发（Java 字节码/图形客户端），不提供独立源码编译路线；本节仅作说明。

### 3. Conda / brew（已核实：均无）

* `conda install -c bioconda blast2go`：**已核实 bioconda 无 blast2go**（`api.anaconda.org/package/bioconda/blast2go` → 404），不可用。
* Homebrew：homebrew-core 与 brewsci/bio 均无 blast2go 公式（已核实 404）。
* 请改用上表 §1 自备路线或 §4/§5 自建容器。

### 4. Docker（自建镜像，官方无镜像）

官方渠道无 Blast2GO 镜像，提供自建兜底配方 `native/Dockerfile`（debian:bookworm-slim +
apt `--no-install-recommends` 装 openjdk-17-jre-headless/perl + 清理四连）：

```bash
# 构建前先把自备的 b2g4pipe 发行包放到 native/ 目录
cp ~/software/b2g4pipe_v2.5.zip modules/blast2go/native/
docker build -t blast2go:3.3 -f modules/blast2go/native/Dockerfile modules/blast2go/native/

# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data blast2go:3.3 \
    -in /data/nr.xml -out /data/go -annot -dat -annex
```

> 容器仅打包无头命令行 b2g4pipe；Blast2GO 3.3 图形客户端为桌面程序，请用 `native/install.sh`
> 在宿主机安装；本地注释库需外部 MySQL。

### 5. Apptainer / Singularity（自建，depot 无现成 sif）

官方无 depot 预构建 sif，用同仓库自建定义 `native/Apptainer.def`（同 apt 最小化路线 + `%test`）：

```bash
cp ~/software/b2g4pipe_v2.5.zip modules/blast2go/native/
apptainer build blast2go.sif modules/blast2go/native/Apptainer.def
apptainer run -B $PWD:/data blast2go.sif -in /data/nr.xml -out /data/go -annot -dat -annex
```

## 官方实现登记（不建目录，仅说明 + Schema）

* **nf-core modules**：无 `modules/nf-core/blast2go`（2026-09 核实 404）；Nextflow 场景以本模块 `native/` 兜底。
* **snakemake-wrappers**：无 `bio/blast2go`（2026-09 核实 404）；Snakemake 场景以本模块 `native/` 兜底。

## 测试

```bash
bash test/run_test.sh   # argv 构造验证（monkeypatch java/perl）+ JAVA_OPTS 透传 + 容器配方静态检查
```

## 版本

* Blast2GO 客户端 3.3 · b2g4pipe 命令行 2.5（BioBam；⚠️ 许可受限，需注册/订阅）
* 依赖：Java（推荐 11/17）；本地注释库需 MySQL 5.7+ 与 Perl（DBI/DBD::mysql）
* 构建路线：官方渠道无镜像/无 conda → **自建兜底配方**（`native/Dockerfile` + `native/Apptainer.def`，
  debian:bookworm-slim + openjdk-17-jre-headless/perl；容器消费用户自备 b2g4pipe 发行包）

## 容器与 Conda 链接（均无官方 → 记录替代方案）

* **官网**：<https://www.blast2go.com/>（下载/许可：<https://www.biobam.com/download-blast2go/>，需注册/订阅）
* **Bioconda**：无（404，2026-09 核实）· **quay.io/biocontainers/blast2go**：无仓库 · **depot.galaxyproject.org**：404
* **替代方案**：自建容器 `native/Dockerfile` / `native/Apptainer.def`（需自备 b2g4pipe 发行包）；或宿主机
  `bash native/install.sh --b2g4pipe-zip <b2g4pipe_v2.5.zip> --client-zip <Blast2GO_unix_3_3_x64.zip>`
