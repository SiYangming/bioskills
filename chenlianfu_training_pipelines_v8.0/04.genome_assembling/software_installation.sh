# installing GCE (https://arxiv.org/abs/1308.2012 | ftp://ftp.genomics.org.cn/pub/gce)
#wget ftp://ftp.genomics.org.cn/pub/gce/gce-1.0.0.tar.gz -P ~/software/
tar zxf ~/software/gce-1.0.0.tar.gz -C /opt/biosoft/

# installing GenomeScope 2.0 (https://github.com/tbenavi1/genomescope2.0) and Jellyfish (https://github.com/gmarcais/Jellyfish)
#wget https://github.com/gmarcais/Jellyfish/releases/download/v2.3.0/jellyfish-2.3.0.tar.gz -P ~/software/
tar zxf ~/software/jellyfish-2.3.0.tar.gz
cd jellyfish-2.3.0/
./configure --prefix=/opt/biosoft/jellyfish-2.3.0
make -j 8 && make install
cd .. && rm -rf jellyfish-2.3.0
echo 'PATH=/opt/biosoft/jellyfish-2.3.0/bin:$PATH' >> ~/.bashrc
source  ~/.bashrc

#wget https://github.com/tbenavi1/genomescope2.0/archive/v1.0.0.tar.gz -O ~/software/genomescope2.0-1.0.0.tar.gz
#mkdir ~/.R_libs
#echo "R_LIBS=~/.R_libs/" >> ~/.Renviron
#R
#> options("repos" = c(CRAN="http://mirrors.tuna.tsinghua.edu.cn/CRAN/"))
#> install.packages("argparse")
#> install.packages("minpack.lm")
#> quit()
R CMD INSTALL ~/software/genomescope2.0-1.0.0.tar.gz
tar zxf ~/software/genomescope2.0-1.0.0.tar.gz -C /opt/biosoft/


# installing Newbler (http://454.com/contact-us/software-request.asp)
tar zxf ~/software/DataAnalysis_2.9_All_20130530_1559.tgz 
cd DataAnalysis_2.9_All/
sudo yum -y install zlib* libXi* libXtst* libXaw* zlib*i686 libXi*i686 libXtst*i686 libXaw*i686
./setup.sh
# 设定安装路径为 /opt/biosoft/454
echo 'PATH=$PATH:/opt/biosoft/454/bin/' >> ~/.bashrc
source ~/.bashrc
cd ..
rm DataAnalysis_2.9_All/ -rf


# installing IDBA (https://github.com/loneknightpy/idba)
#wget https://github.com/loneknightpy/idba/releases/download/1.1.3/idba-1.1.3.tar.gz -P ~/software
tar zxf ~/software/idba-1.1.3.tar.gz -C /opt/biosoft/
cd /opt/biosoft/idba-1.1.3/
./configure --prefix=/opt/biosoft/idba-1.1.3
perl -p -i -e 's/kMaxShortSequence = 128/kMaxShortSequence = 160/' src/sequence/short_sequence.h
make -j 4
echo 'PATH=$PATH:/opt/biosoft/idba-1.1.3/bin/' >> ~/.bashrc
source ~/.bashrc
cd ..


# installing SOAPdenovo (https://github.com/aquaskyline/SOAPdenovo2/releases)
#wget https://github.com/aquaskyline/SOAPdenovo2/archive/r241.tar.gz -O ~/software/SOAPdenovo2-r241.tar.gz
tar zxf ~/software/SOAPdenovo2-r241.tar.gz -C /opt/biosoft/
cd /opt/biosoft/SOAPdenovo2-r241
make
echo 'PATH=$PATH:/opt/biosoft/SOAPdenovo2-r241/' >> ~/.bashrc
source ~/.bashrc


# installing ALLPATHS-LG (http://software.broadinstitute.org/allpaths-lg/blog/?page_id=12)
#wget ftp://ftp.broadinstitute.org/pub/crd/ALLPATHS/Release-LG/latest_source_code/LATEST_VERSION.tar.gz -O ~/software/allpathslg-52488.tar.gz
# 以下是源码安装，非常耗时间。
tar zxf ~/software/allpathslg-52488.tar.gz 
cd allpathslg-52488/
./configure --prefix=/opt/biosoft/ALLPATHS-LG/
make -j 4
make install
cd .. && rm allpathslg-52488/ -rf
echo 'PATH=$PATH:/opt/biosoft/ALLPATHS-LG/bin/' >> ~/.bashrc
source ~/.bashrc


