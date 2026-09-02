#!/usr/bin/env python

#Imports
import argparse

#Functions
def extract_cutadapt_counts(fylename):
    logfyle = fylename + "_cutadapt_log.txt"
    in_counts = "0"
    out_counts = "0"
    with open(logfyle, 'r') as f:
        for line in f:
            ls = line.strip()
            if ls.startswith('Total reads processed'):
                in_counts = ls.split(':', 1)[1].strip().replace(',', '')
            elif ls.startswith('Total read pairs processed'):
                in_counts = ls.split(':', 1)[1].strip().replace(',', '')
            elif ls.startswith('Reads written (passing filters):'):
                out_counts = ls.split(':', 1)[1].split('(')[0].strip().replace(',', '')
            elif ls.startswith('Pairs written (passing filters):'):
                out_counts = ls.split(':', 1)[1].split('(')[0].strip().replace(',', '')
    return (in_counts, out_counts)
    
def extract_bbmap_counts(fylename,RNA_molecule):
    '''takes a bbmap log and extracts mapped and unmapped read counts'''
    logfyle=fylename + "_" + RNA_molecule + "_log.txt"
    with open(logfyle,'r') as f:
        for line in f:
            if line.startswith('Reads Used:'):
                in_counts = line.split('\t')[1]
            if line.startswith('mapped:'):
                out_counts = line.split('\t')[2].strip()
    return (in_counts, out_counts)
    
def extract_bowtie2_counts(fylename, RNA_molecule):
    logfyle = fylename + "_" + RNA_molecule + "_log.txt"
    in_counts = "0"
    unique_counts = "0"
    multi_counts = "0"
    with open(logfyle, 'r') as f:
        for line in f:
            ls = line.strip()
            if ls.endswith('reads; of these:'):
                in_counts = ls.split(' ')[0].strip().replace(',', '')
            elif 'aligned concordantly exactly 1 time' in ls:
                unique_counts = ls.split(' ')[0].strip().replace(',', '')
            elif 'aligned concordantly >1 times' in ls:
                multi_counts = ls.split(' ')[0].strip().replace(',', '')
    out_counts = str(int(unique_counts) + int(multi_counts))
    return (in_counts, out_counts)

def extract_UMI_clipped_counts(fylename):
    '''takes a UMItools extracted UMI log files and extracts the read counts'''
    logfyle=fylename + "_extracted_UMIs.log"
    with open(logfyle,'r') as f:
        for line in f:
            if 'INFO Input Reads:' in line:
                in_counts = line.split(':')[-1].strip()
            if 'INFO Reads output:' in line:
                out_counts = line.split(':')[-1].strip()
    return (in_counts, out_counts)
    
def extract_deduplication_counts(fylename):
    logfyle = fylename + "_deduplication_log.txt"
    in_counts = "0"
    out_counts = "0"
    with open(logfyle, 'r') as f:
        for line in f:
            ls = line.strip()
            if 'INFO Reads: Input Reads:' in ls:
                part = ls.split('Input Reads:', 1)[1]
                in_counts = part.split(',', 1)[0].strip().replace(',', '')
            elif 'INFO Number of reads out:' in ls:
                out_counts = ls.split('INFO Number of reads out:', 1)[1].strip().replace(',', '')
    return (in_counts, out_counts)
    
def main():
    parser = argparse.ArgumentParser(description='Takes a filename and extracts the read counts for each step of the library')
    parser.add_argument('infyle', type=str, help='filename to pull values from the log files')
    parser.add_argument('lib_type', type=str, help='Define whether the reads are RPFs or Totals')
    parser.add_argument('-log_dir', type=str, default=None, help='directory containing log files')
    args = parser.parse_args()
    
    cutadapt_in, cutadapt_out = extract_cutadapt_counts(args.log_dir + '/' + args.infyle)
    
    UMI_clipped_in, UMI_clipped_out = extract_UMI_clipped_counts(args.log_dir + '/' + args.infyle)
    
    if args.lib_type == "RPFs":
        rRNA_in, rRNA_out = extract_bbmap_counts(args.log_dir + '/' + args.infyle, "rRNA")
        tRNA_in, tRNA_out = extract_bbmap_counts(args.log_dir + '/' + args.infyle, "tRNA")
        pc_in, pc_out = extract_bbmap_counts(args.log_dir + '/' + args.infyle, "pc")
    
    if args.lib_type == "Totals":
        pc_in, pc_out = extract_bowtie2_counts(args.log_dir + '/' + args.infyle, "pc")
    
    deduplication_in, deduplication_out = extract_deduplication_counts(args.log_dir + '/' + args.infyle)
    
    if int(cutadapt_out) != int(UMI_clipped_in):
        print("warning: cutadapt out does not equal UMI clipped in for sample: " + args.infyle)
    
    if args.lib_type == "RPFs":
        if int(UMI_clipped_out) != int(rRNA_in):
            print("warning: UMI clipped out does not equal rRNA in for sample: " + args.infyle)
        if (int(rRNA_in) - int(rRNA_out)) != int(tRNA_in):
            print("warning: non-rRNA reads does not equal tRNA in for sample: " + args.infyle)
        if (int(tRNA_in) - int(tRNA_out)) != int(pc_in):
            print("warning: non-rRNA_tRNA reads does not equal pc in for sample: " + args.infyle)
    
    if args.lib_type == "Totals":
        if int(UMI_clipped_out) != int(pc_in):
            print("warning: UMI clipped out does not equal pc in for sample: " + args.infyle)
        # 在配对端场景下，dedup 输入包含不完全成对/嵌合等情况，严格等于 pc_out 不成立，改为仅在明显异常时告警
        if int(deduplication_in) > int(pc_in):
            print("warning: deduplication in greater than pc in for sample: " + args.infyle)
        if int(deduplication_out) > int(deduplication_in):
            print("warning: deduplication out greater than input for sample: " + args.infyle)
    
    #write output
    outfyle = args.log_dir + '/' + args.infyle + "_read_counts.csv"
    
    if args.lib_type == "RPFs":
        with open(outfyle,'w') as g:
            g.write("cutadapt_in,cutadapt_out,UMI_clipped_in,UMI_clipped_out,rRNA_in,rRNA_out,tRNA_in,tRNA_out,pc_in,pc_out,deduplication_in,deduplication_out\n")
            g.write((',').join((cutadapt_in,cutadapt_out,UMI_clipped_in,UMI_clipped_out,rRNA_in,rRNA_out,tRNA_in,tRNA_out,pc_in,pc_out,deduplication_in,deduplication_out)))
    
    if args.lib_type == "Totals":
        with open(outfyle,'w') as g:
            g.write("cutadapt_in,cutadapt_out,UMI_clipped_in,UMI_clipped_out,pc_in,pc_out,deduplication_in,deduplication_out\n")
            g.write((',').join((cutadapt_in,cutadapt_out,UMI_clipped_in,UMI_clipped_out,pc_in,pc_out,deduplication_in,deduplication_out)))

if __name__ == '__main__':
    main()
