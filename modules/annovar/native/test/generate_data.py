#!/usr/bin/env python3
"""生成 annovar native 测试用的合成输入。

ANNOVAR 的注释需要真实注释数据库（humandb/ 下 refGene 等）才能产出结果，合成数据无法
覆盖真实注释计算。因此本脚本生成「最小可解析的占位输入」，run_test.sh 用 python 构造 argv
验证命令构建不崩溃（monkeypatch _resolve_binary，不依赖已安装 annovar）。

产出：
  <outdir>/variants.vcf                        最小 VCF（table_annovar/geneanno 输入）
  <outdir>/humandb/README.placeholder          注释库占位目录
  <outdir>/humandb/hg38_refGene.txt            注释库占位文件
  <outdir>/annovar/table_annovar.pl            脚本占位（模拟 ANNOVAR_HOME 布局）
  <outdir>/annovar/annotate_variation.pl       脚本占位
"""
from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    (outdir / "variants.vcf").write_text(
        "##fileformat=VCFv4.2\n"
        "##contig=<ID=chr1,length=1000>\n"
        "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n"
        "chr1\t100\t.\tA\tG\t50\tPASS\t.\n",
        encoding="utf-8",
    )
    dbdir = outdir / "humandb"
    dbdir.mkdir(exist_ok=True)
    (dbdir / "README.placeholder").write_text(
        "# PLACEHOLDER: ANNOVAR 注释库（真实使用需 annotate_variation.pl -downdb 下载）\n",
        encoding="utf-8",
    )
    (dbdir / "hg38_refGene.txt").write_text(
        "# PLACEHOLDER refGene table\n", encoding="utf-8"
    )
    annodir = outdir / "annovar"
    annodir.mkdir(exist_ok=True)
    for name in ("table_annovar.pl", "annotate_variation.pl"):
        (annodir / name).write_text(
            "#!/usr/bin/perl\n# PLACEHOLDER ANNOVAR script\nprint \"ANNOVAR placeholder\\n\";\n",
            encoding="utf-8",
        )
    print(f"已生成测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