# installing MaSuRCA (http://www.genome.umd.edu/masurca.html | https://github.com/alekseyzimin/masurca)
#wget https://github.com/alekseyzimin/masurca/releases/download/v3.4.1/MaSuRCA-3.4.1.tar.gz -P ~/software/
tar zxf ~/software/MaSuRCA-3.4.1.tar.gz -C /opt/biosoft/
cd /opt/biosoft/MaSuRCA-3.4.1/
export BOOST_ROOT=/opt/biosoft/boost_1_64_0/
./install.sh
#echo 'PATH=$PATH:/opt/biosoft/MaSuRCA-3.4.1/bin/' >> ~/.bashrc
#source ~/.bashrc


# installing DBG2OLC (https://github.com/yechengxi/DBG2OLC)
# a. 安装较高版本的git (https://github.com/git/git/releases)
#wget https://github.com/git/git/archive/v2.21.0.tar.gz -O ~/software/git-2.21.0.tar.gz
#tar zxf ~/software/git-2.21.0.tar.gz
#cd git-2.21.0
#make configure
#./configure --prefix=/opt/sysoft/git-2.21.0
#make -j 4
#make install
#cd .. && rm -rf git-2.21.0/
#echo 'PATH=/opt/sysoft/git-2.21.0/bin:$PATH' >> ~/.bashrc
#source ~/.bashrc

