# custom/ 目录

复合流程（composite / multi-stage）统一存档目录，分**两层**：

```
custom/
├── workflow/                    # 专门设计流程：面向特定领域的完整流程
│   ├── nanoseq/                 # Nanopore RNA-seq（SRA/dorado -> minimap2 -> samtools -> FLAIR -> StringTie -> ORF）
│   ├── isoseq/                  # PacBio Iso-Seq（CCS -> Lima -> Refine -> BamTools -> GSTAMA -> 比对）
│   └── flrnaseq/                # 全长 RNA-seq ORF 预测（TransDecoder -> TD2 -> ORFfinder）
└── subworkflow/                 # 常用软件组合：可复用的小流程，供 workflow 引用或独立调用
    └── fastp_bwa_samtools/      # fastp -> bwa-mem2 -> samtools sort/index -> QC
```

## 分层约定

| 层级 | 用途 | 特点 |
|------|------|------|
| `workflow/` | 专门设计流程 | 面向特定领域/数据类型的完整流程；可 include subworkflow 与各原子模块规则；编排器（*.py）串联全部 stages |
| `subworkflow/` | 常用软件组合 | 可复用的多软件串联小流程（如 `fastp_bwa_samtools`）；命名用软件名下划线连接；可被 workflow 引用 |

## 每个流程目录的组成

- `meta.yaml`：声明 stages / inputs / outputs / dependencies_in_skills
- 入口编排脚本（如 `*.py`，支持 `--dry-run` / `--real` / `--list-stages`）
- `workflow_skeleton/`：Snakefile.template / main.nf.template / config.yaml 等模板
- `README.md`：说明用法、与 skills/<sw>/ 各实现的依赖关系
- legacy 资产（`LEGACY_*` / 流程级脚本）按「脚本归位」原则处理：专属于某软件的归位到该软件，流程级通用脚本留本目录

## 目录扁平化

`workflow_skeleton/` 下的辅助文件尽量放根级（`config.yaml`、`common.smk`、脚本等），
避免 `config/`/`rules/` 等多级子目录；仅当同层文件确实过多时才建子目录。
