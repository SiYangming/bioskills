***

name: "bioskills-package-standardizer"
description: "标准化 bioskills 新增软件包（5 实现 + 版本差异声明 + apt 容器最小化 + 官方子模块清单对齐 + validate/scan 核验）。每次新增/改 bioskills/<sw> 或维护 fastqc/samtools 时调用。"
-------------------------------------------------------------------------------------------------------------------------------------------

# bioskills-package-standardizer

在本仓库新增一个原子技能 `skills/<canonical-software>/`，或对既有技能做“规范化补齐”时使用。
**触发条件**：

* 用户说“新增 XXX 软件”“补 fastqc 的官方子模块 / meta.yaml”“把 Y 个技能的 Dockerfile 改 apt 最小化”

* 每次对 `skills/<sw>/meta.yaml`、`skills/<sw>/native/Dockerfile`、`skills/<sw>/nextflow/nf-core/meta.yaml`、`skills/<sw>/snakemake/snakemake-wrappers/meta.yaml` 做结构维护

## 0. 最终目录形状（必对齐）

```
skills/<canonical>/                 # samtools / bwa-mem2 / fastqc / multiqc …（全小写连字符）
├── meta.yaml                       # 软件级总览：implementations + default_implementation + software_versions
├── README.md
├── native/
│   ├── meta.yaml                   # type=native source_type=custom
│   ├── main.py                     # 继承 base.SkillBase；必支持 --schema / --list-commands / --threads / --tmpdir
│   ├── environment.yml             # Conda（兜底，用户不装容器时用）
│   ├── Dockerfile                  # apt 最小化优先（§4）
│   ├── Apptainer.def               # apt 最小化优先（§4）；%test 必自检 --list-commands + --schema
│   ├── test/{generate_data.py,run_test.sh}
│   └── README.md
├── nextflow/
│   ├── nf-core/                    # source_type=official type=nextflow_nfcore：说明层，不写源码
│   │   ├── meta.yaml               # source_reference.submodules 必须对齐官方目录；software_versions 声明 samtools/htslib 版本
│   │   ├── module.json
│   │   └── README.md               # 显式“必须 nf modules install，缺失用 ../local”
│   └── local/                      # type=nextflow_local：占位 meta + README 启用方式
└── snakemake/
    ├── snakemake-wrappers/         # type=snakemake_wrappers：说明层，不写源码
    │   ├── meta.yaml               # source_reference.submodules 必须对齐官方目录；software_versions 声明 wrapper tag + bioconda 版本
    │   ├── wrapper.py              # 桥接/规则模板参考（不是重写官方代码）
    │   └── README.md               # 显式“运行时解析 wrapper: 句柄，缺失用 ../local”
    └── local/                      # type=snakemake_local：占位 meta + README 启用方式
```

## 1. 命名与 ID（从 AGENT.md §1 提炼）

* 软件目录名：Canonical Name，全小写，连字符分词。不要写 FastQC / BwaMem2；写 `fastqc` / `bwa-mem2`。

* 实现 ID：`<software>_<impl>` 小写+下划线；type / source\_type / path 必须与下面对照表**双向可回溯**：

| 实现 ID                     | type                 | 相对路径                            | source\_type |
| ------------------------- | -------------------- | ------------------------------- | ------------ |
| `<sw>_native`             | `native`             | `native/`                       | custom       |
| `<sw>_nextflow_nfcore`    | `nextflow_nfcore`    | `nextflow/nf-core/`             | official     |
| `<sw>_nextflow_local`     | `nextflow_local`     | `nextflow/local/`               | custom       |
| `<sw>_snakemake_wrappers` | `snakemake_wrappers` | `snakemake/snakemake-wrappers/` | official     |
| `<sw>_snakemake_local`    | `snakemake_local`    | `snakemake/local/`              | custom       |

## 2. 软件级 meta.yaml 必加 `software_versions`

**native / nf-core / snakemake-wrappers / local 支持的软件二进制版本可能不同**，必须在软件级 meta.yaml 显式声明，以方便做跨实现兼容性判断。示例可直接照抄 `skills/samtools/meta.yaml` 顶部：

```yaml
software_versions:
  - id: <sw>_native
    samtools: "<软件 apt/conda 版本>"  # 按实际软件改字段名（fastqc / bwa_mem2 等）
    note: "apt 路线 / Conda 路线；版本来源"
  - id: <sw>_nextflow_nfcore
    module_version: "2.2.0"
    samtools: "1.24"
    source: "bioconda::<sw>=<版本>（modules/nf-core/<sw>/*/environment.yml）"
    note: "何时 bump；若固定 tag < X，可能回落到旧版本"
  - id: <sw>_snakemake_wrappers
    wrapper_tag: "v3.13.0"
    samtools: "1.24"
    source: "bioconda <sw>=<版本>（bio/<sw>/*/environment.yaml）"
  - id: <sw>_nextflow_local / <sw>_snakemake_local
    <sw>: "未固定（用户按 main.nf / rules/ 自行声明）"
```

对应实现级 meta.yaml 里**也要写一份** `software_versions:` 字段（不必重复软件级全部，但要写本实现对应的版本与来源）。

## 3. 官方说明层三件套：submodules 必须对齐官方目录

### nextflow/nf-core

1. 打开 `https://github.com/nf-core/modules/tree/master/modules/nf-core/<sw>`
2. 用 `WebFetch` + `grep -oE .../tree/master/modules/nf-core/<sw>/[^)"<]+` 提取最后一段目录名。
3. 去重排序后写进 `source_reference.submodules`，并在 `submodules_note` 里声明“以官方在线目录为准”。
4. 在 `software_versions` 中：

   * 抓 `https://raw.githubusercontent.com/nf-core/modules/master/modules/nf-core/<sw>/sort/environment.yml`（或典型子模块）作为 bioconda 版本锚点；

   * 记录 `module_version`（nf-core modules 家族版本，如 2.2.0）+ 工具二进制版本（如 samtools=1.24）。

