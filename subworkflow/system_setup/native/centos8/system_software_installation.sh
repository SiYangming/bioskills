#!/bin/bash

# 使用 dnf 安装软件
dnf install lftp
# 使用 dnf 卸载软件
dnf remove lftp

# 安装本地源
/bin/rm -rf /media/CentOS/
mkdir -p /media/CentOS/AppStream
mount -o ro /home/train/software/CentOS-8.1.1911-x86_64-dvd1.iso /mnt
cp -a /mnt/AppStream/* /media/CentOS/AppStream
umount /mnt/
# 使用本地源安装软件
dnf --disablerepo=\* --enablerepo=c8-media-AppStream -y install gd*
echo "alias dnflocal='dnf --disablerepo=* --enablerepo=c8-media-AppStream'" >> ~/.bashrc
source ~/.bashrc
dnflocal -y install mysql mysql-devel lftp ftp gd gd-devel cmake gsl gsl-devel lm_sensors gnuplot gmp-devel postgresql* libffi-devel

# 备份原来的yum源，变更为Aliyun的yum源
#wget http://mirrors.aliyun.com/repo/Centos-8.repo -O /home/train/software/CentOS-Base.repo
/bin/mkdir /etc/yum.repos.d/bak
/bin/mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-AppStream.repo /etc/yum.repos.d/CentOS-Extras.repo /etc/yum.repos.d/CentOS-PowerTools.repo /etc/yum.repos.d/CentOS-centosplus.repo /etc/yum.repos.d/bak
/bin/cp /home/train/software/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo

# 增加第三方源(EPEL/RPMFusion/REMI)，可以从非官方源安装更多的其它软件。
# 添加EPEL（Extra Packages for Enterprise Linux）源，使用最广泛的第三方源，包含1万多个软件包，对官方源是极好的补充。
dnf -y install epel-release
# 添加RPMFusion源，可以用于安装一些音频软件。
wget http://download1.rpmfusion.org/free/el/rpmfusion-free-release-8.noarch.rpm -P /home/train/software
yum install /home/train/software/rpmfusion-free-release-8.noarch.rpm
# 查看当前源信息
dnf repolist
# 使用第三方源安装软件
dnf -y install screen
# 有些软件的安装，还需要额外启用PowerTools源。查看/etc/yum.repos.d/CentOS-Base.repo文件内容，其中centosplus和PowerTools源是默认没有启用的。可能这两个源中的有软件和其它系统软件有冲突，故根据需要临时启用这些源是较好的选择。
dnf --enablerepo=PowerTools -y install sshfs mplayer

# 使用源码方式安装软件
cd 
# installing NTFS-3G (https://www.tuxera.com/community/open-source-ntfs-3g/)
#wget https://tuxera.com/opensource/ntfs-3g_ntfsprogs-2017.3.23.tgz -P ~/software
tar zxf /home/train/software/ntfs-3g_ntfsprogs-2017.3.23.tgz
cd ntfs-3g_ntfsprogs-2017.3.23
./configure && make -j 4 && make install
cd .. && /bin/rm ntfs-3g_ntfsprogs-2017.3.23 -rf
ln -s /usr/sbin/mount.ntfs-3g /usr/sbin/mount.ntfs

# 准备/opt/biosoft目录，用于生物信息学软件的安装
# 准备/opt/sysoft目录，用于系统软件的安装
mkdir /opt/biosoft/ /opt/sysoft/
chmod 1777 /opt/biosoft/ /opt/sysoft/


##以上是CentOS系统中软件的安装方法。以下安装CentOS系统的一些系统软件
# 1. 安装GCC (https://gcc.gnu.org/releases.html)
# 1.1 在CentOS7系统种使用源码安装GCC
#cd
#wget http://mirrors-usa.go-parts.com/gcc/releases/gcc-4.9.4/gcc-4.9.4.tar.bz2 -P ~/software/
#tar jxf ~/software/gcc-4.9.4.tar.bz2
#cd gcc-4.9.4/
#./contrib/download_prerequisites
#安装GCC 4.9.4需要依赖GMP、MPFR、MPC、ISL和CLooG软件较高的版本。使用上面的命令则会下载相应的软件，利于GCC的安装。
#sudo yum install -y glibc-devel.i686
#mkdir ../gcc-build
#cd ../gcc-build
#../gcc-4.9.4/configure --prefix=/opt/sysoft/gcc-4.9.4 --enable-multilib --with-system-zlib
# 推荐使用root用户进行编译
#sudo make -j 8
# 多线程运行，加快软件的编译速度。由于GCC软件较大，编译会很耗时间。此安装经验是使用系统自带的gcc 4.4.7成功进行了编译，而高版本的gcc可能会导致编译失败。若提示错误：error "Where has __float128 gone?"，则可能是LD_LIBRARY_PATH设置问题，推荐清空该环境变量的值，在进行编译，或者选择使用root用户进行编译来应对该报错。
# real	22m3.549s
# user	91m24.603s
# sys	7m31.014s
#make install
#cd ../ && rm gcc-build/ gcc-4.9.4/ -rf
#ln -s /opt/sysoft/gcc-4.9.4/bin/gcc /opt/sysoft/gcc-4.9.4/bin/cc
echo 'export PKG_CONFIG_PATH=/opt/sysoft/gcc-4.9.4/lib/pkgconfig:$PKG_CONFIG_PATH' > /home/train/.bashrc.gcc
echo 'export LD_LIBRARY_PATH=/opt/sysoft/gcc-4.9.4/lib64:/opt/sysoft/gcc-4.9.4/lib:$LD_LIBRARY_PATH' >> /home/train/.bashrc.gcc
echo 'export C_INCLUDE_PATH=/opt/sysoft/gcc-4.9.4/include:$C_INCLUDE_PATH' >> /home/train/.bashrc.gcc
echo 'export PATH=/opt/sysoft/gcc-4.9.4/bin/:$PATH' >> /home/train/.bashrc.gcc

# 1.2 从已经编译好的压缩包中解压，但必须解压缩到目录/opt/sysoft/目录下才有效
# 在CentOS8下编译低版本（4.9.4）的GCC不成功，使用CentOS7下编译的GCC依然是有效的。
tar zxf /home/train/software/gcc-4.9.4.CentOS7.6_1810_opt_sysoft.tar.gz -C /opt/sysoft/


# 2. 安装Python及其modules
# 2.1 下载并安装Python2
#wget https://www.python.org/ftp/python/2.7.18/Python-2.7.18.tgz -P ~/software/
#tar zxf ~/software/Python-2.7.18.tgz
#cd Python-2.7.18/
#./configure --prefix=/opt/sysoft/Python-2.7.18/ --enable-optimizations
#make -j 8
#make install
#利用源码包文件安装setuptools和pip模块，后者的安装需要依赖前者
#python Lib/ensurepip/_bundled/pip-19.2.3-py2.py3-none-any.whl/pip install --no-index Lib/ensurepip/_bundled/setuptools-41.2.0-py2.py3-none-any.whl
#python Lib/ensurepip/_bundled/pip-19.2.3-py2.py3-none-any.whl/pip install Lib/ensurepip/_bundled/pip-19.2.3-py2.py3-none-any.whl
#cd .. && rm Python-2.7.18/ -rf
#echo 'PATH=/opt/sysoft/Python-2.7.18/bin/:$PATH' >> ~/.bashrc
#source ~/.bashrc

# 2.2 永久修改Pypi镜像源，以利于使用pip联网安装Python模块。
#pip config set global.index-url https://mirrors.aliyun.com/pypi/simple/

# 2.3 使用pip安装其它Python模块
#pip install setuptools pip --upgrade -i https://mirrors.aliyun.com/pypi/simple/
#pip install numpy

# 2.4 从已经编译好的压缩包解压，但必须解压缩到目录/opt/sysoft/目录下才有效
tar zxf /home/train/software/Python-2.7.18.CentOS8.1_1911_opt_sysoft.tar.gz -C /opt/sysoft/

# 2.5 下载并安装Python3
#wget https://www.python.org/ftp/python/3.8.4/Python-3.8.4.tgz -P ~/software/
#tar zxf ~/software/Python-3.8.4.tgz
#cd Python-3.8.4
#./configure --prefix=/opt/sysoft/Python-3.8.4 --enable-optimizations
#make -j 8
#make install
#cd .. && rm -rf Python-3.8.4
#echo 'PATH=/opt/sysoft/Python-3.8.4/bin/:$PATH' >> ~/.bashrc
#source ~/.bashrc
#pip3 install numpy
tar zxf /home/train/software/Python-3.8.4.CentOS8.1_1911_opt_sysoft.tar.gz -C /opt/sysoft/

# 3. 安装R及其modules
# 3.1 安装R
#sudo dnf -y install readline readline-devel libcurl libcurl-devel
#wget https://mirrors.tuna.tsinghua.edu.cn/CRAN/src/base/R-4/R-4.0.2.tar.gz -P ~/software/
#tar zxf ~/software/R-4.0.2.tar.gz
#cd R-4.0.2/
#./configure --prefix=/opt/sysoft/R-4.0.2
#make -j 4
#make install
#cd .. && rm R-4.0.2/ -rf
#echo 'PATH=/opt/sysoft/R-4.0.2/bin/:$PATH' >> ~/.bashrc
#source ~/.bashrc

# 3.2 安装R modules
#wget http://mirrors.tuna.tsinghua.edu.cn/CRAN/src/contrib/Archive/gplots/gplots_3.0.1.tar.gz -P ~/software/
#R CMD INSTALL ~/software/gplots_3.0.1.tar.gz
#wget http://mirrors.tuna.tsinghua.edu.cn/CRAN/src/contrib/Archive/XML/XML_3.98-1.20.tar.gz -P ~/software
#R CMD INSTALL ~/software/XML_3.98-1.20.tar.gz 
# R
# 切换CRAN国内镜像
# > options("repos" = c(CRAN="http://mirrors.tuna.tsinghua.edu.cn/CRAN/"))
# 安装R包
# > install.packages(c('ggplot2', 'gplots', 'ape'))
# 安装bioconductor
# > if (!requireNamespace("BiocManager", quietly = TRUE))
# + install.packages("BiocManager")
# > BiocManager::install(version = "3.11")
# 切换bioconductor国内镜像: https://www.bioconductor.org/about/mirrors/
# > options(BioC_mirror="http://mirrors.tuna.tsinghua.edu.cn/bioconductor/")
# > BiocManager::install(c('edgeR', 'fastcluster', 'limma', 'IRanges', 'DESeq2', 'Biobase', 'qvalue', 'seqLogo', 'pathview', 'goseq'))
# > q()

# 3.3 从已经编译好的压缩包解压，但必须解压缩到目录/opt/sysoft/目录下才有效
tar zxf /home/train/software/R-4.0.2.CentOS8.1_1911_opt_sysoft.tar.gz -C /opt/sysoft/
echo 'PATH=$PATH:/opt/sysoft/R-4.0.2/bin/' >> ~/.bashrc
source ~/.bashrc


# 4. 安装Perl modules
# Installing LibGD (https://github.com/libgd/libgd/releases/tag/gd-2.2.5)
#wget https://github.com/libgd/libgd/releases/download/gd-2.2.5/libgd-2.2.5.tar.gz -P ~/software/
tar zxf /home/train/software/libgd-2.2.5.tar.gz
cd libgd-2.2.5/
./configure --prefix=/usr/ && make -j 4 && sudo make install
cd ../ && rm -rf libgd-2.2.5
/bin/rm /usr/lib64/libgd.so
cp /usr/lib/libgd.* /usr/lib64/
# 安装好正确的/usr/lib/libgd.so.3库文件，才能正常成功安装Perl GD模块。

# Installing Perl Modules
tar zxf /home/train/software/usr_local.tar.gz -C /


# 5. 安装并行化软件mpich (http://www.mpich.org/downloads/)
#wget http://www.mpich.org/static/downloads/3.3/mpich-3.3.tar.gz -P ~/software/
tar zxf ~/software/mpich-3.3.tar.gz
cd mpich-3.3
source ~/.bashrc.gcc
./configure --prefix=/opt/sysoft/mpich-3.3 && make -j 4 && make install
cd .. && rm -rf mpich-3.3
echo 'export PKG_CONFIG_PATH=/opt/sysoft/mpich-3.3/lib/pkgconfig:$PKG_CONFIG_PATH' >> /home/train/.bashrc.gcc
echo 'export LD_LIBRARY_PATH=/opt/sysoft/mpich-3.3/lib:$LD_LIBRARY_PATH' >> /home/train/.bashrc.gcc
echo 'export C_INCLUDE_PATH=/opt/sysoft/mpich-3.3/include:$C_INCLUDE_PATH' >> /home/train/.bashrc.gcc
echo 'export PATH=/opt/sysoft/mpich-3.3/bin/:$PATH' >> /home/train/.bashrc.gcc


# 6. Installing Java 1.7
tar zxf /home/train/software/jre1.7.0_05.tar.gz -C /opt/sysoft/
