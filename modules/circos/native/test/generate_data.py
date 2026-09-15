#!/usr/bin/env python3
"""生成 circos native 测试用的合成输入。

产出：
  <outdir>/karyotype.txt   最小染色体组型（chr1/chr2）
  <outdir>/circos.conf     最小可渲染配置（引用同一目录 karyotype.txt）
说明：Circos 渲染需完整 Perl 依赖，若宿主机未安装 circos，run_test.sh 退化为
「python 构造 argv 验证命令构建不崩溃」；装了 circos 则真实渲染并断言 PNG。
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

    (outdir / "karyotype.txt").write_text(
        "chr - chr1 chr1 0 5000000 black\n"
        "chr - chr2 chr2 0 3000000 black\n",
        encoding="utf-8",
    )
    (outdir / "circos.conf").write_text(
        f"karyotype = {outdir / 'karyotype.txt'}\n"
        "chromosomes_units = 1000000\n"
        "\n"
        "<ideogram>\n"
        "  <spacing>\n"
        "    default = 0.005r\n"
        "  </spacing>\n"
        "  radius = 0.90r\n"
        "  thickness = 20p\n"
        "  fill = yes\n"
        "</ideogram>\n"
        "\n"
        "<image>\n"
        f"  dir = {outdir}\n"
        "  file = circos.png\n"
        "  png = yes\n"
        "  radius = 1000p\n"
        "</image>\n",
        encoding="utf-8",
    )
    print(f"已生成测试数据 -> {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
