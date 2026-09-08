#!/usr/bin/env python3
"""aspera-connect 测试数据生成（保持仓库轻量：不提交真实下载文件）。

ascp 需要真实 FASP 服务端（NCBI/EBI）才能实际传输，合成数据无法覆盖真实网络传输；
因此本脚本只生成：1) 一条示例远端路径清单（文档/argv 断言引用，SRR797242 为 README 示例
accession，勿当真下载对象）；2) 一个本地下载目标占位目录；3) 一份密钥占位说明。
run_test.sh 的断言以「python 构造 argv 验证命令构建不崩溃 + 必填校验」为主。
"""

from __future__ import annotations

import sys
from pathlib import Path


def main(outdir: str) -> None:
    work = Path(outdir)
    work.mkdir(parents=True, exist_ok=True)

    # 示例远端路径（NCBI SRA 布局；SRR797242 为 README 实战示例 accession）
    paths = work / "sra_paths.txt"
    paths.write_text(
        "/sra/sra-instant/reads/ByRun/sra/SRR/SRR797/SRR797242\n",
        encoding="ascii",
    )

    # 本地下载目标占位目录（真实下载请建空目录后挂载/进入）
    destdir = work / "downloads"
    destdir.mkdir(exist_ok=True)

    # 密钥占位说明（密钥本体属 IBM 随包资产，不随仓库分发）
    keynote = work / "KEY_README.txt"
    keynote.write_text(
        "公共数据源密钥（asperaweb_id_dsa.openssh）随 IBM Aspera Connect 安装包分发，位于安装目录\n"
        "etc/ 下（如 ~/.aspera/connect/etc/asperaweb_id_dsa.openssh）；不随 bioskills 仓库分发。\n"
        "社区报告 Connect 4.2+ 或不再随包提供该密钥（未核实 IBM 官方说明）→ 缺失时 -i 显式指定。\n",
        encoding="utf-8",
    )

    print(f"[generate_data] wrote {paths}, {destdir}, {keynote}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: generate_data.py <outdir>", file=sys.stderr)
        raise SystemExit(2)
    main(sys.argv[1])
