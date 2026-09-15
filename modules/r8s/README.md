# r8s 软件模块

> 汇总说明：本 README 合并 native 实现的用法；安装方式见下方各节，容器信息记录于此。
> 官方 nf-core / snakemake-wrappers 均无 r8s 实现（2026-09 抓取 404），且官方渠道无 conda/容器包，故不建对应目录，仅在 `software_versions` 与本文登记。

***

## native 实现

# r8s / native — 似然分子钟分析驱动

r8s 1.81 的本地自包含实现（`source_type: custom`、`type: native`）。

## 功能

| 子命令       | 命令                     | 作用                                                           |
| --------- | ---------------------- | ------------------------------------------------------------ |
| `run`     | `r8s -b -f <NEXUS 输入>`  | 执行输入文件中的 `divtime` / `crossv` / `showage` / `describe` 指令（交叉验证与分歧时间计算） |
| `version` | `r8s -v -b`            | 打印版本并退出（r8s 以退出码 1 结束，属正常行为）                                  |

> r8s 单线程；`--threads` 经 `OMP_NUM_THREADS` 透传，命令行不注入线程参数。

## 用法

```bash
# CLI 直跑（-b 批处理、-f 指定 NEXUS 输入）
python main.py run r8s_in.txt --threads 8
python main.py version

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

## 实战示例：交叉验证选 smoothing + 分歧时间计算

r8s 用 penalized likelihood（PL）估计分歧时间，需先交叉验证选 smoothing 参数。等价能力由 `native/main.py` 的 `run` 子命令提供（见上「用法」）。

### 1. 准备 NEXUS 输入（trees 块 + r8s 块）

```bash
cat > r8s_in.txt <<'EOF'
#NEXUS
begin trees;
tree tree_1 = [&R] (((laame:0.46,plost:0.49):0.11,(parub:0.27,sccit:0.34):0.28):0.09,(lasul:0.40,phgig:0.47):0.09);
end;
begin r8s;
blformat lengths=persite nsites=429963 ulrametric=no;
MRCA BOL sccit parub;
MRCA AGC laame plost parub sccit;
fixage taxon=BOL age=89;
fixage taxon=AGC age=246;
end;
EOF
```

### 2. 交叉验证选 smoothing 参数

```bash
for ((i=-9;i<=9;i=i+1)); do
    mkdir -p tmp_$i && cp r8s_in.txt tmp_$i/
    echo "divtime method=PL algorithm=TN crossv=yes fossilfixed=yes cvstart=$i cvinc=0.1 cvnum=10;" >> tmp_$i/r8s_in.txt
    # 等价：python main.py run tmp_$i/r8s_in.txt > tmp_$i/r8s_out.txt
    r8s -b -f tmp_$i/r8s_in.txt > tmp_$i/r8s_out.txt
done
# 取 Fract_Error 最小者
for ((i=-9;i<=5;i=i+1)); do grep -P "^\s+-?\d+" tmp_$i/r8s_out.txt; done \
    | sort -k3 -k4 -n | grep Good | head -n 1 | perl -pe 's/\s+/\t/g' | cut -f 3 > best_smoothing_value.txt
