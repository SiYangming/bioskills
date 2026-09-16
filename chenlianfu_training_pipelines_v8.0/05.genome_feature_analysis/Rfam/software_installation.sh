# 安装Rfam数据库比对软件Infernal/INFErence of RNa ALignments (http://eddylab.org/infernal/)
#wget http://eddylab.org/infernal/infernal-1.1.3.tar.gz -P ~/software/
tar zxf ~/software/infernal-1.1.3.tar.gz
cd infernal-1.1.3/
./configure --prefix=/opt/biosoft/infernal-1.1.3/
make -j 4 
make install
cd .. && rm -rf infernal-1.1.3/
echo 'PATH=$PATH:/opt/biosoft/infernal-1.1.3/bin' >> ~/.bashrc
source ~/.bashrc

# Installing Rfam Database (http://rfam.xfam.org/)
# Rfam 14.1 (January 2019, 3016 families)
#wget ftp://ftp.ebi.ac.uk/pub/databases/Rfam/CURRENT/Rfam.cm.gz -P ~/software/
gzip -dc ~/software/Rfam.cm.gz > /opt/biosoft/infernal-1.1.3/Rfam.cm
cmpress /opt/biosoft/infernal-1.1.3/Rfam.cm
