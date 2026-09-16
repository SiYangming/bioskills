# installing lftp
sudo yum -y install lftp

# installing Aspera (https://downloads.asperasoft.com/connect2/)
#wget https://d3gcli72yxqn2z.cloudfront.net/connect/bin/ibm-aspera-connect-3.8.3.170430-linux-g2.12-64.tar.gz -P ~/software/
tar zxf ~/software/ibm-aspera-connect-3.8.3.170430-linux-g2.12-64.tar.gz
./ibm-aspera-connect-3.8.3.170430-linux-g2.12-64.sh
rm ./ibm-aspera-connect-3.8.3.170430-linux-g2.12-64.sh
echo 'PATH=$PATH:/home/train/.aspera/connect/bin/' >> ~/.bashrc
source ~/.bashrc

# installing sratoolkit (https://github.com/ncbi/sra-tools/wiki/Downloads | https://ftp-trace.ncbi.nlm.nih.gov/sra/sdk/current/)
#wget https://ftp-trace.ncbi.nlm.nih.gov/sra/sdk/current/sratoolkit.current-centos_linux64.tar.gz -P ~/software/
tar zxf ~/software/sratoolkit.current-centos_linux64.tar.gz -C /opt/biosoft/
NEW=`ls -dt /opt/biosoft/sratoolkit* | head -n 1`
ln -sfn $NEW /opt/biosoft/sratoolkit
echo 'PATH=$PATH:/opt/biosoft/sratoolkit/bin/' >> ~/.bashrc
source ~/.bashrc
