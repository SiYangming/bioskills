# stringtie 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# stringtie / native — 自包含转录本组装驱动

StringTie 的本地自包含实现（`source_type: custom`、`type: native`），命令逻辑迁移自
`snakemake.smk/nanoseq.smk/nanoseq.sh/run_stringtie.sh`（Nanopore long-read 模式）。

## 功能

三个子命令对应 nanoseq 的 STRINGTIE 三段链路：

| 子命令 | 命令 | 作用 |
|--------|------|------|
| `assemble` | `stringtie <bam> --conservative -L -R -G <gtf> -o <out> -l <label> -m <len> -p N` | 样本级转录本重构 |
| `fix_gtf` | `awk '$4>$5{交换}'` | 修复 GTF 坐标颠倒（纯文本，无需 stringtie） |
| `merge` | `stringtie --merge -G <gtf> -o <merged> -l MSTRG -m <len> <gtf_list>` | 多样本非冗余合并 |

## 用法

```bash
# CLI 直跑
python main.py assemble sample.sorted.bam -G gencode.v49.annotation.gtf -o sample.stringtie.gtf --threads 8
python main.py fix_gtf sample.stringtie.gtf -o sample.stringtie.fixed.gtf
python main.py merge gtf_list.txt -G gencode.v49.annotation.gtf -o stringtie_merged_nonredundant.gtf

# Agent / Schema 自省
python main.py --schema
python main.py --list-commands
```

每个子命令支持 `--threads` / `--tmpdir` 运行期覆盖。

## 环境安装（三选一）

### 1. Conda（HPC 无 root / 离线兜底）

```bash
mamba env create -f environment.yml   # name: stringtie-native
conda activate stringtie-native
```

### 2. Docker

```bash
docker build -t bioskills/stringtie:3.0.3-v1.0 -f Dockerfile .
# 注意：必须 -u $(id -u):$(id -g) 挂载宿主用户，否则产物归 root
docker run --rm -u $(id -u):$(id -g) -v $PWD:/data -w /data \
    bioskills/stringtie:3.0.3-v1.0 assemble \
    sample.sorted.bam -G gencode.v49.annotation.gtf -o sample.stringtie.gtf
```

### 3. Apptainer / Singularity

```bash
apptainer build stringtie.sif Apptainer.def
apptainer run -B $PWD:/data -H /data stringtie.sif assemble \
    /data/sample.sorted.bam -G /data/gencode.v49.annotation.gtf -o /data/sample.stringtie.gtf
```

## 测试

```bash
bash test/run_test.sh   # fix_gtf 为真实回归；assemble/merge 退化为 argv 构造验证
```

## 版本

* stringtie 3.0.3（bioconda::stringtie=3.0.3）
* 构建路线：debian:bookworm-slim + micromamba 引导 bioconda env（stringtie 不在 Debian apt）
* 与 nf-core 子模块 stringtie/stringtie + stringtie/merge 的 bioconda pin 一致

## 历史留存（legacy/）

`legacy/` 存放迁移自 nanoseq 流程 `nanoseq.sh/run_stringtie.sh` 的原始脚本，仅供追溯对照，**正式入口为 `main.py`**。

- `run_stringtie.sh`


---

## snakemake 实现

# stringtie / snakemake / local — 自维护 Snakemake 规则

官方 `snakemake-wrappers` 无 `bio/stringtie`（抓取 404），因此本目录提供自维护 rule，
作为 Snakemake 场景的**主执行路径**（`source_type: custom`、`type: snakemake_local`）。

## 规则文件

- `stringtie.smk` — 三个 rule，对应 nanoseq STRINGTIE 三段链路：
  - `stringtie_assemble`：`stringtie <bam> --conservative -L -R -G <gtf> -o <out> -l <sample> -m 200 -p N`
  - `stringtie_fix_gtf`：`awk -F'\t' '$4>$5{交换}'`（坐标修复，纯文本）
  - `stringtie_merge`：`stringtie --merge -G <gtf> -o <merged> -l MSTRG -m 200 <gtf_list>`

规则迁移自 `snakemake.smk/nanoseq.smk/nanoseq.sh/run_stringtie.sh`，去除
nohup/PID/LOCK 后台运行封装、绝对路径与 GNU parallel 依赖；`gtf_annotation` 走
`config.get(...)` 内联默认值。

## 用法

```python
# Snakefile 中
include: "modules/stringtie/snakemake/stringtie.smk"

# 运行
snakemake -j 8 merged/stringtie_merged_nonredundant.gtf
```

## 依赖环境

规则内 `conda: "envs/stringtie.yaml"`，需要自备：

```yaml
# envs/stringtie.yaml
channels: [conda-forge, bioconda]
dependencies:
  - stringtie=3.0.3
```

## 与其它实现的关系

- 官方 wrapper 若未来出现（重新抓取 bio/stringtie 有目录），可切换回 `../snakemake-wrappers/` 登记层
- 非 Snakemake 场景（独立 CLI / Agent Function Calling）请走 `../../native/`


---

## Conda 环境（原 native/environment.yml）

```yaml
# stringtie native Conda 环境配方
# 创建：mamba env create -f environment.yml
# 说明：stringtie 不在 Debian bookworm apt；本文件是 Conda 兜底（HPC 无 root / 离线场景）。
#      容器默认路线：Dockerfile / Apptainer.def 走 micromamba 引导本环境到 /opt/env。
name: stringtie-native
channels:
  - conda-forge
  - bioconda
dependencies:
  - python=3.11
  - stringtie=3.0.3
  - pyyaml>=6.0
  - pip
```
