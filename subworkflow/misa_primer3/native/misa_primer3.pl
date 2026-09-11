#!/usr/bin/perl
# ---------------------------------------------------------------------------
# 来源（vendored，2026-09-10 取自上游并逐字核对）：
#   https://github.com/SiYangming/SSR_marker_design/blob/master/misa_primer3.pl
#   上游 sha256: c451d1d00aee00d2f7a1ac3c03b297bcc9ed7cd1dcddceec4f665abbaed80d60
# 本副本相对上游的唯一功能改动：并行调用 ParaFly 的重定向 `&> /dev/null` → `> /dev/null 2>&1`。
#   原因：`&>` 是 bash 扩展，Debian/Ubuntu 的 /bin/sh（dash）会报 Syntax error，而 perl 的
#   system() 走 /bin/sh → 在容器/Debian 环境下必然 die "Excute Failed"。其余逻辑与上游一致。
# 归属：subworkflow/misa_primer3/native/（MISA + Primer3 SSR 检测与引物设计组合的桥接脚本）
# 依赖：primer3_core（modules/primer3）+ ParaFly（--CPU 并行）+ perl
# ---------------------------------------------------------------------------
use strict;
use Getopt::Long;

my $usage = <<USAGE;
Usage:
    perl $0 genome.fasta.misa genome.fasta > SSR_primer3.out

    --flanking_length <INT>  Default: 300
        设计引物时提取SSR两侧翼该长度的序列作为Primer3输入的模板序列。

    --min_product_length <INT>  Default: 100
        引物得到的最小产物长度。

    --max_product_length <INT>  Default: 250
        引物得到的最大产物长度。

    --CPU <INT>  Default:1
        程序调用ParaFly命令进行并行化计算，该参数设置并行数。

    --p3_setting_file <STRING>
        程序使用Primer3进行引物批量设计，该参数设置所使用的Primer3配置文件。若不输入该参数，Primer3默认得到的结果会很差。
        
    --gff3_out <STRING>
        可以选择输出GFF3格式的结果。

USAGE
if (@ARGV==0){die $usage}

my ($flanking_length, $min_product_length, $max_product_length, $CPU, $p3_setting_file, $gff3_out);
GetOptions(
    "flanking_length:i" => \$flanking_length,
    "min_product_length:i" => \$min_product_length,
    "max_product_length:i" => \$max_product_length,
    "CPU:i" => \$CPU,
    "p3_setting_file:s" => \$p3_setting_file,
    "gff3_out:s" => \$gff3_out,
);

$flanking_length ||= 300;
$min_product_length ||= 100;
$max_product_length ||= 250;
$CPU ||= 1;
warn "Warning: No Primer3 config file\n" unless $p3_setting_file;

open IN, '<', $ARGV[1] or die $!;
my ($seqID, %seq);
while (<IN>) {
    chomp;
    if (/^>(\S+)/) { $seqID = $1 }
    else { $seq{$seqID} .= $_ }
}
close IN;

open IN, '<', $ARGV[0] or die $!;
open COM, '>', "misa_primer3.commands" or die $!;
mkdir "misa_primer3.tmp" unless -e "misa_primer3.tmp";
<IN>;
my (@ID, %gff);
while (<IN>) {
    chomp;
    my @misa = split /\t/, $_;
    my $ID = "$misa[0]_$misa[1]";
    push @ID, $ID;
    open OUT, '>', "misa_primer3.tmp/$ID" or die $!;
    $gff{$ID}{"total"} = $_;
    $gff{$ID}{"seqName"} = $misa[0];
    $gff{$ID}{"ID"} = $ID;
    $gff{$ID}{"attribute"} = "ID=$misa[0]_$misa[1];Type=$misa[2];SSR=$misa[3];Size=$misa[4];";
    $gff{$ID}{"start"} = $misa[5];
    $gff{$ID}{"end"} = $misa[6];
    my $seq = $seq{$misa[0]};
    my $start = $misa[5] - $flanking_length - 1;
    my $target_pos;
    if ($start < 0) {
        $start = 0;
        $target_pos = $misa[5];
    }
    else {
        $target_pos = $flanking_length + 1;
    }
    my $length = $misa[6] - $start + $flanking_length;
    my $subseq = substr($seq, $start, $length);
    print OUT "SEQUENCE_ID=$ID\nSEQUENCE_TEMPLATE=$subseq\nSEQUENCE_TARGET=$target_pos,$misa[4]\nPRIMER_PRODUCT_SIZE_RANGE=$min_product_length-$max_product_length\nSEQUENCE_INTERNAL_EXCLUDED_REGION=$target_pos,$misa[4]\n=\n";
    close OUT;
    if ($p3_setting_file) {
        print COM "primer3_core -p3_settings_file $p3_setting_file -strict_tags misa_primer3.tmp/$ID > misa_primer3.tmp/$ID.out\n";
    }
    else {
        print COM "primer3_core -strict_tags misa_primer3.tmp/$ID > misa_primer3.tmp/$ID.out\n";
    }
}
close IN;
close COM;

