#!/usr/bin/env python

#Imports
#导入依赖包
import argparse
from Ribosome_profiling_functions import read_counts
from Ribosome_profiling_functions import read_region_lengths

#Functions
#函数定义
def sum_UTR5_counts(in_dict, region_lengths_dict, outfyle):
    '''takes a counts dict and sums all the counts within each region
    对每个转录本 5'UTR 区域内的计数求和。
    '''
    summed_UTR5_counts = {}
    
    for k, v in in_dict.items():
        UTR5_len = region_lengths_dict[k][0]
        UTR5_counts = v[:UTR5_len]
        summed_UTR5_counts[k] = sum(map(int,UTR5_counts))
        
    with open(outfyle, 'w') as g:
        g.write('transcript,UTR5_counts\n')
        for k,v in summed_UTR5_counts.items():
            g.write(k + "," + str(v) + '\n')

def main():
    parser = argparse.ArgumentParser(description='Takes a RPF counts file and sums all counts in the 5\'UTR')
    parser.add_argument('infyle', type=str, help='counts file to pull values from')
    parser.add_argument('region_lengths_fyle', type=str, help='region lengths file. Needs to be csv file in the following format; Transcript ID,5\'UTR length,CDS length,3\'UTR length')
    parser.add_argument('-in_dir', type=str, default=None, help='Change the input folder, default is current directory')
    parser.add_argument('-out_dir', type=str, default=None, help='Change the output folder, default is current directory')
    args = parser.parse_args()
    
    #Read in the counts file
    #读取计数文件。
    if args.in_dir == None:
        input_counts = read_counts(args.infyle)
    else:
        input_counts = read_counts(args.in_dir + '/' + args.infyle)
    
    #read in the region lengths
    #读取区域长度文件。
    region_lengths = read_region_lengths(args.region_lengths_fyle)
    
    #generate output filename
    #生成输出文件名。
    if args.out_dir == None:
        fylename = args.infyle.replace('.counts', '_UTR5_counts.csv')
    else:
        fylename = args.out_dir + '/' + args.infyle.replace('.counts', '_UTR5_counts.csv')
    
    #write summed counts for each region to file
    #将每个转录本的 5'UTR 计数和写入文件。
    sum_UTR5_counts(input_counts, region_lengths, fylename)

if __name__ == '__main__':
    main()
