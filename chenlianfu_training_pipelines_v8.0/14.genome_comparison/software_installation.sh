# installing MCL (https://www.micans.org/mcl/)
#wget https://www.micans.org/mcl/src/mcl-14-137.tar.gz -P ~/software/
tar zxf ~/software/mcl-14-137.tar.gz
cd mcl-14-137/
./configure --prefix=/opt/biosoft/mcl-14-137/ && make -j 4 && make install
cd .. && rm -rf mcl-14-137/
echo 'PATH=$PATH:/opt/biosoft/mcl-14-137/bin/' >> ~/.bashrc 
source ~/.bashrc 

# installing OrthoMCL (http://orthomcl.org/orthomcl/)
#wget http://orthomcl.org/common/downloads/software/v2.0/orthomclSoftware-v2.0.9.tar.gz -P ~/software/
tar zxf ~/software/orthomclSoftware-v2.0.9.tar.gz -C /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/orthomclSoftware-v2.0.9/bin/' >> ~/.bashrc
source ~/.bashrc

# installing mafft (https://mafft.cbrc.jp/alignment/software/)
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

# installing Gblocks (http://molevol.cmima.csic.es/castresana/Gblocks.html)
#wget http://molevol.cmima.csic.es/castresana/Gblocks/Gblocks_Linux64_0.91b.tar.Z -P ~/software/
tar zxf ~/software/Gblocks_Linux64_0.91b.tar.gz -C /opt/biosoft/
chmod 755 /opt/biosoft/Gblocks_0.91b
echo 'PATH=$PATH:/opt/biosoft/Gblocks_0.91b/' >> ~/.bashrc
source ~/.bashrc

