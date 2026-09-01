#!/usr/bin/env python

#Imports
#导入依赖包
import re
import argparse
from Bio import SeqIO

#Functions
#函数定义
def read_in_fasta(afasta):
    '''Reads in a fasta file to a dictionary
    读取 fasta 文件并将其保存到字典中。
    '''
    fasta_dict = {}
    fasta_sequences = SeqIO.parse(open(afasta),'fasta')
    for fasta in fasta_sequences:
        fasta_dict[fasta.id] = str(fasta.seq).upper()
    return fasta_dict

def reformat_fasta(fasta_transcripts_in, fasta_translations_in):
    '''Uses transcript and translation fasta dicts to return a five dicts, one for each fasta with just the transcript or protein ID as key, one for region lengths and one for gene and protein IDs
    使用转录本和蛋白翻译 FASTA 字典，生成五个字典：仅以转录本或蛋白 ID 作为键的 FASTA 字典、区域长度字典以及基因/转录本/蛋白 ID 映射。
    '''
        
    fasta_transcripts_out, fasta_translations_out, region_lens, gene_IDs, protein_IDs = {},{},{},{},{}
    
    for k,v in fasta_transcripts_in.items():
        
        #extract transcript/gene IDs
        #提取转录本和基因 ID。
        transcript_ID = k.split('|')[0]
        gene_ID = k.split('|')[1]
        gene_sym = k.split('|')[5]
        
        #extract 5'UTR length
        #提取 5'UTR 长度。
        UTR5_search = re.findall(r"\|\UTR5:\d+\-\d+\|",k)
        if UTR5_search != []:
            UTR5_len = int(UTR5_search[0].strip('|').split('-')[1])
        else:
            UTR5_len = 0
        
        #extract CDS length
        #提取 CDS 长度。
        cds_search = re.findall(r"\|\CDS:\d+\-\d+\|",k)
        cds_range = cds_search[0].split(':')[1].strip('|')
        cds_len = int(cds_range.split('-')[1]) - int(cds_range.split('-')[0]) + 1
        
        #extract 3'UTR length
        #提取 3'UTR 长度。
        UTR3_search = re.findall(r"\|\UTR3:\d+\-\d+\|",k)
        if UTR3_search != []:
            UTR3_range = UTR3_search[0].split(':')[1].strip('|')
            UTR3_len = int(UTR3_range.split('-')[1]) - int(UTR3_range.split('-')[0]) + 1
        else:
            UTR3_len = 0
        
        total_length = int(re.findall(r"\|\d+\|",k)[0].strip('|'))
        if total_length == UTR5_len + cds_len + UTR3_len: #sanity check that nothing has gone wrong
            #简单校验总长度是否等于三段长度之和，防止出错。
            #save sequence to fasta dict
            #将序列保存到转录本 FASTA 字典中。
            fasta_transcripts_out[transcript_ID] = v
            #save region lengths and gene/transcript IDs to dicts
            #将区域长度和基因/转录本 ID 保存到对应字典。
            region_lens[transcript_ID] = (str(UTR5_len), str(cds_len), str(UTR3_len))
            gene_IDs[transcript_ID] = [gene_ID, gene_sym]
    
    #extract protein IDs
    #提取蛋白 ID 并建立蛋白与转录本/基因的对应关系。
    for k,v in fasta_translations_in.items():
        protein_ID = k.split('|')[0]
        transcript_ID = k.split('|')[1]
        protein_IDs[protein_ID] = [transcript_ID] + gene_IDs[transcript_ID]
        
        #save sequence to fasta dict
        #将蛋白氨基酸序列保存到蛋白 FASTA 字典中。
        fasta_translations_out[protein_ID] = v
                                    
    return (fasta_transcripts_out, fasta_translations_out, region_lens, gene_IDs, protein_IDs)
    
def write_fasta(adict, outfyle, LW=80):
    '''takes a fasta dictionary and writes a fasta
    将 FASTA 字典写出为 fasta 文件。
    '''
    with open(outfyle, 'w') as g:
        for k,v in adict.items():
            g.write('>' + k + '\n')
            for i in range(0, len(v), LW):
                g.write(v[i:i+LW] + '\n')

def write_csv(adict, outfyle):
    '''takes a dict and writes to csv
    将普通字典写出为 csv 文件。
    '''
    with open(outfyle, 'w') as g:
        for k,v in adict.items():
            g.write(k + ',' + ','.join(v) + '\n')
    
#Main Function
def main():
    parser = argparse.ArgumentParser(description='Takes a GENCODE FASTA file containing transcript sequences and a \
    GENCODE FASTA file containing amino acid sequences and reformats them so that the header line is just the transcript or protein ID \
    and exporting the UTR and CDS region lengths and gene/transcript/protein IDs to seperate csv files')
    parser.add_argument('FASTA_transcripts', type=str, help='GENCODE FASTA file containing transcript sequences')
    parser.add_argument('FASTA_translations', type=str, help='GENCODE FASTA file containing amino acid sequences')
    args = parser.parse_args()
    
    #read in FASTA
    #读取 FASTA 文件。
    original_fasta_transcripts = read_in_fasta(args.FASTA_transcripts)
    original_fasta_translations = read_in_fasta(args.FASTA_translations)
    
    #reformat FASTAs
    #重新格式化 FASTA 序列和相关信息。
    final_fasta_transcripts, final_fasta_translations, region_lens, gene_IDs, protein_IDs = reformat_fasta(original_fasta_transcripts, original_fasta_translations)
    
    #write FASTAs
    #写出重新格式化后的 FASTA 文件。
    fasta_fylename = args.FASTA_transcripts.replace('.fa', '_reformatted.fa')
    write_fasta(final_fasta_transcripts, fasta_fylename)
    
    fasta_fylename = args.FASTA_translations.replace('.fa', '_reformatted.fa')
    write_fasta(final_fasta_translations, fasta_fylename)
    
    #write CSVs
    #写出区域长度和 ID 映射的 CSV 文件。
    write_csv(region_lens, args.FASTA_transcripts.replace('.fa', '_region_lengths.csv'))
    write_csv(gene_IDs, args.FASTA_transcripts.replace('.fa', '_gene_IDs.csv'))
    write_csv(protein_IDs, args.FASTA_transcripts.replace('.fa', '_protein_IDs.csv'))

if __name__ == '__main__': 
    main()
 
