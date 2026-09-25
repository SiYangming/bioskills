# workflow/riboseq — 核糖体足迹（Ribo-seq / RPF）+ 总 RNA 测序

基于上游改版：真源在 fork，bioskills 以 **git submodule** 挂载（AGENT §0A）。

## 真源（fork）

- **Fork**：<https://github.com/SiYangming/Ribo-seq>（基于 [Bushell-lab/Ribo-seq](https://github.com/Bushell-lab/Ribo-seq)）
- **本仓挂载**：`workflow/riboseq/native` → 上述 fork 的 git submodule（钉死 commit，见 `.gitmodules`）
- **chr20 测试模块**：fork 内 `test/`（`bash test/run_smoke.sh` 校验环境；FASTQ + 参考已入库）
- **编排入口**：submodule 根目录 `./run.sh --pipeline RPFs|Totals|Downstream`

### 克隆本仓时拉取 submodule

```bash
git clone --recurse-submodules https://github.com/SiYangming/bioskills.git
# 若已 clone 未带 submodule：
git submodule update --init --recursive workflow/riboseq/native
```

### 在 submodule 内跑冒烟 / 流程

```bash
cd workflow/riboseq/native
bash test/run_smoke.sh
./run.sh --pipeline Totals \
  --input-csv test/info.csv \
  --fasta-dir test/reference \
  --genome-version v49 \
  --ref-suffix _chr20 \
  --output-dir results/test_smoke \
  --threads 4
```

### 更新 fork 指针（在 fork 有新 commit 后）

```bash
cd workflow/riboseq/native
git fetch origin
git checkout <commit-or-main>   # 或: git pull origin main
cd ../../..
git add workflow/riboseq/native
git commit -m "chore(riboseq): bump Ribo-seq submodule"
```

脚本改动请在 **SiYangming/Ribo-seq** 提交并推送，再 bump 本仓 gitlink；勿在 bioskills 内另复制一份工作树。

## 本目录保留内容

| 文件 | 作用 |
|------|------|
| [riboseq.yaml](riboseq.yaml) | stages / 依赖 modules / fork 与 submodule 登记 |
| [riboseq.md](riboseq.md) | 本说明 |
| [native/](native/) | **git submodule** → [SiYangming/Ribo-seq](https://github.com/SiYangming/Ribo-seq) |

完整 Shell/Python/R 脚本、conda yml、`test/` 冒烟数据以 **SiYangming/Ribo-seq** 为准。

## 其他执行方式

- **Snakemake**：按需在项目内重建（规则复用 `modules/*/snakemake/`）；见历史说明时可对照 fork README。
- **nf-core**：官方 [nf-core/riboseq](https://github.com/nf-core/riboseq) —— 不建本地 nextflow/ 目录，仅引用。

## UMI 子组合

可复用 [subworkflow/umi_tools_extract_dedup](../../subworkflow/umi_tools_extract_dedup/umi_tools_extract_dedup.md)。
