# installing cufflinks (http://cole-trapnell-lab.github.io/cufflinks/)
tar zxf ~/software/cufflinks-2.2.1.Linux_x86_64.tar.gz -C /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/cufflinks-2.2.1.Linux_x86_64/' >> ~/.bashrc
source ~/.bashrc


# installing stringtie (http://ccb.jhu.edu/software/stringtie/)
#wget http://ccb.jhu.edu/software/stringtie/dl/stringtie-2.1.3.Linux_x86_64.tar.gz -P ~/software/
tar zxf ~/software/stringtie-2.1.3.Linux_x86_64.tar.gz -C /opt/biosoft/
echo 'PATH=$PATH:/opt/biosoft/stringtie-2.1.3.Linux_x86_64/' >> ~/.bashrc
source ~/.bashrc

#wget https://ccb.jhu.edu/software/stringtie/dl/prepDE.py -P ~/software
#chmod 755 ~/software/prepDE.py
cp ~/software/prepDE.py /opt/biosoft/stringtie-2.1.3.Linux_x86_64/


# installing HTSeq (https://htseq.readthedocs.io/en/release_0.11.1/overview.html)
pip install HTSeq -i https://mirrors.aliyun.com/pypi/simple/
