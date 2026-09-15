#!/usr/bin/env python3
"""生成 ballgown native 测试用合成数据（模拟 StringTie 输出目录）。

产出（<outdir> 下）：
  stringtie_out/sample1..sample6/{sampleN_e_data.ctab, _t_data.ctab, _i_data.ctab}
      占位型 StringTie 输出（含表头的最小 ctab；仅用于 argv/脚本构造测试）
  coldata.txt
      分组表（sample, condition；control×3 + treatment×3）
"""
from __future__ import annotations

import sys
from pathlib import Path

SAMPLES = [f"sample{i}" for i in range(1, 7)]
CONDITIONS = ["control"] * 3 + ["treatment"] * 3

# 各 ctab 的最小表头（占位，不参与真实 Ballgown 计算）
CTAB_HEADER = {
    "e_data": "e_id\tgene_id\tchr\tstart\tend\tstrand",
    "t_data": "t_id\tgene_id\tchr\tstart\tend\tstrand",
    "i_data": "i_id\tt_id\tgene_id\tchr\tstart\tend\tstrand",
}


def main() -> int:
    if len(sys.argv) != 2:
        print(f"用法: {sys.argv[0]} <outdir>", file=sys.stderr)
        return 2
    outdir = Path(sys.argv[1])
    outdir.mkdir(parents=True, exist_ok=True)

    st = outdir / "stringtie_out"
    st.mkdir(exist_ok=True)
    for s in SAMPLES:
        sdir = st / s
        sdir.mkdir(exist_ok=True)
        for kind, header in CTAB_HEADER.items():
            (sdir / f"{s}_{kind}.ctab").write_text(header + "\n")

    with open(outdir / "coldata.txt", "w") as fh:
        fh.write("sample\tcondition\n")
        for s, c in zip(SAMPLES, CONDITIONS):
            fh.write(f"{s}\t{c}\n")

    print(f"已生成 Ballgown 测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
