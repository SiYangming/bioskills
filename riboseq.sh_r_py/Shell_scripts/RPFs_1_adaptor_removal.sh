#!/usr/bin/env bash

#This script runs cutadapt on all your raw fastq files. For more info on settings see https://cutadapt.readthedocs.io/en/stable/guide.html
#该脚本对所有原始 RPF fastq 文件运行 cutadapt，更多参数说明见：https://cutadapt.readthedocs.io/en/stable/guide.html

#You need to make sure the 3' adaptor sequence in the variables.txt file is correct. The -a option specifies this here
#请确保 variables.txt（或 common_variables）中设置的 3' 接头序列正确，此处通过 -a 选项指定。

#The --nextseq-trim=20 option will trim bases from the 3' end if the quality score is below 20. This is only for sequencing data generated on the
#Next-seq (which is what we have here at the Beatson). If using external data set that has been sequenced on a Hi-seq, replace this command with -q 20
#It should state which sequencing platform was used on the GEO page
#The following text from the cutadpat manual explains why this is
#--nextseq-trim=20 会从 reads 3' 端开始剪切质量值低于 20 的碱基，仅适用于 NextSeq 等双色平台（如本地 Beatson 数据）；若外部数据使用的是 HiSeq 等平台，应改用 -q 20。GEO 页面通常会注明测序平台，下面的说明引用自 cutadapt 手册解释这一差异。

#Some Illumina instruments use a two-color chemistry to encode the four bases. This includes the NextSeq and the NovaSeq.
#In those instruments, a ‘dark cycle’ (with no detected color) encodes a G. However, dark cycles also occur when sequencing “falls off” the end of the fragment.
#The read then contains a run of high-quality, but incorrect “G” calls at its 3’ end.
#Since the regular quality-trimming algorithm cannot deal with this situation, you need to use the --nextseq-trim option:
#This works like regular quality trimming (where one would use -q 20 instead), except that the qualities of G bases are ignored.
#部分 Illumina 仪器（如 NextSeq、NovaSeq）采用双色化学来编码四种碱基：在这类平台上，“无信号”的 dark cycle 被解释为 G，但当测序走到片段末端时也会出现 dark cycle，从而在 reads 3' 端产生一段高质量但错误的 G。常规质控剪切算法无法正确处理这一现象，因此需要使用 --nextseq-trim 选项，它类似于常规 -q 20 剪切，但会忽略 G 的质量值。

#-m and -M specify the minimum and Maximum read lengths following adaptor removal and base trimming. RPFs should be roughly 30nt but can vary.
#However if the libraries also contain UMIs then you need to add this on too. UMIs from the nextflex kit that we use are 4nt on each end of the read
#therefore a 30nt RPF should be 38nt with UMIs following adaptor removal. Using -m 30 -M 50 means after UMI removal you will be left with read lengths 22-42
#which is suitable for this situation but will need to be modified to suit specific needs if using external data which may have different UMI lengths or may not contain UMIs
#-m 和 -M 分别指定去接头和剪切后保留的最小和最大 read 长度。RPF 理论长度约为 30nt，但会有一定浮动；如果文库中还包含 UMI，则需要把 UMI 长度加上。我们使用的 nextflex 试剂盒在每条 read 两端各有 4nt UMI，因而 30nt RPF 在去接头后长度约为 38nt。使用 -m 30 -M 50，意味着在后续去除 UMI 后，保留下来的是 22–42nt 的 reads，适用于本数据，但若使用外部数据（UMI 长度不同或无 UMI），需要按实际情况调整。

#--cores=0 will automatically detect the number of cores available on the system and use this amount
#--cores=0 会自动检测系统可用核心数并全部使用。

#1> causes all the text that is normally printed to the screen to be saved in a log file in your logs directory for each sample
#1> 会将原本打印到屏幕上的标准输出信息重定向到 logs 目录中对应样本的日志文件。

#once cutadapt is complete, fastQC is ran on the output fastq files to check they are as expected
#cutadapt 运行完成后，会对输出 fastq 再次运行 fastQC 以检查结果是否符合预期。

#read in variables
#读取公共变量
source common_variables.sh

#run cutadapt
#运行 cutadapt
for filename in $RPF_filenames
do
cutadapt $fastq_dir/${filename}.fastq -a $RPF_adaptor --nextseq-trim=20 -m 30 -M 50 --cores=0 -o $fastq_dir/${filename}_cutadapt.fastq 1> $log_dir/${filename}_cutadapt_log.txt
done

#run fastqc on cutadapt output
#对 cutadapt 输出运行 fastQC 检查质量。
for filename in $RPF_filenames
do
fastqc $fastq_dir/${filename}_cutadapt.fastq --outdir=$fastqc_dir &
done
wait
