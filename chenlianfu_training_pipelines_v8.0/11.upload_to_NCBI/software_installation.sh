# installing sequin (https://www.ncbi.nlm.nih.gov/Sequin/)
#wget ftp://ftp.ncbi.nih.gov/sequin/sequin.linux-x86_64.tar.gz -P ~/software/
mkdir /opt/biosoft/sequin
tar zxf ~/software/sequin.linux-x86_64.tar.gz -C /opt/biosoft/sequin
echo 'PATH=$PATH:/opt/biosoft/sequin/' >> ~/.bashrc
source ~/.bashrc


# installing tbl2asn (https://www.ncbi.nlm.nih.gov/genbank/tbl2asn2/)
#wget ftp://ftp.ncbi.nih.gov/toolbox/ncbi_tools/converters/by_program/tbl2asn/linux64.tbl2asn.gz -P ~/software/
mkdir /opt/biosoft/tbl2asn
gzip -dc ~/software/linux64.tbl2asn.gz > /opt/biosoft/tbl2asn/tbl2asn
chmod 755 /opt/biosoft/tbl2asn/tbl2asn
echo 'PATH=$PATH:/opt/biosoft/tbl2asn/' >> ~/.bashrc
source ~/.bashrc
