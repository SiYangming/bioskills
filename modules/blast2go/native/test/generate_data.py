#!/usr/bin/env python3
"""生成 blast2go native 测试用合成输入。

Blast2GO / b2g4pipe 需真实 BLAST XML + 本地注释库（MySQL）+ Java 才能产出注释结果，
合成数据无法覆盖真实计算。因此本脚本生成「最小占位输入」，run_test.sh 用 python 构造
argv 验证命令构建不崩溃（monkeypatch java/perl 解析，不依赖已安装 Blast2GO）。

产出：
  <outdir>/nr.xml                             最小 BLAST XML（outfmt 5，annot 输入）
  <outdir>/b2g4pipe/b2gPipe.properties         b2g4pipe 配置占位
  <outdir>/b2g4pipe/ext/.keep                  ext/ 目录占位
  <outdir>/blast2go-db/install_blast2goDB.sh   本地注释库脚本占位
  <outdir>/Blast2GO/Blast2GO                   客户端启动器占位
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

    (outdir / "nr.xml").write_text(
        '<?xml version="1.0"?>\n'
        '<!DOCTYPE BlastOutput PUBLIC "-//NCBI//NCBI BlastOutput/EN" '
        '"http://www.ncbi.nlm.nih.gov/dtd/NCBI_BlastOutput.dtd">\n'
        "<BlastOutput>\n  <BlastOutput_program>blastp</BlastOutput_program>\n"
        "</BlastOutput>\n",
        encoding="utf-8",
    )

    b2g = outdir / "b2g4pipe"
    (b2g / "ext").mkdir(parents=True, exist_ok=True)
    (b2g / "b2gPipe.properties").write_text(
        "Dbacces.dbname=b2gdb\nDbacces.dbhost=localhost\n", encoding="utf-8"
    )
    (b2g / "ext" / ".keep").write_text("", encoding="utf-8")

    db = outdir / "blast2go-db"
    db.mkdir(exist_ok=True)
    (db / "install_blast2goDB.sh").write_text(
        "#!/usr/bin/perl\n# PLACEHOLDER local_b2g_db installer\nprint \"b2g db placeholder\\n\";\n",
        encoding="utf-8",
    )

    client = outdir / "Blast2GO"
    client.mkdir(exist_ok=True)
    (client / "Blast2GO").write_text(
        "#!/bin/sh\n# PLACEHOLDER Blast2GO launcher\necho 'Blast2GO placeholder'\n",
        encoding="utf-8",
    )

    print(f"已生成 blast2go 测试占位数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
