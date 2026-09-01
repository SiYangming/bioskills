#!/usr/bin/env python

'''
Extracts a single transcript from a <.counts> and a <.fasta> file, reformats it into an easy to read <.csv>
从 <.counts> 和 <.fasta> 文件中提取单个转录本，并重新格式化为易读的 <.csv>。
'''

#Imports
#导入依赖包
import argparse
import os
from Ribosome_profiling_functions import read_counts
from Ribosome_profiling_functions import read_in_fasta

#Functions
#函数定义
def write_out_csv(sequence,values,outfile='stats.csv'):
    '''Writes out the data
    将单个转录本的碱基和计数信息写出到 CSV。
    '''
    with open(outfile,'w') as g:
        g.write(','.join(['Position','Nucleotide','Counts'])+'\n')
        lines = zip(range(1,len(sequence)+1),sequence,values)
        for line in lines:
            g.write(','.join([str(x) for x in line])+'\n')


def batch_write_out_csv(sequence_dict,values_dict,name_suffix):
    '''batch writes a lot of csv
    批量将多个转录本写出为各自的 CSV 文件。
    '''
    q_keys = set(sequence_dict.keys()).intersection(set(values_dict.keys()))
    for key in q_keys:
        new_fyle = '_'.join([key,name_suffix])+'.csv'
        sequence, values = sequence_dict[key],values_dict[key]
        if len(sequence) == len(values):
            with open(new_fyle,'w') as g:
                g.write(','.join(['Position','Nucleotide','Counts'])+'\n')
                lines = zip(range(1,len(sequence)+1),sequence,values)
                for line in lines:
                    g.write(','.join([str(x) for x in line])+'\n')

def write_out_one_csv(counts_dict, sequences, out_name):
    '''batch writes a lot of csv
    将所有转录本合并写入同一个 CSV 文件。
    '''
    with open(out_name,'w') as g:
        g.write(','.join(['transcript', 'Position', 'Nucleotide', 'Counts'])+'\n')
        for transcript in counts_dict.keys():
            counts, sequence = counts_dict[transcript], sequences[transcript]
            if len(counts) == len(sequence):
                lines = zip([transcript] * len(counts), range(1,len(counts)+1), sequence, counts)
                for line in lines:
                    g.write(','.join([str(x) for x in line])+'\n')

def main():
    parser = argparse.ArgumentParser(description='Reformats <.counts> file to <.csv> file')
    parser.add_argument('counts_fyle',type=str,help='<.counts> file to pull values from')
    parser.add_argument('fasta',type=str,help='<.fasta> file used to generate the <.counts>')
    parser.add_argument('-transcript',default=None,type=str,help='Specific transcript to reformat')
    parser.add_argument('-all_transcripts',action='store_true',help='Reformat all, output to new directory')
    parser.add_argument('-one_csv',action='store_true',help='Reformat all, output to one csv file')
    parser.add_argument('-in_dir', type=str, default=None, help='Change the input folder, default is current directory')
    parser.add_argument('-out_dir', type=str, default=None, help='Change the output folder, default is current directory')
    args = parser.parse_args()
    
    #Read in files to query
    #读取待查询的输入文件。
    #Read in the counts file
    #读取计数文件。
    if args.in_dir == None:
        counts_dict = read_counts(args.counts_fyle)
    else:
        counts_dict = read_counts(args.in_dir + '/' + args.counts_fyle)
    
    #read in fasta sequences
    #读取 fasta 序列。
    sequences = read_in_fasta(args.fasta)
    
    if args.transcript and not args.all_transcripts and not args.one_csv:
        #Check Values
        #检查指定转录本在序列和计数字典中是否都存在。
        seq = sequences[args.transcript] if args.transcript in sequences else None
        counts = counts_dict[args.transcript] if args.transcript in counts_dict else None
        
        #Auto-generate name
        #自动生成输出文件名。
        if args.out_dir == None:
            outname= '_'.join([args.transcript,args.counts_fyle.replace('.counts','.csv')])
        else:
            outname= args.out_dir + '/' + '_'.join([args.transcript,args.counts_fyle.replace('.counts','.csv')])
            
        #Write
        #写出单个转录本的 CSV 文件。
        if seq != None and counts !=None:
            if len(seq) == len(counts):
                write_out_csv(seq,counts,outname)
            else:
                print('Sequence length does not match number of counts for {}'.format(args.transcript))
        else:
            print('One or more of the files did not contain entry {}'.format(args.transcript))
    
    elif args.all_transcripts and not args.transcript and not args.one_csv:
        #Directory
        #创建输出目录以保存所有转录本的 CSV 文件。
        if args.out_dir == None:
            new_dir = args.counts_fyle.replace('.counts','_all_csvs')
        else:
            new_dir = args.out_dir + '/' + args.counts_fyle.replace('.counts','_all_csvs')
        
        check= os.listdir('.')
        if new_dir not in check:
            os.mkdir(new_dir)
            os.chdir(new_dir)
            batch_write_out_csv(sequences,counts_dict,args.counts_fyle.replace('.counts',''))
            os.chdir('..')
        else:
            print('{} folder already exists. Remove or rename and try again.'.format(new_dir))
    
    elif args.one_csv and not args.transcript and not args.all_transcripts:
        #create out filename
        #创建合并输出的 CSV 文件名。
        if args.out_dir == None:
            out_name = args.counts_fyle.replace('.counts','_counts.csv')
        else:
            out_name = args.out_dir + '/' + args.counts_fyle.replace('.counts','_counts.csv')
        
        #write csv
        #将所有转录本写入同一个 CSV 文件。
        write_out_one_csv(counts_dict, sequences, out_name)
    
    
    else:
        print('Check options, use only one of -all_transcripts,  -transcript, -one_csv')

if __name__ == '__main__':
    main()
