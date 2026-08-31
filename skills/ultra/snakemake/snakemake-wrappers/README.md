# ultra / snakemake / snakemake-wrappers

官方 [Snakemake Wrappers](https://github.com/snakemake/snakemake-wrappers) 中 uLTRA 的引用说明与降级桥接脚本。

> ⚠️ **本目录仅为说明 + Schema 挂载层 + 降级桥接脚本**。经 2026-08 核对，
> 官方 snakemake-wrappers **不存在 `bio/ultra` 目录**（GitHub API 返回 404），
> 因此没有任何 `wrapper: "vX.Y.Z/bio/ultra/<subcommand>"` 句柄可被 Snakemake 运行时解析。
> **Snakemake 场景请直接使用 `../local/rule_ultra.smk`**（本技能已内置迁移规则）。

## 目录内容

| 文件 | 作用 |
|------|------|
| `meta.yaml` | 统一抽象接口 Schema、Agent 引导、官方缺失登记 |
| `wrapper.py` | 降级桥接脚本：`available()` / `wrapper_path()` / `defaults()` / `rule()` |
| `README.md` | 本说明 |

## wrapper 清单

**无。** `bio/ultra` 官方不存在（404），无任何子 wrapper 可用。

```bash
# 核对命令（刷新时用）：
curl -s https://api.github.com/repos/snakemake/snakemake-wrappers/contents/bio/ultra
# 期望输出：{"message": "Not Found", ...} （当前状态）
```

## 在 Snakemake 中使用（降级路径）

```python
# 直接在 Snakefile 中引入本地迁移规则
include: "skills/ultra/snakemake/local/rule_ultra.smk"

rule ultra_align_on_sample:
    input:
        reads="reads/{sample}.fa.gz",
        index_flag="results/INDEX/{species}/done"
    output:
        bam="results/ULTRA/{sample}/{sample}.bam"
    threads: 8
    wrapper:
        # 官方缺失；请用本地规则替代，不要直接 include 本目录任何文件
        ...
```

推荐直接用 `rule_ultra.smk`（见 `../local/README.md`）。

## 桥接脚本能力

```bash
python wrapper.py --status        # official wrapper available: False
python wrapper.py index           # 打印降级 rule 参考（include ../local/rule_ultra.smk）
```

## 若官方缺失 / 需定制

请使用 `../local/` 目录的自维护规则（`source_type: custom`、`type: snakemake_local`），
并在软件级 `meta.yaml` 的 `implementations` 登记 `ultra_snakemake_local`。

## 何时选择本实现

- 目标流程语言为 **Snakemake** → 直接走 `ultra_snakemake_local`（官方 wrapper 缺失）。

非流程引擎场景（独立 CLI / Agent Function Calling）请走 `../../native/`。
