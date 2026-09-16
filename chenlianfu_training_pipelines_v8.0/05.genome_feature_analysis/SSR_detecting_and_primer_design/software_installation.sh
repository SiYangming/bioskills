# 安装 MISA (http://pgrc.ipk-gatersleben.de/misa/misa.html)
tar zxf ~/software/Misa_Primer3.tar.gz -C /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/Misa_Primer3/' >> ~/.bashrc
source ~/.bashrc


# 安装 Primer3 (http://primer3.ut.ee/ | https://sourceforge.net/projects/primer3/ | https://github.com/primer3-org/primer3)
#wget https://sourceforge.net/projects/primer3/files/primer3/2.5.0/primer3-2.5.0.tar.gz -P ~/software/
tar zxf ~/software/primer3-2.5.0.tar.gz -C /opt/biosoft/
cd /opt/biosoft/primer3-2.5.0/src/
make all
# make test             # 比较耗时，不需要进行
echo 'PATH=$PATH:/opt/biosoft/primer3-2.5.0/src/' >> ~/.bashrc
source ~/.bashrc
