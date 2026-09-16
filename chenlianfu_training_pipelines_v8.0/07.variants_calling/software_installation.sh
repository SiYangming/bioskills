# installing GATK (https://github.com/broadinstitute/gatk/releases | https://software.broadinstitute.org/gatk/blog)
#wget https://github.com/broadinstitute/gatk/releases/download/4.1.8.1/gatk-4.1.8.1.zip -P ~/software
unzip ~/software/gatk-4.1.8.1.zip -d /opt/biosoft
echo 'PATH=$PATH:/opt/biosoft/gatk-4.1.8.1/' >> ~/.bashrc
source ~/.bashrc


# installing snpEff (http://snpeff.sourceforge.net/)
#wget https://downloads.sourceforge.net/project/snpeff/snpEff_latest_core.zip -P ~/software/
unzip ~/software/snpEff_latest_core.zip -d /opt/biosoft/