# installing PAML
#wget http://abacus.gene.ucl.ac.uk/software/paml4.9i.tgz -P ~/software/
tar zxf ~/software/paml4.9i.tgz -C /opt/biosoft/
cd /opt/biosoft/paml4.9i/
rm bin/*
cd src
make -f Makefile
cp baseml basemlg chi2 codeml evolver infinitesites mcmctree pamp yn00 ../bin
echo 'PATH=$PATH:/opt/biosoft/paml4.9i/bin' >> ~/.bashrc
source ~/.bashrc

# installing prottest (https://github.com/ddarriba/prottest3/releases)
#wget https://github.com/ddarriba/prottest3/releases/download/3.4.2-release/prottest-3.4.2-20160508.tar.gz -P ~/software/
tar zxf ~/software/prottest-3.4.2-20160508.tar.gz -C /opt/biosoft/
echo 'export PROTTEST_HOME=/opt/biosoft/prottest-3.4.2' >> ~/.bashrc
source ~/.bashrc

# installing RAxML (https://github.com/stamatak/standard-RAxML | https://cme.h-its.org/exelixis/web/software/raxml/index.html)
#wget https://github.com/stamatak/standard-RAxML/archive/v8.2.12.tar.gz -O ~/software/RAxML-v8.2.12.tar.gz
tar zxf ~/software/RAxML-v8.2.12.tar.gz -C /opt/biosoft/
mv /opt/biosoft/standard-RAxML-8.2.12/ /opt/biosoft/RAxML-8.2.12/
cd /opt/biosoft/RAxML-8.2.12/
make -f Makefile.SSE3.PTHREADS.gcc -j 4
rm *.o
make -f Makefile.AVX.PTHREADS.gcc -j 4
rm *.o
export C_INCLUDE_PATH=/usr/include/mpich-x86_64:$C_INCLUDE_PATH
export LD_LIBRARY_PATH=/usr/lib64/mpich/lib:$LD_LIBRARY_PATH
export PATH=/usr/lib64/mpich/bin:$PATH
make -f Makefile.SSE3.HYBRID.gcc -j 4
rm *.o
make -f Makefile.AVX.HYBRID.gcc -j 4
rm *.o
chmod 755 /opt/biosoft/RAxML-8.2.12/usefulScripts/*
echo 'PATH=$PATH:/opt/biosoft/RAxML-8.2.12/' >> ~/.bashrc
source ~/.bashrc

# installing FigTree (http://tree.bio.ed.ac.uk/software/figtree/ | https://github.com/rambaut/figtree/releases)
#wget https://github.com/rambaut/figtree/releases/download/v1.4.4/FigTree_v1.4.4.tgz -P ~/software
tar zxf ~/software/FigTree_v1.4.4.tgz -C /opt/biosoft/

# installing r8s (https://sourceforge.net/projects/r8s/)
#wget https://sourceforge.net/projects/r8s/files/r8s1.81.tar.gz -P ~/software/
tar zxf ~/software/r8s1.81.tar.gz -C /opt/biosoft/
cd /opt/biosoft/r8s1.81/src
make -j 4
echo 'PATH=$PATH:/opt/biosoft/r8s1.81/src' >> ~/.bashrc
source ~/.bashrc

# installing BEAST2 (https://www.beast2.org/ | https://github.com/CompEvol/beast2)
#wget https://github.com/CompEvol/beast2/releases/download/v2.5.2/BEAST.v2.5.2.Linux.tgz -P ~/software/
tar zxf ~/software/BEAST.v2.5.2.Linux.tgz -C /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/beast/bin/' >> ~/.bashrc
source ~/.bashrc

# installing BEAGLE (https://github.com/beagle-dev/beagle-lib)
#wget https://github.com/beagle-dev/beagle-lib/archive/v3.1.2.tar.gz -O ~/software/beagle-lib-3.1.2.tar.gz
tar zxf ~/software/beagle-lib-3.1.2.tar.gz
cd beagle-lib-3.1.2/
./autogen.sh 
./configure --prefix=/opt/biosoft/beagle-lib-3.1.2
make -j 8
make install
echo 'export PKG_CONFIG_PATH=/opt/biosoft/beagle-lib-3.1.2/lib/lib/pkgconfig:$PKG_CONFIG_PATH
export LD_LIBRARY_PATH=/opt/biosoft/beagle-lib-3.1.2/lib/:$LD_LIBRARY_PATH
export C_INCLUDE_PATH=/opt/biosoft/beagle-lib-3.1.2/include:$C_INCLUDE_PATH' >> ~/.bashrc

# installing Tracer (http://tree.bio.ed.ac.uk/software/tracer/)
#wget https://github.com/beast-dev/tracer/releases/download/v1.7.1/Tracer_v1.7.1.tgz -P ~/software
tar zxf ~/software/Tracer_v1.7.1.tgz -C /opt/biosoft/
chmod 755 /opt/biosoft/Tracer_v1.7.1/bin/tracer 
echo 'PATH=$PATH:/opt/biosoft/Tracer_v1.7.1/bin/' >> ~/.bashrc
source ~/.bashrc


# installing CAFE (https://github.com/hahnlab/CAFE)
#wget https://github.com/hahnlab/CAFE/archive/v4.2.1.tar.gz -O ~/software/CAFE-4.2.1.tar.gz
tar zxf ~/software/CAFE-4.2.1.tar.gz -C /opt/biosoft
cd /opt/biosoft/CAFE-4.2.1
./configure && make -j 4
mkdir bin
cp cafe/caferror.py release/cafe bin/
perl -p -i -e 's#/usr/bin/python#/usr/bin/env python#' /opt/biosoft/CAFE-4.2.1/bin/caferror.py
echo 'PATH=$PATH:/opt/biosoft/CAFE-4.2.1/bin/' >> ~/.bashrc
source ~/.bashrc

# install MCScanX (http://chibba.pgml.uga.edu/mcscan2/)
#wget http://chibba.pgml.uga.edu/mcscan2/MCScanX.zip -P ~/software/
unzip ~/software/MCScanX.zip -d /opt/biosoft/
cd /opt/biosoft/MCScanX/
#make
echo 'PATH=$PATH:/opt/biosoft/MCScanX/' >> ~/.bashrc
source ~/.bashrc

# installing MUMmer (https://github.com/mummer4/mummer)
#wget https://github.com/mummer4/mummer/releases/download/v4.0.0beta2/mummer-4.0.0beta2.tar.gz -P ~/software
tar zxf ~/software/mummer-4.0.0beta2.tar.gz
cd mummer-4.0.0beta2
./configure --prefix=/opt/biosoft/mummer-4.0.0beta2 && make -j 24 && make install
cd .. && rm -rf mummer-4.0.0beta2
echo 'PATH=$PATH:/opt/biosoft/mummer-4.0.0beta2/bin/' >> ~/.bashrc
source ~/.bashrc

# installing Mauve (http://darlinglab.org/mauve/mauve.html)
#wget http://darlinglab.org/mauve/downloads/mauve_linux_2.4.0.tar.gz -P ~/software/
tar zxf ~/software/mauve_linux_2.4.0.tar.gz -C /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/mauve_2.4.0/' >> ~/.bashrc
source ~/.bashrc
