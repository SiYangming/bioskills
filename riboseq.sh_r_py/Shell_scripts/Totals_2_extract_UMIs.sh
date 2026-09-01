#!/usr/bin/env bash

#This script uses UMItools to extract the UMIs from the reads and add them to the read name
#该脚本使用 UMItools 从 reads 中提取 UMI 并将其添加到 read 名称中。
#The script is written for libraries which contain 12nt UMIs at the 5'end of the read. If this is not the case for your libraries you will need to change the following part of the command
#本脚本假定文库在 reads 5' 端含有 12nt UMI；如果你的文库不是这种结构，需要修改下面命令中的相应部分。
#"--bc-pattern=NNNNNNNNNNNN"
#即 \"--bc-pattern=NNNNNNNNNNNN\" 这一参数。
#For more info on UMItools see https://github.com/CGATOxford/UMI-tools and https://umi-tools.readthedocs.io/en/latest/
#更多 UMItools 说明见 https://github.com/CGATOxford/UMI-tools 与 https://umi-tools.readthedocs.io/en/latest/。

#It will output a new fastq file with the suffix _UMI_clipped
#脚本会输出一个以 _UMI_clipped 作为后缀的新 fastq 文件。
#It then runs fastQC on output to check it is as expected
#随后对输出文件运行 fastQC，以检查结果是否符合预期。

#read in variables
#读取公共变量
source common_variables.sh

#extract UMIs
#提取 UMI
for filename in $Totals_filenames
do
umi_tools extract -I $fastq_dir/${filename}_cutadapt.fastq -S $fastq_dir/${filename}_UMI_clipped.fastq --bc-pattern=NNNNNNNNNNNN --log=$log_dir/${filename}_extracted_UMIs.log &
done
wait

#run fastqc on output
#对输出运行 fastQC
for filename in $Totals_filenames
do
fastqc $fastq_dir/${filename}_UMI_clipped.fastq --outdir=$fastqc_dir &
done
wait
