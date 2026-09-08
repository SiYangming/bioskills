#!/opt/lrs-venv/bin/python3
"""longreadsum 启动器（容器内 /usr/local/bin/longreadsum）。

镜像内布局（Dockerfile / Apptainer.def 约定）：
  /opt/longreadsum/lib   SWIG 生成的 Python 绑定（lrst.py + _lrst*.so）
  /opt/longreadsum/src   longreadsum Python 源码（cli.py / generate_html.py / plot_utils.py / pod5_module.py）
Python 运行依赖（numpy/plotly/pyarrow/pod5）由 /opt/lrs-venv 提供（shebang 直指其解释器）。

注入 lib/src 后调用官方 cli.main()（其 installed 分支 import lrst / generate_html /
plot_utils / pod5_module）。
"""
import os
import sys

sys.path.insert(0, "/opt/longreadsum/lib")
sys.path.insert(0, "/opt/longreadsum/src")
os.environ.setdefault("HDF5_PLUGIN_PATH", "/usr/lib/x86_64-linux-gnu/hdf5/plugin")

from cli import main  # noqa: E402

sys.exit(main())
