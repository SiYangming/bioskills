#!/usr/bin/env bash

#This script runs cutadapt on all your raw fastq files. For more info on settings see https://cutadapt.readthedocs.io/en/stable/guide.html
#该脚本对所有原始 totals fastq 文件运行 cutadapt，更多参数说明见：https://cutadapt.readthedocs.io/en/stable/guide.html

#You need to make sure the 3' adaptor sequence in the variables.txt file is correct. The -a option specifies this here
#请确保 variables.txt（或 common_variables）中设置的 3' 接头序列正确，此处通过 -a 选项指定。

#The --nextseq-trim=20 option will trim bases from the 3' end if the quality score is below 20. This is only for sequencing data generated on the
#Next-seq (which is what we have here at the Beatson). If using external data set that has been sequenced on a Hi-seq, replace this command with -q 20
#It should state which sequencing platform was used on the GEO page
#The following text from the cutadpat manual explains why this is
#--nextseq-trim=20 会从 reads 3' 端剪切质量值低于 20 的碱基，仅适用于 NextSeq 等双色平台；若外部数据使用 HiSeq 等平台，应改用 -q 20。GEO 页面通常会注明测序平台，下面说明引自 cutadapt 手册解释这一差异。

#Some Illumina instruments use a two-color chemistry to encode the four bases. This includes the NextSeq and the NovaSeq.
#In those instruments, a ‘dark cycle’ (with no detected color) encodes a G. However, dark cycles also occur when sequencing “falls off” the end of the fragment.
#The read then contains a run of high-quality, but incorrect “G” calls at its 3’ end.
#Since the regular quality-trimming algorithm cannot deal with this situation, you need to use the --nextseq-trim option:
#This works like regular quality trimming (where one would use -q 20 instead), except that the qualities of G bases are ignored.
#部分 Illumina 仪器（如 NextSeq、NovaSeq）采用双色化学；在这些平台上，“无信号”的 dark cycle 会被解释为 G，但当测序走到片段末端时也会出现 dark cycle，从而在 reads 3' 端产生一段高质量但错误的 G。常规质控剪切算法无法处理这种情况，因此需要使用 --nextseq-trim 选项：其行为类似于使用 -q 20 的常规质控剪切，但会忽略 G 的质量值。

#-m specifies the minimum read lengths following adaptor removal and base trimming, which we set as 30. As the fragment length for total RNA-seq is normally longer than the sequencing length no upper limit is specified
#-m 指定去接头和剪切之后保留的最小 read 长度，这里设置为 30；由于总 RNA‑seq 片段长度通常长于测序长度，因此不设定上限。

#1> causes all the text that is normally printed to the screen to be saved in a log file in your logs directory for each sample
#1> 会将原本输出到屏幕上的信息重定向到 logs 目录中每个样本对应的日志文件。

#once cutadapt is complete, fastQC is ran on the output fastq files to check they are as expected
#cutadapt 运行完成后，会对输出 fastq 再次运行 fastQC 以检查结果是否符合预期。

#read in variables
#读取公共变量
source common_variables.sh

#run cutadapt
#运行 cutadapt
for filename in $Totals_filenames
do
cutadapt $fastq_dir/${filename}.fastq -a $Totals_adaptor --nextseq-trim=20 -m 30 --cores=0 -o $fastq_dir/${filename}_cutadapt.fastq 1> $log_dir/${filename}_cutadapt_log.txt
done

#run fastqc on cutadapt output
for filename in $Totals_filenames
do
fastqc $fastq_dir/${filename}_cutadapt.fastq --outdir=$fastqc_dir &
done
wait
