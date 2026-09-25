# workflow/snakemake-template — Snakemake 官方流程脚手架

按 AGENT §0A / riboseq 同款：**登记层留仓，脚手架真源外挂**。

## 真源（submodule）

- **上游**：[snakemake-workflows/snakemake-workflow-template](https://github.com/snakemake-workflows/snakemake-workflow-template)
- **本机路径**：[native/](native/)（git submodule，当前钉 `v1.3.0` 一带 commit）
- **元数据**：[meta.yaml](meta.yaml)

```bash
# 克隆 bioskills 后初始化
git submodule update --init workflow/snakemake-template/native

# 查看 / 试跑上游 README 中的用法
cd workflow/snakemake-template/native
snakemake --dry-run
```

## 本目录保留内容

| 文件 | 作用 |
|------|------|
| [meta.yaml](meta.yaml) | 官方链接 / 用途 / init 提示 |
| [snakemake-template.md](snakemake-template.md) | 本说明 |
| [native/](native/) | **git submodule** → 官方模板仓库 |

勿再在 bioskills 内 vendoring 半截拷贝；升级只动 submodule pin。

## 新建业务流程时

1. 以该模板生成/复制骨架到项目目录（勿直接改 submodule 当业务仓）。
2. 规则按需 `include` `modules/<sw>/snakemake/*.smk`。
3. 官方已有完整流程（nf-core 等）→ 不建本地目录，只登记引用。
