# installing FastQC (http://www.bioinformatics.babraham.ac.uk/projects/fastqc/)
#wget http://www.bioinformatics.babraham.ac.uk/projects/fastqc/fastqc_v0.11.9.zip -P ~/software/
unzip ~/software/fastqc_v0.11.9.zip -d /opt/biosoft/
chmod 755 /opt/biosoft/FastQC/fastqc
echo 'PATH=$PATH:/opt/biosoft/FastQC/' >> ~/.bashrc
source ~/.bashrc


# installing Trimmomatic (http://www.usadellab.org/cms/index.php?page=trimmomatic)
#wget http://www.usadellab.org/cms/uploads/supplementary/Trimmomatic/Trimmomatic-0.39.zip -P ~/software/
unzip ~/software/Trimmomatic-0.39.zip -d /opt/biosoft/


# installing FastUniq (https://sourceforge.net/projects/fastuniq/files/)
#wget https://sourceforge.net/projects/fastuniq/files/FastUniq-1.1.tar.gz -P ~/software/
tar zxf ~/software/FastUniq-1.1.tar.gz -C /opt/biosoft/
cd /opt/biosoft/FastUniq/source/
make
chmod 644 fastq* Makefile
echo 'PATH=$PATH:/opt/biosoft/FastUniq/source/' >> ~/.bashrc
source ~/.bashrc


# installing BLESS (https://sourceforge.net/projects/bless-ec/files/)
#wget https://sourceforge.net/projects/bless-ec/files/bless.v1p02.tgz -P ~/software/
tar zxf ~/software/bless.v1p02.tgz -C /opt/biosoft/
mv /opt/biosoft/v1p02/ /opt/biosoft/BLESS/
chmod 755 /opt/biosoft/BLESS
cd /opt/biosoft/BLESS/
source ~/.bashrc.gcc
make -j 4
echo 'PATH=$PATH:/opt/biosoft/BLESS/' >> ~/.bashrc
echo "alias bless='mkdir -p kmc/bin/; cp /opt/biosoft/BLESS/kmc/bin/kmc kmc/bin/; bless'" >> ~/.bashrc
source ~/.bashrc
# 培训时，由于小米路由器原因，导致bless无法运行。只需要断开和小米路由器的连接即可，或输入命令“hostname localhost”将主机名还原即可。


# installing ALLPATHS-LG
# 源码安装
# source ~/.bashrc.gcc
#wget ftp://ftp.broadinstitute.org/pub/crd/ALLPATHS/Release-LG/latest_source_code/allpathslg-52488.tar.gz -P ~/software
# tar zxf ~/software/allpathslg-52488.tar.gz
# sudo dnf --disablerepo=* --enablerepo=c8-media-AppStream -y install libieee1284-devel libieee1284*i686*
# source /home/train/.bashrc.gcc
# cd allpathslg-52488
# ./configure --prefix=/opt/biosoft/ALLPATHS-LG/ 
# make -j 4
# make install
# echo 'PATH=$PATH:/opt/biosoft/ALLPATHS-LG/bin/' >> ~/.bashrc
# source ~/.bashrc
# cd .. && rm -rf allpathslg-52488
# 使用已经编译完毕的二进制包安装
tar zxf ~/software/ALLPATHS-LG.CentOS8.1_1911_opt_biosoft.tar.gz -C /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/ALLPATHS-LG/bin/' >> ~/.bashrc
source ~/.bashrc


# installing Celera Assembler (http://wgs-assembler.sourceforge.net/wiki/index.php?title=Main_Page)
#wget https://sourceforge.net/projects/wgs-assembler/files/wgs-assembler/wgs-8.3/wgs-8.3rc2.tar.bz2 -P ~/software/
tar jxf ~/software/wgs-8.3rc2.tar.bz2 -C /opt/biosoft/
cd /opt/biosoft/wgs-8.3rc2/kmer
make install && cd ../src
make && cd ..
echo 'PATH=$PATH:/opt/biosoft/wgs-8.3rc2/Linux-amd64/bin/' >> ~/.bashrc.pacbio
source ~/.bashrc.pacbio
# 需要安装如下perl模块，以利于CA进行基因组组装。
sudo cpan -i Statistics:Descriptive


# installing LoRDEC (http://www.atgc-montpellier.fr/lordec/)
# LoRDEC 的编译需要 gatb-core 和 Boost C++ libraries

# Installing gatb-core
#wget https://github.com/GATB/gatb-core/archive/v1.4.1.tar.gz -O ~/software/gatb-core-1.4.1.tar.gz
tar zxf ~/software/gatb-core-1.4.1.tar.gz
cd gatb-core-1.4.1/gatb-core/
mkdir build
cd build
cmake -DCMAKE_INSTALL_PREFIX=/opt/biosoft/gatb-core-1.4.1/ ../
make -j 4
make install
cd ../../../ && rm gatb-core-1.4.1 -rf
echo 'export LD_LIBRARY_PATH=/opt/biosoft/gatb-core-1.4.1/lib:$LD_LIBRARY_PATH
export C_INCLUDE_PATH=/opt/biosoft/gatb-core-1.4.1/include:$C_INCLUDE_PATH' >> ~/.bash_profile
source ~/.bash_profile

# Installing boost
#wget https://kent.dl.sourceforge.net/project/boost/boost/1.64.0/boost_1_64_0.tar.gz -P ~/software
tar zxf ~/software/boost_1_64_0.tar.gz
cd boost_1_64_0/
./bootstrap.sh --prefix=/opt/biosoft/boost_1_64_0
./b2 -j 4 install
cd .. && rm boost_1_64_0/ -rf
echo 'export LD_LIBRARY_PATH=/opt/biosoft/boost_1_64_0/lib:$LD_LIBRARY_PATH
export C_INCLUDE_PATH=/opt/biosoft/boost_1_64_0/include:$C_INCLUDE_PATH' >> ~/.bash_profile
source ~/.bash_profile

#wget https://gite.lirmm.fr/lordec/lordec-releases/uploads/800a96d81b3348e368a0ff3a260a88e1/lordec-src_0.9.tar.bz2 -P ~/software/
#tar jxf ~/software/lordec-src_0.9.tar.bz2 -C /opt/biosoft/
#cd /opt/biosoft/lordec-src_0.9/
#make -j 4
tar zxf ~/software/lordec-src_0.9.tar.gz -C /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/lordec-src_0.9/' >> ~/.bashrc 
source ~/.bashrc