my $cmdString = "ParaFly -c misa_primer3.commands -CPU $CPU > /dev/null 2>&1";
(system $cmdString) == 0 or die "Excute Failed: $cmdString\n";

print "ID\tSSR nr.\tSSR type\tSSR\tsize\tstart\tend\tleft PRIMER1\tTm\tsize\tRight Primer1\t\tTm\tsize\tProduct size\tleft PRIMER2\tTm\tsize\tRight Primer2\t\tTm\tsize\tProduct size\tleft PRIMER3\tTm\tsize\tRight Primer3\t\tTm\tsize\tProduct size\tleft PRIMER4\tTm\tsize\tRight Primer4\t\tTm\tsize\tProduct size\tleft PRIMER5\tTm\tsize\tRight Primer5\t\tTm\tsize\tProduct size\n";
if ($gff3_out) {
    open GFF3, ">", $gff3_out or die $!; 
}

foreach (@ID) {
    open IN, '<', "misa_primer3.tmp/$_.out" or die $!;
    my $misa_primer3_out = $gff{$_}{"total"} . "\t";
    my $misa_primer3_gff = $gff{$_}{"seqName"} . "\t" . "misa_primer3\tSSR\t" . $gff{$_}{"start"} . "\t" . $gff{$_}{"end"} . "\t\.\t\.\t\.\t" . $gff{$_}{"attribute"};
    my $primer_annotation = join "", <IN>;
    my $num = 0;
    foreach my $code(0..4) {
        $num ++;
        if ($primer_annotation =~ /PRIMER_LEFT_${code}_SEQUENCE=(\w+)/) {
            $misa_primer3_out .= "$1\t";
            $misa_primer3_gff .= "Primer_${num}_left_seq=$1;";
            $primer_annotation =~ m/PRIMER_LEFT_${code}_TM=(.*)/;
            $misa_primer3_out .= "$1\t";
            $misa_primer3_gff .= "Primer_${num}_left_tm=$1;";
            $primer_annotation =~ m/PRIMER_LEFT_${code}=\d+,(\d+)/;
            $misa_primer3_out .= "$1\t";
            $misa_primer3_gff .= "Primer_${num}_left_size=$1;";
            $primer_annotation =~ m/PRIMER_RIGHT_${code}_SEQUENCE=(\w+)/;
            $misa_primer3_out .= "$1\t";
            $misa_primer3_gff .= "Primer_${num}_right_seq=$1;";
            $primer_annotation =~ m/PRIMER_RIGHT_${code}_TM=(.*)/;
            $misa_primer3_out .= "$1\t";
            $misa_primer3_gff .= "Primer_${num}_right_tm=$1;";
            $primer_annotation =~ m/PRIMER_RIGHT_${code}=\d+,(\d+)/;
            $misa_primer3_out .= "$1\t";
            $misa_primer3_gff .= "Primer_${num}_right_size=$1;";
            $primer_annotation =~ m/PRIMER_PAIR_${code}_PRODUCT_SIZE=(\d+)/;
            $misa_primer3_out .= "$1\t";
            $misa_primer3_gff .= "Primer_${num}_product_size=$1;";
        }
    }
    close IN;
    print GFF3 "$misa_primer3_gff\n" if $gff3_out;
    print "$misa_primer3_out\n";
}
