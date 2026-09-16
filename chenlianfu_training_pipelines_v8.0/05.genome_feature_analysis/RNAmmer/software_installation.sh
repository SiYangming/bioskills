# installing hmmer-2.2g (http://hmmer.org/download.html)
#wget http://eddylab.org/software/hmmer/hmmer-2.2g.tar.gz -P ~/software/
tar zxf ~/software/hmmer-2.2g.tar.gz
cd hmmer-2.2g
./configure --prefix=/opt/biosoft/hmmer-2.2g
mkdir -p /opt/biosoft/hmmer-2.2g/man/man1/ /opt/biosoft/hmmer-2.2g/bin
make
make install
cd .. && rm hmmer-2.2g -rf

# installing RNAmmer (http://www.cbs.dtu.dk/services/RNAmmer/)
# 下载需要填写edu邮箱和相关信息
tar zxf ~/software/rnammer-1.2.tar.gz -C /opt/biosoft/
perl -p -i -e 's/(my \$INSTALL_PATH).*/$1 = \"\/opt\/biosoft\/rnammer-1.2\";/' /opt/biosoft/rnammer-1.2/rnammer
perl -p -i -e 's/^(\s+\$HMMSEARCH_BINARY).*/$1 = \"\/opt\/biosoft\/hmmer-2.2g\/bin\/hmmsearch\";/' /opt/biosoft/rnammer-1.2/rnammer

# installing Perl Module
sudo cpan -i XML::Simple
