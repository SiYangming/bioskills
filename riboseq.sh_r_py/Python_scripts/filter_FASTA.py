#!/usr/bin/env python

#Imports
#导入依赖包
import argparse
from Bio import SeqIO

#Functions
#函数定义
def read_in_fasta(afasta):
    '''Reads in a fasta file to a dictionary
    读取 fasta 文件并保存为字典。
    '''
    fasta_dict = {}
    fasta_sequences = SeqIO.parse(open(afasta),'fasta')
    for fasta in fasta_sequences:
        fasta_dict[fasta.id] = str(fasta.seq).upper()
    return fasta_dict

def read_in_IDs(infyle):
    '''reads in transcript IDs and returns it as a dictionary
    读取转录本 ID 列表并保存为字典。
    '''
    adict = {}
    with open(infyle, 'r') as f:
        for line in f:
            transcript = line.strip()
            adict[transcript] = None
    return adict
    
        
def write_filtered_fasta(afasta, adict, outfyle, LW=80):
    '''takes a fasta dictionary and a list of IDs and writes fasta for all IDs in the list
    根据给定 ID 列表过滤 FASTA 序列并写出新 fasta 文件。
    '''
    with open(outfyle, 'w') as g:
        for k,v in afasta.items():
            transcript = k.strip('>')
            if transcript in adict:
                g.write('>' + k + '\n')
                for i in range(0, len(v), LW):
                    g.write(v[i:i+LW] + '\n')
                    

def main():
    parser = argparse.ArgumentParser(description='Takes a fasta file and filters to inculde only those transcripts in supplied transcript IDs file')
    parser.add_argument('FASTA', type=str, help='GENCODE FASTA file')
    parser.add_argument('IDs', type=str, help='transcript IDs file')
    parser.add_argument('out_file', type=str, help='Set the name of the output file')
    args = parser.parse_args()
    
    input_dict = read_in_fasta(args.FASTA)
    most_abundant_transcripts = read_in_IDs(args.IDs)
    write_filtered_fasta(input_dict, most_abundant_transcripts, args.out_file)
    
if __name__ == '__main__':
    main()
