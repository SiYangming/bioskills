#!/usr/bin/env bash

#read in variables
#读取公共变量
source common_variables.sh

###This script will download <.sra> files and convert them to <.fastq> files. You will need to ensure you have the SRA toolkit correctly installed
###该脚本会下载 <.sra> 文件并将其转换为 <.fastq> 文件，你需要确保已正确安装 SRA toolkit。

#make a list of all the SRA numbers that you want to download (these normally begin SRR)
#列出所有需要下载的 SRA 号（通常以 SRR 开头）。
SRAs='SRR00000001 SRR00000002 SRR00000003 SRR00000004' #this is just a template and needs to be edited

#set the directory where SRA toolkit will download the <.sra> files. This will have been user defined when you installed SRA toolkit
#设置 SRA toolkit 下载 <.sra> 文件的目录，这在安装 SRA toolkit 时由用户指定。
SRA_dir='~/Downloads/SRA_downloads/sra' #this is just a template and needs to be edited

#make a temporary directory to store temporary files for fasterq-dump
#创建临时目录，用于 fasterq-dump 产生的中间文件。
temp_dir=${fastq_dir}/temp
mkdir $temp_dir

#download data with a for loop
#使用 for 循环下载数据。
for SRA in $SRAs
do
prefetch $SRA #this downloads the file as a <.sra>
#这一步将下载 <.sra> 文件。
fasterq-dump ${SRA_dir}/${SRA}.sra -O $fastq_dir -t $temp_dir #this converts the <.sra> to <.fastq>
#这一步将 <.sra> 转换为 <.fastq>。
rm ${SRA_dir}/${SRA}.sra #this deletes the <.sra> file which is no longer needed
#这一步删除已经不再需要的 <.sra> 文件。
done

#delete the temporary directory
#删除临时目录。
rmdir $temp_dir

#rename the files and compress them to save space
#重命名文件并压缩以节省空间。

mv ${fastq_dir}/SRR00000001.fastq ${fastq_dir}/RPFs_1.fastq
gzip ${fastq_dir}/RPFs_1.fastq

mv ${fastq_dir}/SRR00000002.fastq ${fastq_dir}/RPFs_2.fastq
gzip ${fastq_dir}/RPFs_2.fastq

mv ${fastq_dir}/SRR00000003.fastq ${fastq_dir}/RPFs_3.fastq
gzip ${fastq_dir}/RPFs_3.fastq

mv ${fastq_dir}/SRR00000004.fastq ${fastq_dir}/RPFs_4.fastq
gzip ${fastq_dir}/RPFs_4.fastq
