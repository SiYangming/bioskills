# 1. 先安装conda
# conda is a package manager, Miniconda is the conda installer, and Anaconda is a scientific Python distribution that also includes conda.
# 安装minicoda（https://conda.io/miniconda.html）安装Python3.6版本的Minicoda
#wget https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh -P ~/software
sh ~/software/Miniconda3-latest-Linux-x86_64.sh
# 进入交互式界面：输入yes，按Enter键，表示同意license； 输入安装路径/opt/biosoft/miniconda3_for_antiSMASH，按enter键； 设置是否添加Minicoda3的PATH变量，直接按Enter键，表示选择no，以免和系统自带的软件冲突。若需要切换到本miniconda3环境，输入命令export PATH=/opt/biosoft/miniconda3_for_antiSMASH/bin:$PATH即可。

# 2. 安装antiSMASH
# 载入miniconda环境
export PATH=/opt/biosoft/miniconda3_for_antiSMASH/bin:$PATH
# 配置bioconda channel（https://bioconda.github.io/index.html）
conda config --add channels defaults
conda config --add channels conda-forge
conda config --add channels bioconda
# 通过bioconda源安装antiSMASH
conda create -n antismash antismash
# 程序会从bioconda和conda-forge源中下载antiSMASH所依赖的软件包（共131个）并安装。
# 激活antiSMASH环境
source activate antismash
# 自动下载antiSMASH数据库
download-antismash-databases
# 取消激活antiSMASH环境
source deactivate antismash
# 推荐直接使用下载并编译好的安装包直接解压缩
tar zxf ~/software/miniconda3_for_antiSMASH.tar.gz -C /opt/biosoft/

# 3. 使用antiSMASH
# 每次使用antiSMASH，需要依次载入minicoda变量，然后使用minicoda载入antiSMASH环境
export PATH=/opt/biosoft/miniconda3_for_antiSMASH/bin:$PATH
source activate antismash
# 再运行antiSMASH，例如：
antismash my_input.gbk
