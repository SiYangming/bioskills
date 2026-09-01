#!/usr/bin/env bash

#This script will demulitplex the bcl data and write a <.fastq> file for each sample. Make sure the bcl_dir and fastq_dir are specified in the common_variables.sh script.
#该脚本对 bcl 数据进行样本拆分，并为每个样本生成一个 <.fastq> 文件。请确保在 common_variables.sh 中正确设置 bcl_dir 和 fastq_dir。
#All raw sequencing data needs to be saved in the R11/raw_sequencing_data. Create your own directory in here and place each directory for each sequencing run (this is the bcl_dir) in that directory.
#所有原始测序数据需要保存在 R11/raw_sequencing_data 下；在其中为本项目创建自己的目录，并将每次测序运行产生的目录（即 bcl_dir）放到该目录中。
#bcl2fastq is used to convert bcl files to fastq. This can be downloaded with conda.
#使用 bcl2fastq 将 bcl 文件转换为 fastq，可通过 conda 安装。
#You will need to complete a sampleSheet.csv file for each run, which specifies which samples have which barcodes. This needs to be in bcl_dir.
#每次测序运行都需要准备一个 sampleSheet.csv，指定样本与条形码的对应关系，该文件需要保存在 bcl_dir 中。
#-p denotes how many threads to use
#-p 指定使用的线程数。
#use the --no-lane-splitting option so that you get one fastq file per sample and not four (there are four seperate lanes in the NextSeq, but unless you suspect there have been any sequencing issues these can be combined
#使用 --no-lane-splitting 选项，以便每个样本只生成一个 fastq 文件而不是四个（NextSeq 有四条 lane，除非怀疑某条 lane 有问题，一般可以将数据合并）。
#use --barcode-mismatches 0 so that only the extact barcodes are used.
#使用 --barcode-mismatches 0，确保只使用完全匹配的条形码。

#read in variables
#读取公共变量
source common_variables.sh

#run blc2fastq
#运行 bcl2fastq
bcl2fastq -p $threadN --no-lane-splitting --runfolder-dir $bcl_dir --output-dir $fastq_dir --barcode-mismatches 0
