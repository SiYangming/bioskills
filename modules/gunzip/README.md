# gunzip 软件模块

> 汇总说明：本 README 合并各实现（native/snakemake/nextflow）的用法；安装方式见下方各节，容器与 conda 环境信息记录于此。

---

## native 实现

# gunzip / native

自包含的 gunzip 驱动实现（`source_type: custom`），命令逻辑迁移自
`snakemake.smk/isoseq.smk/workflow/modules/gunzip/snakemake/gunzip.smk`（`gzip -cd <in.gz> > <out>`）。

## 能力

| 子命令 | 说明 | 线程 |
|--------|------|------|
| `gunzip` | 解压 .gz 文件（`gzip -cd <in.gz> > <out>`） | —（单线程） |

## 快速开始

### 1. 安装环境

```bash
mamba env create -f environment.yml
conda activate gunzip-native
```

### 2. CLI 调用

```bash
python main.py gunzip genome.fa.gz -o genome.fa
python main.py gunzip reads.fq.gz          # 默认输出 reads.fq
```

### 3. Agent / Schema 自省

```bash
python main.py --schema              # 输出 JSON Schema
python main.py --list-commands       # 列出支持的子命令
```

### 4. 容器运行

```bash
docker build -t bioskills/gunzip:1.12-v1.0 -f Dockerfile .
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data bioskills/gunzip:1.12-v1.0 \
  gunzip /data/genome.fa.gz -o /data/genome.fa
```

### 5. 测试

```bash
bash test/run_test.sh
```

## 说明

- 二进制为 `gzip`（`gunzip` 是其硬链接前端）；`gzip -cd` 同时兼容 GNU gzip 与 macOS 系统 gzip。
- 成功后会在输出文件同目录写 `versions.yml`（与 nf-core/gunzip 对齐）。
- 临时目录/线程参数（`--tmpdir` / `--threads`）按 skill 统一契约保留；`gzip -cd` 本身单线程。


---

## snakemake 实现

# gunzip / snakemake / local — 自定义 Snakemake 实现

> 本目录为 snakemake-wrappers 官方缺失（bio/gunzip 404）时的 **Snakemake 自维护 rule**。
> 规则从 `snakemake.smk/isoseq.smk/workflow/modules/gunzip/snakemake/gunzip.smk` 迁移，去掉了对
> `workflow/lib/helpers.py` 的全局依赖（docker_run / GUNZIP_DOCKER_IMAGE）。

## 使用方式

```python
# Snakefile 中引入（可按需 use 重命名避免规则冲突）
include: "modules/gunzip/snakemake/gunzip.smk"
# 或
use rule gunzip from rule_gunzip as gunzip
```

## 规则清单

| 规则 | 作用 | 迁移自 |
|------|------|--------|
| `gunzip` | `gzip -cd <in.gz> > <out>`（wildcard_constraints 保证不重复解压 .gz） | `gunzip.smk:gunzip` |

## 示例

```python
# 目标：把 results/xxx.fa.gz 解压为 results/xxx.fa
rule gunzip_demo:
    input:  "results/{sample}.fa.gz"
    output: "results/{sample}.fa"
```

## 与原 isoseq.smk 的差异

- 移除 `docker_run` / `GUNZIP_DOCKER_IMAGE`（容器由调用方在 rule 上声明）。
- 移除 `log` 重定向（需要日志时在调用方 rule 补充 `log:` + `2> {log}`）。
- `gzip_bin` 保留 config 可覆盖（默认 `gzip`）。


---

## Conda 环境（原 native/environment.yml）

```yaml
# gunzip native Conda 环境配方（兜底：离线 / 非容器场景）
# 创建：mamba env create -f environment.yml
# 注意：gzip 在 conda-forge（非 bioconda）。
name: gunzip-native
channels:
  - conda-forge
dependencies:
  - python=3.11
  - gzip=1.12
  - pyyaml>=6.0
  - pip
  - pip:
      - -e .  # 若把 native/ 打包为可安装包（可选）
```
