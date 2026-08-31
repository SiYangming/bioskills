# skills/custom/ 目录

复合流程（composite / multi-stage）的统一存档目录。

命名建议：<引擎/领域>_<语义名称>（全小写，下划线分词）。例如：

- `dna_seq_align_qc`  — 本次提供的短读 DNA 比对 + QC 最小骨架
- `rna_seq_star_salmon`（后续可加）
- `wgs_sv_smoove_svaba`（后续可加）

每个子流程至少包含：
- `meta.yaml`：声明 stages / inputs / outputs / dependencies_in_skills
- 一个入口脚本或编排脚本（如 `*.py`）+ `workflow_skeleton/` 放 Snakefile.template / main.nf.template
- `README.md`：说明用法、与 skills/<sw>/ 各实现的依赖关系
