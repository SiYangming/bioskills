# installing trinity (https://github.com/trinityrnaseq/trinityrnaseq/releases)
#wget https://github.com/trinityrnaseq/trinityrnaseq/releases/download/v2.11.0/trinityrnaseq-v2.11.0.FULL.tar.gz -P ~/software/
tar zxf ~/software/trinityrnaseq-v2.11.0.FULL.tar.gz
mv trinityrnaseq-v2.11.0/ /opt/biosoft/Trinity-v2.11.0
cd /opt/biosoft/Trinity-v2.11.0
make -j 4
make plugins
echo 'PATH=$PATH:/opt/biosoft/Trinity-v2.11.0/' >> ~/.bashrc
source ~/.bashrc

# installing Jellyfish (http://www.genome.umd.edu/jellyfish.html)
# Trinity的运行需要依赖jellyfish version 2。Jellyfish两个版本并存，注意不要下错了。
#wget https://github.com/gmarcais/Jellyfish/releases/download/v2.3.0/jellyfish-linux -P ~/software/
cp /home/train/software/jellyfish-linux /opt/biosoft/Trinity-v2.11.0/jellyfish
chmod 755 /opt/biosoft/Trinity-v2.11.0/jellyfish

# installing samlomon (https://combine-lab.github.io/salmon/ | https://github.com/COMBINE-lab/salmon)
#wget https://github.com/COMBINE-lab/salmon/releases/download/v1.3.0/salmon-1.3.0_linux_x86_64.tar.gz -P ~/software/
tar zxf ~/software/salmon-1.3.0_linux_x86_64.tar.gz -C /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/salmon-latest_linux_x86_64/bin/' >> ~/.bashrc
source ~/.bashrc

#tar zxf /home/train/software/R-4.0.2.CentOS8.1_1911_opt_sysoft.tar.gz -C /opt/sysoft/
#echo 'PATH=$PATH:/opt/sysoft/R-3.5.3/bin/' >> ~/.bashrc
#source ~/.bashrc

#installing RSEM (http://deweylab.github.io/RSEM/)
#wget https://github.com/deweylab/RSEM/archive/v1.3.3.tar.gz -O ~/software/RSEM-v1.3.3.tar.gz
tar zxf ~/software/RSEM-v1.3.3.tar.gz -C /opt/biosoft/
cd /opt/biosoft/RSEM-1.3.3/
make -j 4
echo 'PATH=$PATH:/opt/biosoft/RSEM-1.3.3/' >> ~/.bashrc
source ~/.bashrc 

#wget https://github.com/pachterlab/kallisto/releases/download/v0.46.2/kallisto_linux-v0.46.2.tar.gz -P ~/software/
tar zxf ~/software/kallisto_linux-v0.46.2.tar.gz -C /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/kallisto' >> ~/.bashrc
source ~/.bashrc

# installing TransDecoder (https://github.com/TransDecoder/TransDecoder/releases)
#wget https://github.com/TransDecoder/TransDecoder/archive/TransDecoder-v5.5.0.tar.gz -P ~/software/
tar zxf ~/software/TransDecoder-v5.5.0.tar.gz -C /opt/biosoft/
mv /opt/biosoft/TransDecoder-TransDecoder-v5.5.0 /opt/biosoft/TransDecoder-v5.5.0
cd /opt/biosoft/TransDecoder-v5.5.0/
make -j 4
echo 'PATH=$PATH:/opt/biosoft/TransDecoder-v5.5.0/' >> ~/.bashrc
source ~/.bashrc

# installing hmmer (http://hmmer.org/)
#wget http://eddylab.org/software/hmmer/hmmer-3.3.1.tar.gz -P ~/software/
tar zxf ~/software/hmmer-3.3.1.tar.gz 
cd hmmer-3.3.1/
./configure --prefix=/opt/biosoft/hmmer-3.3.1 && make -j 4 && make install
cd .. && rm -rf hmmer-3.3.1
echo 'PATH=/opt/biosoft/hmmer-3.3.1/bin/:$PATH' >> ~/.bashrc
source ~/.bashrc
cd /opt/biosoft/hmmer-3.3.1
# installing Pfam v27 (http://pfam.xfam.org/ | ftp://ftp.ebi.ac.uk/pub/databases/Pfam/releases/Pfam27.0/)
#wegt ftp://ftp.ebi.ac.uk/pub/databases/Pfam/releases/Pfam27.0/Pfam-A.hmm.gz -O ~/software/Pfam-A_V27.hmm.gz
#wget ftp://ftp.ebi.ac.uk/pub/databases/Pfam/releases/Pfam27.0/Pfam-B.hmm.gz -O ~/software/Pfam-B_V27.hmm.gz
gzip -dc ~/software/Pfam-A_V27.hmm.gz > Pfam-AB.hmm
gzip -dc ~/software/Pfam-B_V27.hmm.gz >> Pfam-AB.hmm
hmmpress Pfam-AB.hmm
rm Pfam-AB.hmm
