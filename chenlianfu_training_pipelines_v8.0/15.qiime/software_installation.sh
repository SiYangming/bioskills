# 1. 先安装conda
# conda is a package manager, Miniconda is the conda installer, and Anaconda is a scientific Python distribution that also includes conda.
# 安装minicoda（https://conda.io/miniconda.html）安装Python3.6版本的Minicoda
#wget https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh -P ~/software
sh ~/software/Miniconda3-latest-Linux-x86_64.sh
# 进入交互式界面：输入yes，按Enter键，表示同意license； 输入安装路径/opt/biosoft/miniconda3_for_QIIME2，按enter键； 设置是否添加Minicoda3的PATH变量，直接按Enter键，表示选择no，以免和系统自带的软件冲突。若需要切换到本miniconda3环境，输入命令export PATH=/opt/biosoft/miniconda3_for_QIIME2/bin:$PATH即可。

# 更新minicoda3
PATH=/opt/biosoft/miniconda3_for_QIIME2/bin:$PATH
# 升级conda
conda update conda

# 2. 联网安装QIIME 2 (https://docs.qiime2.org/2020.6/install/native/)
wget https://data.qiime2.org/distro/core/qiime2-2020.6-py36-linux-conda.yml
conda env create -n qiime2-2020.6 --file qiime2-2020.6-py36-linux-conda.yml
rm qiime2-2020.6-py36-linux-conda.yml

# 推荐直接使用已经下载并编译OK的qiime2包解压缩直接安装
tar zxf ~/software/miniconda3_for_QIIME2.tar.gz -C /opt/biosoft

# 3. 使用QIIME2
# 每次使用QIIME 2，都需要先依次载入minicoda3环境，，然后使用minicoda3载入QIIME2环境
PATH=/opt/biosoft/miniconda3_for_QIIME2/bin:$PATH
source activate qiime2-2020.6
# 在BASH下可以自动补齐qiime的命令。
source tab-qiime
# 测试QIIME 2
