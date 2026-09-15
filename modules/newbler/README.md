# newbler 软件模块（Newbler 2.9 / GS De Novo Assembler）

> ⚠️ DEPRECATED — 已淘汰，仅历史参考登记
>
> **Newbler（gsAssembler）** 是 Roche / 454 Life Sciences 为 **454 焦磷酸测序**数据
> 开发的 de novo 组装器（Overlap-Layout-Consensus 算法），随 GS De Novo Assembler
> 软件（`DataAnalysis_2.9_All`）分发，主程序 `runAssembly` / `runMapping`。
> 随着 **454 测序平台淘汰**（Roche 2013 宣布、2016 全面退出），Newbler 已停止更新；
> 官网 **454.com 2026-09 探测为 JS 跳转占位页**（`software-request.asp` 不再提供下载）。
>
> **新项目请勿使用**——454 组装已被 **SPAdes / SOAPdenovo2 / MaSuRa** 等现代短读组装器
> 替代。本模块只做「录入」：方法/命令/链接准确登记，**不产出自建容器配方**
> （Dockerfile/Apptainer.def），仅供复现 2010 年代的 454 组装分析。

***

## native 实现（说明型 / 命令构造，`source_type: custom` / `type: native`）

本实现为「说明型 + 命令构造」：`native/main.py` 按 Newbler 官方命令语义构造
`runAssembly` / `runMapping` 命令行并打印，**不实际执行**（软件 deprecated、官网停服、
无新用场景）。两个子命令：

| 子命令        | 实际构造命令                                                          | 作用                              |
| ---------- | --------------------------------------------------------------- | ------------------------------- |
| `assemble` | `runAssembly -o <outdir> -force -tr <reads.sff>`                  | 454 de novo 组装 → contigs / isotigs |
| `map`      | `runMapping -o <outdir> -force -tr <reads.sff> <reference.fasta>` | 454 读取回贴参考序列                    |

```bash
# CLI 直跑（构造历史命令，仅供复现；需先装 Newbler，见「环境安装」）
python main.py assemble -r 454Reads.sff -o ./
python main.py map -r 454Reads.sff -R reference.fasta -o ./

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads`（Newbler 无 `--threads` 旗标，仅记录）与 `--tmpdir`。
构造命令通过 stderr 打印 deprecated 提示，stdout 只输出命令本身。

## 实战示例（历史）

```bash
mkdir -p 04.genome_assembling/Newbler
cd 04.genome_assembling/Newbler

# 使用 runAssembly 进行组装
#   -o ./: 输出目录     -force: 强制输出到已存在的目录     -tr: 使用 trimmed reads
runAssembly -o ./ -force -tr ~/00.incipient_data/data_for_genome_assembling/454Reads.sff
```

> 等价能力由 `native/main.py` 的 `assemble` 子命令提供（见上「用法」）。

### 参数说明（录入）

| 参数         | 说明                                       |
| ---------- | ---------------------------------------- |
| `-o <dir>` | 输出目录（`runAssembly`/`runMapping`）          |
| `-force`   | 强制输出到已存在的目录                              |
| `-tr`      | 使用 trimmed reads（不加则用 untrimmed）          |
| `<reads>`  | 位置参数：454 reads（SFF 格式，如 `454Reads.sff`）    |
| `<ref>`    | `runMapping` 位置参数：参考序列 FASTA             |

## 环境安装（已淘汰：无官方渠道，仅历史复现说明）

> 渠道核实（2026-09）：**无任何官方渠道** —— bioconda `newbler` 404；quay.io/biocontainers/newbler
> 无；depot.galaxyproject.org 无；nf-core modules、snakemake-wrappers、homebrew-core/brewsci-bio
> 两源均无。官网 454.com 已停服。软件 deprecated → **不产出自建容器配方**（无 Dockerfile/Apptainer.def）。

### 历史复现步骤（需自备官方安装包）

1. 解压安装包 `DataAnalysis_2.9_All_20130530_1559.tgz`：

   ```bash
   tar zxf ~/software/DataAnalysis_2.9_All_20130530_1559.tgz
   cd DataAnalysis_2.9_All/
   ```

2. 安装 32 位运行库（Newbler 依赖 i686 库；现代 64-only 发行版需 multilib）：

   ```bash
   sudo yum --disablerepo=* --enablerepo=c6-media -y install \
       zlib* libXi* libXtst* libXaw* zlib*i686 libXi*i686 libXtst*i686 libXaw*i686
   ```

3. 运行安装脚本 `./setup.sh`（交互式设定安装路径；历史惯例 `/opt/biosoft/454`，
   **本仓库建议改用户前缀**，避免写 `/opt`）：

   ```bash
   ./setup.sh
   ```

4. 加 PATH 并验证：

   ```bash
   echo 'export PATH=$PATH:<安装目录>/bin/' >> ~/.bashrc && source ~/.bashrc
   runAssembly            # 无参数应打印用法
   ```

> 说明：官网 454.com 已停服，上述安装包需自行从历史存档获取；`install.sh` 为
> **说明型脚本**（不下载、不安装，仅打印以上步骤）：`bash native/install.sh --explain`。

### 替代建议（新项目请直接使用）

| 替代工具 | 说明 | 官方入口 |
| ---- | ---- | ---- |
| **SPAdes** | 短读 de novo 组装主流工具（bioconda `spades`） | <https://github.com/ablab/spades> |
| **SOAPdenovo2** | 大规模基因组短读组装（bioconda `soapdenovo2`） | <https://github.com/aquaskyline/SOAPdenovo2> |
| **MaSuRCA** | 混合（短读+长读）组装 | <https://github.com/alekseyzimin/masurca> |

## 测试

```bash
bash test/run_test.sh   # argv 构造 + parser + schema 自省为常驻断言（不下载/不编译不执行）；
                        # stub 假二进制 CLI 冒烟恒跑
```

## 版本

* **Newbler 2.9**（GS De Novo Assembler；安装包 `DataAnalysis_2.9_All_20130530_1559.tgz`，
  官网 454.com 2026-09 已停服不可下载）
* License：**proprietary**（Roche / 454 Life Sciences 商业软件，需向 Roche 申请许可；
  2026-09 官网停服，许可条款无法在线复核，未使用 SPDX）
* 渠道：无官方 conda / 镜像 / brew / nf-core / snakemake-wrappers（2026-09 全部核实无）
* nf-core / snakemake-wrappers：无官方子模块（2026-09 核实 `modules/nf-core/newbler`、
  `bio/newbler` 均 404）→ 不登记官方说明层
* 软件 deprecated → 不产出自建容器配方
* 社区归档仓库：<https://github.com/SiYangming/newbler>
