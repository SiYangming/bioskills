# installing Bowtie1 (http://bowtie-bio.sourceforge.net/index.shtml)
#wget https://sourceforge.net/projects/bowtie-bio/files/bowtie/1.3.0/bowtie-1.3.0-linux-x86_64.zip -P ~/software
unzip ~/software/bowtie-1.3.0-linux-x86_64.zip -d /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/bowtie-1.3.0-linux-x86_64/' >> ~/.bashrc
source ~/.bashrc

# installing bowtie2 (http://bowtie-bio.sourceforge.net/bowtie2/index.shtml)
#wget https://sourceforge.net/projects/bowtie-bio/files/bowtie2/2.4.1/bowtie2-2.4.1-linux-x86_64.zip -P ~/software
unzip ~/software/bowtie2-2.4.1-linux-x86_64.zip -d /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/bowtie2-2.4.1-linux-x86_64/' >> ~/.bashrc
source ~/.bashrc


# installing BWA (https://sourceforge.net/projects/bio-bwa/files/)
#wget https://sourceforge.net/projects/bio-bwa/files/bwa-0.7.17.tar.bz2 -P ~/software/
tar jxf ~/software/bwa-0.7.17.tar.bz2 -C /opt/biosoft/
cd /opt/biosoft/bwa-0.7.17/
make -j 4
echo 'PATH=$PATH:/opt/biosoft/bwa-0.7.17/' >> ~/.bashrc
source ~/.bashrc


# Installing boost C++ Libraries (https://www.boost.org/)
#wget https://kent.dl.sourceforge.net/project/boost/boost/1.64.0/boost_1_64_0.tar.gz -P ~/software
tar zxf ~/software/boost_1_64_0.tar.gz
cd boost_1_64_0/
./bootstrap.sh --prefix=/opt/biosoft/boost_1_64_0
./b2 -j 4 install
cd .. && rm boost_1_64_0/ -rf
echo 'export LD_LIBRARY_PATH=/opt/biosoft/boost_1_64_0/lib:$LD_LIBRARY_PATH
export C_INCLUDE_PATH=/opt/biosoft/boost_1_64_0/include:$C_INCLUDE_PATH' >> ~/.bash_profile
source ~/.bash_profile


# installing samtools (https://github.com/samtools/samtools/releases)
#wget https://github.com/samtools/samtools/releases/download/1.10/samtools-1.10.tar.bz2 -P ~/software/
tar jxf ~/software/samtools-1.10.tar.bz2
cd samtools-1.10/
./configure --prefix=/opt/biosoft/samtools-1.10 && make -j 4 && make install
cd ../ && rm -rf samtools-1.10/
echo 'PATH=$PATH:/opt/biosoft/samtools-1.10/bin/' >> ~/.bashrc
source ~/.bashrc
#wget https://sourceforge.net/projects/samtools/files/samtools/0.1.19/samtools-0.1.19.tar.bz2 -P ~/software
tar jxf ~/software/samtools-0.1.19.tar.bz2 -C /opt/biosoft
cd /opt/biosoft/samtools-0.1.19/
make -j 4

# install htslib (https://github.com/samtools/htslib)
#wget https://github.com/samtools/htslib/archive/1.10.tar.gz -O ~/software/htslib-1.10.tar.gz
tar zxf ~/software/htslib-1.10.tar.gz
cd htslib-1.10
autoheader
autoconf
./configure --prefix=/opt/biosoft/htslib-1.10 && make -j 4 && make install
cd .. && rm -rf htslib-1.10
echo 'LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/biosoft/htslib-1.10/lib/' >> ~/.bashrc
echo 'C_INCLUDE_PATH=$C_INCLUDE_PATH:/opt/biosoft/htslib-1.10/include/' >> ~/.bashrc
echo 'PATH=$PATH:/opt/biosoft/htslib-1.10/bin/' >> ~/.bashrc
source ~/.bashrc

# installing bcftools (https://github.com/samtools/bcftools/releases)
#wget https://github.com/samtools/bcftools/releases/download/1.10/bcftools-1.10.tar.bz2 -P ~/software/
tar jxf ~/software/bcftools-1.10.tar.bz2
cd bcftools-1.10/
./configure --prefix=/opt/biosoft/bcftools-1.10 --with-htslib=/opt/biosoft/htslib-1.10/
make -j 4 && make install
cd .. && rm -rf bcftools-1.10/
echo 'PATH=$PATH:/opt/biosoft/bcftools-1.10/bin' >> ~/.bashrc
source ~/.bashrc


# installing tophat (http://ccb.jhu.edu/software/tophat/index.shtml)
#wget http://ccb.jhu.edu/software/tophat/downloads/tophat-2.1.1.Linux_x86_64.tar.gz -P ~/software/
tar zxf ~/software/tophat-2.1.1.Linux_x86_64.tar.gz -C /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/tophat-2.1.1.Linux_x86_64/' >> ~/.bashrc 
source ~/.bashrc


# installing HISAT2 (http://ccb.jhu.edu/software/hisat2/manual.shtml)
#wget ftp://ftp.ccb.jhu.edu/pub/infphilo/hisat2/downloads/hisat2-2.1.0-Linux_x86_64.zip -P ~/software/
unzip ~/software/hisat2-2.1.0-Linux_x86_64.zip -d /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/hisat2-2.1.0/' >> ~/.bashrc
source ~/.bashrc


# installing picard (https://github.com/broadinstitute/picard/releases)
#wget https://github.com/broadinstitute/picard/releases/download/2.23.3/picard.jar -O ~/software/picard-2.23.3.jar
mkdir /opt/biosoft/picard-tools
cp ~/software/picard-2.23.3.jar /opt/biosoft/picard-tools/picard.jar