```

### 3. 正式分歧时间计算

```bash
echo "set smoothing=$(cat best_smoothing_value.txt);
divtime method=PL algorithm=TN;
showage;
describe plot=chrono_description;
end;" >> r8s_in.txt
python main.py run r8s_in.txt > r8s_out.txt   # 等价 r8s -b -f r8s_in.txt > r8s_out.txt
```

### 4. 参数说明

| 指令 / 参数                       | 说明                                    |
| ----------------------------- | ------------------------------------- |
| `blformat lengths=persite`    | 分枝长度单位（每碱基替换数）                        |
| `nsites`                      | 比对位点数（与序列长度一致）                        |
| `fixage taxon=... age=...`    | 化石校准点（固定某节点年龄，单位 Myr）                 |
| `MRCA <名> <物种...>`            | 定义单系类群节点                              |
| `divtime method=PL`           | 惩罚似然分歧时间（`algorithm=TN` 截断牛顿法）         |
| `crossv=yes ... cvstart/cvinc` | 交叉验证选 smoothing（cvstart 起始、cvinc 步长）   |
| `set smoothing=<v>`           | 设定最终 smoothing 参数                      |
| `showage` / `describe`        | 输出节点年龄 / 树描述（`plot=chrono_description`） |

## 环境安装（官方渠道无镜像/conda；官方源码编译 + 本地自建容器）

官方渠道（bioconda → quay.io/biocontainers → depot.galaxyproject.org）**均无** r8s 包/镜像（2026-09 核实全 404），故 native/ 保留自建容器配方（`Dockerfile` / `Apptainer.def`）；宿主机推荐官方源码编译或 brew。

### 1. Conda / brew（包管理器安装）

```bash
# conda：官方无 r8s 包（bioconda recipes/r8s 2026-09 核实 404）——conda 路线不可用，请走 brew 或源码编译
```

```bash
# 或用 Homebrew（macOS / Linux；公式在 brewsci/bio tap，需先添加 tap）
brew tap brewsci/bio     # 首次使用需要
brew install r8s
r8s -v -b                # 断言（打印 r8s version 1.81；退出码 1 属正常）
```

> 一键安装也可直接运行 `native/install.sh`（无 conda 包，走官方源码编译：下载 SourceForge `r8s1.81.tar.gz`，补丁 makefile 后 `make` 编译到 `~/software/r8s-1.81` 并写 PATH；版本默认 1.81，与下方 `software_versions` 对齐。用法：`bash native/install.sh --help`）。

### 2. Docker（本地自建镜像）

官方无镜像，故本地自建（`native/Dockerfile`，context 为 `modules/`）：

```bash
docker build -t bioskills/r8s:1.81 -f modules/r8s/native/Dockerfile modules/
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/r8s:1.81 -b -f /data/r8s_in.txt
```

### 3. Apptainer / Singularity

官方无 depot sif，故用本地自建定义文件构建：

```bash
apptainer build r8s.sif modules/r8s/native/Apptainer.def
apptainer run -B $PWD:/data -H /data r8s.sif -b -f /data/r8s_in.txt
```

### 4. 官方源码编译（官方唯一源码路线）

官方**不提供** Linux 预编译二进制包，源码归档即唯一官方来源（已核实）；框架：

```bash
curl -fsSL -o ~/software/r8s1.81.tar.gz \
    https://downloads.sourceforge.net/project/r8s/r8s1.81.tar.gz
tar zxf ~/software/r8s1.81.tar.gz -C ~/software/
cd ~/software/r8s1.81/src
# 补丁：去系统头依赖 + gfortran 10+ 实参不匹配放行 + 旧 C 用 -fcommon
sed -e 's#/usr/include/[^ ]*##g' makefile > makefile.new && mv makefile.new makefile
make FC=gfortran CC=gcc LPATH= CFLAGS="-O2 -w -fcommon" FFLAGS="-fallow-argument-mismatch -w" -j 4 r8s
install -m 0755 r8s ~/software/r8s-1.81/bin/r8s
echo 'export PATH=$PATH:~/software/r8s-1.81/bin' >> ~/.bashrc && source ~/.bashrc
r8s -v -b                # 断言（r8s version 1.81）
```

## 测试

```bash
bash native/test/run_test.sh   # argv 构造验证 + 自省断言；r8s 已安装则额外冒烟
```

## 容器与 Conda 链接

* **官网 / 下载**：<https://sourceforge.net/projects/r8s/>

* **官方源码**：<https://downloads.sourceforge.net/project/r8s/r8s1.81.tar.gz>（sha256 `9e89d785…`）

* **Homebrew**：<https://github.com/brewsci/homebrew-bio/blob/master/Formula/r8s.rb>（`brew tap brewsci/bio && brew install r8s`）

* **Docker / Apptainer**：官方无镜像，本地自建 → `modules/r8s/native/Dockerfile`、`modules/r8s/native/Apptainer.def`

* **Conda**：官方无包（bioconda `r8s` 2026-09 核实 404）

* 官方无 nf-core 模块（`modules/nf-core/r8s` 404）、无 snakemake-wrappers（`bio/r8s` 404）——如需流程集成请以本模块 `native/main.py` 兜底。

## 版本

* r8s **1.81**（官方源码 `r8s1.81.tar.gz`，`make` 编译）

* 构建路线：无官方 conda/容器渠道 → 本地自建容器（debian:bookworm-slim + gfortran/gcc 源码 make）

* 与 brew brewsci/bio 公式同源（同一 SourceForge tarball，sha256 一致）
