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
