#!/usr/bin/env bash

#This script uses UMItools to extract the UMIs from the reads and add them to the read name
#该脚本使用 UMItools 从 reads 中提取 UMI 并将其附加到 read 名称中。
#The script is written for libraries which contain 4nt UMIs at both the 5' and 3' end of the read. If this is not the case for your libraries you will need to change the following part of the command
#该脚本假定文库在 reads 的 5' 和 3' 端各含有 4nt UMI；若你的文库结构不同，需要修改下面命令中的匹配模式：
#"--extract-method=regex --bc-pattern='^(?P<umi_1>.{4}).+(?P<umi_2>.{4})do
umi_tools extract -I $fastq_dir/${filename}_cutadapt.fastq --extract-method=regex --bc-pattern='^(?P<umi_1>.{4}).+(?P<umi_2>.{4})$' -S $fastq_dir/${filename}_UMI_clipped.fastq --log=$log_dir/${filename}_extracted_UMIs.log &
done
wait

#run fastqc on output
for filename in $RPF_filenames
do
fastqc $fastq_dir/${filename}_UMI_clipped.fastq --outdir=$fastqc_dir &
done
wait
"
#For more info on UMItools see https://github.com/CGATOxford/UMI-tools and https://umi-tools.readthedocs.io/en/latest/
#更多 UMItools 信息可参考：https://github.com/CGATOxford/UMI-tools 和 https://umi-tools.readthedocs.io/en/latest/

#It will output a new fastq file with the suffix _UMI_clipped
#该脚本会输出新的 fastq 文件，文件名后缀为 _UMI_clipped。
#It then runs fastQC on output to check it is as expected
#随后对输出 fastq 运行 fastQC 以检查处理结果是否符合预期。

#read in variables
#读取公共变量
source common_variables.sh

#extract UMIs
#提取 UMI
for filename in $RPF_filenames
do
umi_tools extract -I $fastq_dir/${filename}_cutadapt.fastq --extract-method=regex --bc-pattern='^(?P<umi_1>.{4}).+(?P<umi_2>.{4})$' -S $fastq_dir/${filename}_UMI_clipped.fastq --log=$log_dir/${filename}_extracted_UMIs.log &
done
wait

#run fastqc on output
for filename in $RPF_filenames
do
fastqc $fastq_dir/${filename}_UMI_clipped.fastq --outdir=$fastqc_dir &
done
wait