### snakemake/snakemake-wrappers

1. 打开 `https://github.com/snakemake/snakemake-wrappers/tree/master/bio/<sw>`
2. 同法提取子目录名列表写进 `source_reference.submodules`。
3. 抓 `https://raw.githubusercontent.com/snakemake/snakemake-wrappers/master/bio/<sw>/sort/environment.yaml` 作为版本锚点；
4. 在 `software_versions` 写 `wrapper_tag`、`samtools/fastqc=...`、`snakemake-wrapper-utils=...`。

### README 强提示（必写）

* nf-core README 必须声明：“本目录仅说明 + Schema；执行前请 `nf modules install nf-core <sw> <sub1> <sub2> …`；缺失时用 `../local/` 兜底。”

* snakemake-wrappers README 必须声明：“本目录仅说明层；运行时靠 `wrapper: "vX.Y.Z/bio/<sw>/<sub>"` 解析；缺失时用 `../local/` 兜底。”

## 4. native 容器：apt 最小化优先，Conda 仅做兜底

**原则（已在 samtools 1.21 上验证可行）**：

* 底座固定 `debian:bookworm-slim`（或 `ubuntu:24.04` 若 bookworm apt 版本过旧）。

* `DEBIAN_FRONTEND=noninteractive` + `apt-get install -y --no-install-recommends <软件=pin版本> python3-minimal python3 ca-certificates procps (tini)`。

* 安装后立刻 `rm -rf /usr/share/{doc,man,info,locale}/* /var/cache/debconf/* /var/lib/apt/lists/* /tmp/* /var/tmp/*`。

* 构建末尾加**版本断言**：`dpkg -l | awk '$2=="<pkg>"{print $3}' | grep -Eq '^X\.Y(-|$)'`，避免 `bookworm-upgrades` 偷偷升级。

* ENTRYPOINT 建议 `/usr/bin/tini -- python3 /opt/skill/main.py`；不写 tini 也行，但要在注释注明。

* 若软件**不在 Debian stable apt 源**（典型如 fastqc、multiqc、R 包）：

  * 优先查 Debian tracker / backports；

  * 没有时，再用“bookworm-slim + 仅装 openjdk/python/r 基础 + 把 jar/whl 通过 COPY 或 ghcr.io/biocontainers 二层拷贝进 /opt/conda”的形式，但仍然保持 apt 清理步骤，拒绝“整 miniconda + 全量 channel 依赖”路线。

* 保留下 `environment.yml` 作为 Conda 兜底（用户 HPC 无 root）；Dockerfile/Apptainer.def 顶部注释明确写“路线：apt 最小化优先；Conda 兜底”。

## 5. custom/<flow> 复合流程骨架标准

每次在 `skills/custom/` 下新增流程时必包含：

* `meta.yaml`：`category: custom type: custom_workflow source_type: custom`；`stages[]` 列出依赖软件实现 ID；`inputs/outputs/dependencies_in_skills`。

* 一个入口脚本：如 `dna_seq_align_qc.py`，至少支持 `--help` / `--list-stages` / `--dry-run`（无外部依赖可跑）；`--real` 时才调用 `skills/<sw>/native/main.py`。

* `workflow_skeleton/Snakefile.template` + `workflow_skeleton/main.nf.template`：复制到真实项目即能用的模板。

* `README.md`：流程图（fastp → bwa-mem2 → samtools sort/index 这种 ASCII 形式）+ 启用条件。

* `custom/README.md` 全局存在，给出流程命名约定（`<engine_domain>_<semantic_name>` 全小写下划线）。

## 6. 交付前的硬核验清单（Checklist）

修改完一个软件后，**必须全绿**再收工：

```bash
# 1) validate 五个目录（含 local 占位）——必须全 [OK]
python3 skills/bin/skill-cli validate skills/<sw>/native
python3 skills/bin/skill-cli validate skills/<sw>/nextflow/nf-core
python3 skills/bin/skill-cli validate skills/<sw>/nextflow/local
python3 skills/bin/skill-cli validate skills/<sw>/snakemake/snakemake-wrappers
python3 skills/bin/skill-cli validate skills/<sw>/snakemake/local

# 2) YAML 语法 + 关键字段存在性自检（python 直读）
python3 - <<'PY'
from pathlib import Path
import yaml
for p in [Path("skills/<sw>/meta.yaml"),
          Path("skills/<sw>/nextflow/nf-core/meta.yaml"),
          Path("skills/<sw>/snakemake/snakemake-wrappers/meta.yaml")]:
    d = yaml.safe_load(p.read_text())
    n_sub = len(d.get("source_reference",{}).get("submodules",[]))
    print(p.name, "submodules:", n_sub, "software_versions:", "software_versions" in d)
    assert "software_versions" in d, p.name+" missing software_versions"
PY

# 3) 重建全局 registry（不应丢任何实现）
python3 skills/bin/skill-cli scan

# 4) native 回归：若本机装了二进制，必须跑；没装则 --schema / --list-commands 自省测试必须通过
bash skills/<sw>/native/test/run_test.sh
```

若要把 fastqc / samtools 的 Dockerfile 再“再瘦一圈”，可以：

* 进一步用 multi-stage，把 COPY 文件放到 runtime stage（保持 BuildKit 语法时不要用 `--mount=type=cache` 在 CI 不可用的环境）。

* 将 Apptainer.def 切到 `Bootstrap: localimage` 时，复用同仓库的 samtools 基础层。

