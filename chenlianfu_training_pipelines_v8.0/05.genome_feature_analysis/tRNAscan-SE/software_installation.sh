# 安装 tRNAscan-SE (http://lowelab.ucsc.edu/tRNAscan-SE/)
#wget http://trna.ucsc.edu/software/trnascan-se-2.0.6.tar.gz -P ~/software
tar zxf ~/software/trnascan-se-2.0.6.tar.gz
cd tRNAscan-SE-2.0/
./configure --prefix=/opt/biosoft/tRNAscan-SE-2.0 && make -j 4 && make install
ln -s /opt/biosoft/infernal-1.1.3/bin/* /opt/biosoft/tRNAscan-SE-2.0/bin
cd .. && rm -rf tRNAscan-SE-2.0
echo 'PATH=$PATH:/opt/biosoft/tRNAscan-SE-2.0/bin/' >> ~/.bashrc
source ~/.bashrc

tar zxf ~/software/tRNAscan-SE-1.3.1.tar.gz
cd tRNAscan-SE-1.3.1
perl -p -i -e 's#\$\(HOME\)#/opt/biosoft/tRNAscan-SE-1.3.1#' Makefile
make && make install
echo 'PATH=$PATH:/opt/biosoft/tRNAscan-SE-1.3.1/bin/' >> ~/.bashrc
echo 'export PERL5LIB=$PERL5LIB:/opt/biosoft/tRNAscan-SE-1.3.1/bin/' >> ~/.bashrc
source ~/.bashrc
make testrun
cd ..
rm tRNAscan-SE-1.3.1/ -rf
