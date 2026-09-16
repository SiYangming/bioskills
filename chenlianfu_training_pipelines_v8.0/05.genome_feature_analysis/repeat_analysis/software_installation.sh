#!/bin/bash

# installing NCBI Blast and RMBlast (http://www.repeatmasker.org/)
#wget http://www.repeatmasker.org/rmblast-2.10.0+-x64-linux.tar.gz -P ~/software
tar zxf ~/software/rmblast-2.10.0+-x64-linux.tar.gz -C /opt/biosoft
mv /opt/biosoft/rmblast-2.10.0/bin /opt/biosoft/ncbi-rmblast-2.10.0+/
echo 'PATH=$PATH:/opt/biosoft/ncbi-rmblast-2.10.0+/bin/' >> ~/.bashrc
source ~/.bashrc

# 安装RepeatMasker (http://www.repeatmasker.org/RMDownload.html)
#wget http://www.repeatmasker.org/RepeatMasker-4.1.0.tar.gz -P ~/software
tar zxf ~/software/RepeatMasker-4.1.0.tar.gz -C /opt/biosoft/
cd /opt/biosoft/RepeatMasker/
chmod 644 *.pm configure 
echo 'PATH=$PATH:/opt/biosoft/RepeatMasker' >> ~/.bashrc
source ~/.bashrc

# installing trf (http://tandem.bu.edu/trf/trf.html)
#wget http://tandem.bu.edu/trf/downloads/trf409.linux64 -P ~/software/
cp ~/software/trf409.linux64 /opt/biosoft/RepeatMasker/trf
chmod 755 /opt/biosoft/RepeatMasker/trf

# instaling RepBase (https://www.girinst.org/server/RepBase/index.php)
#下载RepBase数据库需要用户名和密码，使用edu邮箱可以申请用户。
#wget --http-user=chenlianfu_china --http-password=u2o7rn https://www.girinst.org/server/RepBase/protected/repeatmaskerlibraries/RepBaseRepeatMaskerEdition-20181026.tar.gz -P ~/software/
cd /opt/biosoft/RepeatMasker/
tar zxf ~/software/RepBaseRepeatMaskerEdition-20181026.tar.gz

# 配置RepeatMasker
cd /opt/biosoft/RepeatMasker/
perl ./configure
# /opt/biosoft/RepeatMasker/trf           Enter
# 2                                       Enter
# /opt/biosoft/ncbi-rmblast-2.10.0+/bin   Enter
# Y                                       Enter
# 5                                       Enter


# Installing RepeatModeler (http://www.repeatmasker.org/RepeatModeler/)
# 需要先安装程序所依赖的软件：RECON、RepeatScout、LtrHarvest、Ltr_retriever、MAFFT、CD-HIT和Ninja
# Installing RECON (http://eddylab.org/software/recon/)
#wget http://www.repeatmasker.org/RepeatModeler/RECON-1.08.tar.gz -P ~/software/
tar zxf ~/software/RECON-1.08.tar.gz -C /opt/biosoft/
cd /opt/biosoft/RECON-1.08/src/
make && make install
# Installing RepeatScout (http://repeatscout.bioprojects.org)
#wget http://www.repeatmasker.org/RepeatScout-1.0.6.tar.gz -P ~/software/
tar zxf ~/software/RepeatScout-1.0.6.tar.gz -C /opt/biosoft/
cd /opt/biosoft/RepeatScout-1.0.6
make
# Installing LtrHarvest (http://genometools.org/pub/)
#wget http://genometools.org/pub/genometools-1.5.9.tar.gz -P ~/software/
cd && tar zxf ~/software/genometools-1.5.9.tar.gz
cd genometools-1.5.9
perl -p -i -e 's/-Werror/-Wno-error/g' Makefile
make prefix=//opt/biosoft/genometools-1.5.9/ install -j 4
cd ../ && rm -rf genometools-1.5.9
# Installing Ltr_retriever (https://github.com/oushujun/LTR_retriever/releases)
#wget https://github.com/oushujun/LTR_retriever/archive/v2.9.0.tar.gz -O ~/software/LTR_retriever-2.9.0.tar.gz
tar zxf ~/software/LTR_retriever-2.9.0.tar.gz -C /opt/biosoft/
# Installing MAFFT (https://mafft.cbrc.jp/alignment/software/)
#wget https://mafft.cbrc.jp/alignment/software/mafft-7.407-without-extensions-src.tgz -P ~/software
tar zxf ~/software/mafft-7.407-without-extensions-src.tgz
cd mafft-7.407-without-extensions/core/
perl -p -i -e 's#PREFIX =.*#PREFIX = /opt/biosoft/mafft#' Makefile
perl -p -i -e 's#BINDIR =.*#BINDIR = /opt/biosoft/mafft/bin/#' Makefile
make -j 4
make install
cd ../../ && rm -rf mafft-7.407-without-extensions
echo 'PATH=$PATH:/opt/biosoft/mafft/bin/' >> ~/.bashrc
source ~/.bashrc
# Installing CD-HIT (http://weizhongli-lab.org/cd-hit/ | https://github.com/weizhongli/cdhit)
#wget https://github.com/weizhongli/cdhit/releases/download/V4.8.1/cd-hit-v4.8.1-2019-0228.tar.gz -P ~/software
tar zxf ~/software/cd-hit-v4.8.1-2019-0228.tar.gz -C /opt/biosoft/
cd /opt/biosoft/cd-hit-v4.8.1-2019-0228
make -j 4
# Installing Ninja (https://github.com/TravisWheelerLab/NINJA/releases/tag/0.95-cluster_only)
#wget https://github.com/TravisWheelerLab/NINJA/archive/0.95-cluster_only.tar.gz -O ~/software/NINJA-0.95-cluster_only.tar.gz
tar zxf ~/software/NINJA-0.95-cluster_only.tar.gz -C /opt/biosoft/
cd /opt/biosoft/NINJA-0.95-cluster_only/NINJA/
make -j 4

# Installing RepeatModeler
#wget http://www.repeatmasker.org/RepeatModeler/RepeatModeler-2.0.1.tar.gz -P ~/software/
tar zxf ~/software/RepeatModeler-2.0.1.tar.gz -C /opt/biosoft/
cd /opt/biosoft/RepeatModeler-2.0.1
chmod 644 *.pm configure
echo 'PATH=$PATH:/opt/biosoft/RepeatModeler-2.0.1' >> ~/.bashrc
source ~/.bashrc

# 可能需要Perl模块JSON
#sudo cpan -i JSON

# 配置RepeatModeler
cd /opt/biosoft/RepeatModeler-2.0.1
perl configure
#                                             Enter
# /usr/bin/perl                               Enter
# /opt/biosoft/RepeatMasker                   Enter
# /opt/biosoft/RECON-1.08/bin                 Enter
# /opt/biosoft/RepeatScout-1.0.6              Enter
# /opt/biosoft/RepeatMasker/trf               Enter
# 1                                           Enter
# /opt/biosoft/ncbi-rmblast-2.10.0+/bin       Enter
# 3                                           Enter
# y                                           Enter
# /opt/biosoft/genometools-1.5.9/bin          Enter
# /opt/biosoft/LTR_retriever-2.9.0            Enter
# /opt/biosoft/mafft/bin                      Enter
# /opt/biosoft/NINJA-0.95-cluster_only/NINJA  Enter
# /opt/biosoft/cd-hit-v4.8.1-2019-0228        Enter