# b. 使用git从GitHub下载源代码并安装
#git clone https://github.com/yechengxi/DBG2OLC.git /opt/biosoft/DBG2OLC
#cd /opt/biosoft/DBG2OLC
# 按照说明中对软件进行编译，编译出的3个可执行程序全部都是DBG2OLC命令
#g++ -O3 -o SparseAssembler DBG2OLC.cpp
#g++ -O3 -o DBG2OLC *.cpp
#g++ -O3 -o Sparc *.cpp
#直接拷贝作者编译好的程序即可
#cp compiled/* .
tar zxf ~/software/DBG2OLC.tar.gz -C /opt/biosoft/
cp /opt/biosoft/DBG2OLC/compiled/* /opt/biosoft/DBG2OLC/
cd DBG2OLC && g++ -O3 -o DBG2OLC *.cpp
echo 'PATH=$PATH:/opt/biosoft/DBG2OLC' >> ~/.bashrc
source ~/.bashrc

# c. 安装blasr软件，该软件是DBG2OCL流程第三步骤所依赖的软件。(https://github.com/PacificBiosciences/blasr)
# 使用bioconda方式安装blasr (https://conda.io/en/latest/miniconda.html)
#wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -P ~/software/
#sh ~/software/Miniconda3-latest-Linux-x86_64.sh
# 进入交互式界面：按Enter键进入license界面并使用空格键到页尾；输入yes，按Enter键，表示同意license； 输入安装路径/opt/biosoft/miniconda3_for_blasr，按enter键； 设置是否添加Minicoda3的PATH变量，直接按Enter键，表示选择no，以免和系统自带的软件冲突。若需要切换到本miniconda3环境，输入命令export PATH=/opt/biosoft/miniconda3_for_blasr/bin:$PATH即可。
#export PATH=/opt/biosoft/miniconda3_for_blasr/bin:$PATH
# 添加conda源
#conda config --add channels default
#conda config --add channels bioconda
#conda config --add channels conda-forge
#conda install blasr
#conda install bax2bam
#conda install bam2fastx
#rm /opt/biosoft/miniconda3_for_blasr/pkgs/* -rf
tar zxf ~/software/miniconda3_for_blasr.tar.gz -C /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/miniconda3_for_blasr/bin/' >> ~/.bashrc.pacbio
source ~/.bashrc.pacbio


# installing SMRT Analysis (https://www.pacb.com/support/software-downloads/)
#wget https://downloads.pacbcloud.com/public/software/installers/smrtlink_7.0.1.66975.zip -P ~/software/
cd /home/train
unzip ~/software/smrtlink_7.0.1.66975.zip
sh smrtlink_7.0.1.66975.run  # 交互问答中全部按Enter键选择默认值
ulimit -u 10240
ulimit -n 10240 # (修改不成功，则修改配置文件/etc/security/limits.conf，然后重新登录用户生效，或重启sshd服务生效)
./smrtlink/admin/bin/services-start  # (推荐在ulimit修改权限成功后，再启动smrtlink软件，否则会启动失败；然后修改ulimit成功后要kill之前的进程才能再次启动成功)
rm smrtlink_7.0.1.66975.run*

# installing google chrome
# echo '[google-chrome]
# name=google-chrome
# baseurl=http://dl.google.com/linux/chrome/rpm/stable/$basearch
# enabled=1
# gpgcheck=0
# #gpgkey=https://dl-ssl.google.com/linux/linux_signing_key.pub' > google-chrome.repo
# sudo mv google-chrome.repo /etc/yum.repos.d/
# sudo yum install google-chrome-stable
sudo dnf --disablerepo=* --enablerepo=c8-media-AppStream -y install ~/software/google-chrome-stable-84.0.4147.125-1.x86_64.rpm

# installing Canu (https://canu.readthedocs.io/en/latest/ | https://github.com/marbl/canu/releases)
#wget https://github.com/marbl/canu/archive/end-of-big-meryl.tar.gz -O ~/software/canu-end-of-big-meryl.tar.gz
tar zxf ~/software/canu-end-of-big-meryl.tar.gz -C /opt/biosoft
mv /opt/biosoft/canu-end-of-big-meryl/ /opt/biosoft/canu-2.0
cd /opt/biosoft/canu-2.0/src/
make -j 8
echo 'PATH=$PATH:/opt/biosoft/canu-2.0/Linux-amd64/bin/' >> ~/.bashrc.pacbio
source ~/.bashrc.pacbio


# installing FALCON (https://github.com/PacificBiosciences/pb-assembly)
#wgt https://repo.anaconda.com/miniconda/Miniconda3-py37_4.8.3-Linux-x86_64.sh -P ~/software
#sh ~/software/Miniconda3-py37_4.8.3-Linux-x86_64.sh
## 进入交互式界面：输入yes，按Enter键，表示同意license； 输入安装路径/opt/biosoft/miniconda3_for_pb-assembly，按enter键； 设置是否添加Minicoda3的PATH变量，直接按Enter键，表示选择no，以免和系统自带的软件冲突。若需要切换到本miniconda3环境，输入命令export PATH=/opt/biosoft/miniconda3_for_pb-assembly/bin:$PATH即可。
#export PATH=/opt/biosoft/miniconda3_for_pb-assembly/bin:$PATH
#conda config --add channels default
#conda config --add channels conda-forge
#conda config --add channels bioconda
#conda install pb-assembly
#source activate /opt/biosoft/miniconda3_for_pb-assembly
tar zxf ~/software/miniconda3_for_pb-assembly.tar.gz -C /opt/biosoft/


# installing wtdbg2 (https://github.com/ruanjue/wtdbg2)
#wget https://github.com/ruanjue/wtdbg2/releases/download/v2.5/wtdbg-2.5_x64_linux.tgz -P ~/software/
tar zxf ~/software/wtdbg-2.5_x64_linux.tgz -C /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/wtdbg-2.5_x64_linux/' >> ~/.bashrc
source ~/.bashrc

# installing minimap2 (https://github.com/lh3/minimap2/releases)
#wget https://github.com/lh3/minimap2/releases/download/v2.17/minimap2-2.17_x64-linux.tar.bz2 -P ~/software
tar jxf ~/software/minimap2-2.17_x64-linux.tar.bz2 -C /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/minimap2-2.17_x64-linux/' >> ~/.bashrc
source ~/.bashrc


# installing Platanus-allee (http://platanus.bio.titech.ac.jp/platanus/platanus-allee-2-0-was-released)
# wget http://platanus.bio.titech.ac.jp/?ddownload=347 -O ~/software/Platanus_allee_v2.0.2_Linux_x86_64.tgz
tar zxf ~/software/Platanus_allee_v2.0.2_Linux_x86_64.tgz -C /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/Platanus_allee_v2.0.2_Linux_x86_64' >> ~/.bashrc
source ~/.bashrc


# installing quickmerge (https://github.com/mahulchak/quickmerge/releases)
#wget https://github.com/mahulchak/quickmerge/archive/v0.3.tar.gz -O ~/software/quickmerge-0.3.tar.gz
tar zxf ~/software/quickmerge-0.3.tar.gz -C /opt/biosoft/
cd /opt/biosoft/quickmerge-0.3
bash make_merger.sh
echo 'PATH=$PATH:/opt/biosoft/quickmerge-0.3' >> ~/.bashrc
source ~/.bashrc

# installing MUMmer (https://github.com/mummer4/mummer)
#wget https://github.com/mummer4/mummer/releases/download/v4.0.0beta2/mummer-4.0.0beta2.tar.gz -P ~/software/
tar zxf ~/software/mummer-4.0.0beta2.tar.gz
cd mummer-4.0.0beta2
./configure --prefix=/opt/biosoft/mummer-4.0.0beta2 && make -j 8 && make install
cd .. && rm -rf mummer-4.0.0beta2
echo 'PATH=$PATH:/opt/biosoft/mummer-4.0.0beta2/bin/' >> ~/.bashrc
source ~/.bashrc


# installing FinisherSC (http://kakitone.github.io/finishingTool/)
#wget https://codeload.github.com/kakitone/finishingTool/legacy.zip/master -O ~/software/kakitone-finishingTool-v2.1-2-ga1f2608.zip
unzip ~/software/kakitone-finishingTool-v2.1-2-ga1f2608.zip -d /opt/biosoft/


# installing GenomicConsensus (https://github.com/PacificBiosciences/GenomicConsensus)
#wget https://github.com/PacificBiosciences/GenomicConsensus/releases/download/2.3.3/GenomicConsensus-2.3.3.tar.gz -P ~/software



# installing Pilon (https://github.com/broadinstitute/pilon/releases)
#wget https://github.com/broadinstitute/pilon/releases/download/v1.23/pilon-1.23.jar
mkdir /opt/biosoft/pilon
cp /home/train/software/pilon-1.23.jar /opt/biosoft/pilon


# installing GapFiller (http://www.baseclear.com/landingpages/basetools-a-wide-range-of-bioinformatics-solutions/gapfiller/)
tar zxf ~/software/GapFiller_v1-11_linux-x86_64.tar.gz -C /opt/biosoft/
perl -p -i -e 's/\s*$/\n/' /opt/biosoft/GapFiller_v1-11_linux-x86_64/GapFiller.pl
chmod 644 /opt/biosoft/GapFiller_v1-11_linux-x86_64/*.pdf /opt/biosoft/GapFiller_v1-11_linux-x86_64/README
echo 'PATH=$PATH:/opt/biosoft/GapFiller_v1-11_linux-x86_64/' >> ~/.bashrc
source ~/.bashrc


# installing GapCloser (https://sourceforge.net/projects/soapdenovo2/files/GapCloser)
#wget https://sourceforge.net/projects/soapdenovo2/files/GapCloser/bin/r6/GapCloser-bin-v1.12-r6.tgz -P ~/software/
mkdir /opt/biosoft/GapCloser-v1.12-r6
tar zxf ~/software/GapCloser-bin-v1.12-r6.tgz -C /opt/biosoft/GapCloser-v1.12-r6
echo 'PATH=$PATH:/opt/biosoft/GapCloser-v1.12-r6/' >> ~/.bashrc
source ~/.bashrc 


# installing SSPACE (https://www.baseclear.com/services/bioinformatics/basetools/sspace-standard)
#wget https://www.baseclear.com/wp-content/uploads/SSPACE-STANDARD-v.-3.0-linux-x86_64.tar.gz -P ~/software/
tar zxf /home/train/software/SSPACE-STANDARD-v.-3.0-linux-x86_64.tar.gz -C /opt/biosoft/
chmod 644 /opt/biosoft/SSPACE-STANDARD-3.0_linux-x86_64/*.pdf /opt/biosoft/SSPACE-STANDARD-3.0_linux-x86_64/README
echo 'PATH=$PATH:/opt/biosoft/SSPACE-STANDARD-3.0_linux-x86_64/' >> ~/.bashrc
source ~/.bashrc

# installing bowtie2 (http://bowtie-bio.sourceforge.net/bowtie2/index.shtml)
#wget https://sourceforge.net/projects/bowtie-bio/files/bowtie2/2.4.1/bowtie2-2.4.1-linux-x86_64.zip -P ~/software
unzip ~/software/bowtie2-2.4.1-linux-x86_64.zip -d /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/bowtie2-2.4.1-linux-x86_64/' >> ~/.bashrc
source ~/.bashrc
