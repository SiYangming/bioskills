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

def extract_HAVANA_IDs(GTFfyle):
    '''Reads a gtf file line by line. Extracts the transcript ID from each feature line if transcript is annotated by HAVANA as being protein coding
    按行读取 GTF 文件，如果转录本由 HAVANA 注释为蛋白编码，则提取其转录本 ID。
    '''
    HAVANA_IDs_dict = {}
    with open(GTFfyle,'r') as f:
        for line in f:
            if line.startswith('#'):
                pass
            else:
                source = line.split('\t')[1]
                if source == "HAVANA":
                    attribute = line.split('\t')[8]
                    pc_transcript = re.findall(r'transcript_type\ \"protein_coding\"', attribute)
                    if pc_transcript != []:
                        transcript = re.findall(r'\"E\w+T\d+\.\d+\"', attribute)
                        if transcript != []:
                            transcriptID = transcript[0].strip('"')
                            if transcriptID in HAVANA_IDs_dict:
                                pass
                            else:
                                HAVANA_IDs_dict[transcriptID] = None
    return HAVANA_IDs_dict

def read_region_lengths(csv_fyle):
    '''reads in region lengths csv file and saves as a dictionary
    读取区域长度信息的 CSV 文件，并保存为字典。
    '''
    adict = {}
    with open(csv_fyle, 'r') as f:
        for line in f:
            ENST = line.strip().split(',')[0]
            UTR5_len = line.strip().split(',')[1]
            cds_len = line.strip().split(',')[2]
            UTR3_len = line.strip().split(',')[3]
            adict[ENST] = (int(UTR5_len), int(cds_len), int(UTR3_len))
    return adict

def filter_fasta(fasta_dict, HAVANA_IDs, region_lens):
    '''filters fasta
    根据 HAVANA 注释和区域长度信息过滤 FASTA 序列。
    '''
        
    filtered_dict = {}
    
    for transcript,seq in fasta_dict.items():
        if transcript[-5:] != 'PAR_Y': #removes any PAR_Y transcripts
            #移除所有 PAR_Y 转录本。
            if transcript in HAVANA_IDs: #Ensures the transcript has been manually annotated by HAVANA
                
                
                UTR5_len = int(region_lens[transcript][0])
                CDS_len = int(region_lens[transcript][1])
                UTR3_len = int(region_lens[transcript][2])
                
                if UTR5_len > 0 and UTR3_len > 0: #ensures the transcript has both a 5' and 3'UTR
                    #确保转录本同时具有 5'UTR 和 3'UTR。
                    if CDS_len % 3 == 0: #ensures the CDS is equally divisible by 3
                        cds_seq = seq[UTR5_len:-UTR3_len]
                        start_codon = cds_seq[:3]
                        stop_codon = cds_seq[-3:]
                        if start_codon == "ATG" or start_codon == "CTG" or start_codon == "TTG" or start_codon == "GTG": #ensures the CDS starts with an nUG start codon
                            #确保 CDS 以 nUG 起始密码子开始。
                            if stop_codon == "TAA" or stop_codon == "TGA" or stop_codon == "TAG": #ensures the CDS ends with a stop codon
                                #确保 CDS 以终止密码子结束。
                                filtered_dict[transcript] = seq
    return (filtered_dict)

def write_fasta(adict, outfyle, LW=80):
    '''takes a fasta dict and writes fasta'''
    with open(outfyle, 'w') as g:
        for k,v in adict.items():
            g.write('>' + k + '\n')
            for i in range(0, len(v), LW):
                g.write(v[i:i+LW] + '\n')

#Main Function
def main():
    parser = argparse.ArgumentParser(description='Takes a fasta file, a GTF file and a region lengths file and filters FASTA to include only those transcripts\
    that have been manually annotated by HAVANA, that have both a 5\' and 3\'UTR and whose CDS is equally divisible by 3 and starts with an ATG and ends with a stop codon')
    parser.add_argument('FASTA', type=str, help='GENCODE FASTA file')
    parser.add_argument('GTF', type=str, help='GENCODE GTF file')
    parser.add_argument('region_lengths_fyle', type=str, help='region lengths file. Needs to be csv file in the following format; Transcript ID,5\'UTR length,CDS length,3\'UTR length')
    args = parser.parse_args()
    
    #read in FASTA
    #读取 FASTA 文件。
    original_fasta = read_in_fasta(args.FASTA)
    
    #extract HAVANA protein coding transcripts IDs
    #提取 HAVANA 注释的蛋白编码转录本 ID。
    HAVANA_IDs = extract_HAVANA_IDs(args.GTF)
    
    #read in the region lengths
    #读取区域长度文件。
    region_lengths = read_region_lengths(args.region_lengths_fyle)
    
    #filter FASTA
    #过滤 FASTA 序列。
    filtered_dict = filter_fasta(original_fasta, HAVANA_IDs, region_lengths)
    
    #write FASTA
    #写出过滤后的 FASTA 文件。
    fasta_fylename = args.FASTA.replace('_reformatted', '_filtered')
    write_fasta(filtered_dict, fasta_fylename)

if __name__ == '__main__': 
    main()
 
