import gzip
import re
import sys
import os
import argparse

def open_file(path, mode):
    if path.endswith('.gz'):
        return gzip.open(path, mode)
    else:
        return open(path, mode)

def extract_transcripts(gtf_path, fasta_path, output_path, chrom):
    print(f"Extracting records for chromosome {chrom}...")
    print(f"GTF: {gtf_path}")
    print(f"Input FASTA: {fasta_path}")
    print(f"Output FASTA: {output_path}")
    
    # 1. Get transcript IDs from GTF
    transcript_ids = set()
    # Pattern for transcript_id and version
    # transcript_id "ENST00000415932"; transcript_version "1";
    
    try:
        with open(gtf_path, 'r') as f:
            for line in f:
                if line.startswith('#'): continue
                parts = line.split('\t')
                if len(parts) < 9: continue
                
                # Check chromosome match
                if parts[0] == chrom or parts[0] == f"chr{chrom}":
                    # Extract ID and version
                    tid_match = re.search(r'transcript_id "([^"]+)"', parts[8])
                    ver_match = re.search(r'transcript_version "([^"]+)"', parts[8])
                    
                    if tid_match:
                        tid = tid_match.group(1)
                        if ver_match:
                            tid = f"{tid}.{ver_match.group(1)}"
                        transcript_ids.add(tid)
    except FileNotFoundError:
        print(f"Error: GTF file not found at {gtf_path}")
        sys.exit(1)

    print(f"Found {len(transcript_ids)} transcripts for chromosome {chrom} in GTF.")
    
    if not os.path.exists(fasta_path):
        print(f"Error: FASTA file not found at {fasta_path}")
        sys.exit(1)

    # 2. Filter FASTA
    count = 0
    try:
        # Use 'rt' for read text mode for gzip, 'r' for normal file
        mode_in = 'rt' if fasta_path.endswith('.gz') else 'r'
        # Use 'wt' for write text mode for gzip, 'w' for normal file
        mode_out = 'wt' if output_path.endswith('.gz') else 'w'
        
        with open_file(fasta_path, mode_in) as f_in, open_file(output_path, mode_out) as f_out:
            write_record = False
            for line in f_in:
                if line.startswith('>'):
                    # Check if any field in the header matches a known transcript ID
                    # Header format: >ID1|ID2|ID3...
                    header_parts = line[1:].strip().split('|')
                    
                    # We check if any part of the header matches a transcript ID from our set
                    # This covers both transcript files (ID is 1st) and translation files (ID is 2nd)
                    # We also handle versioning: checking if "ID.Version" is in set, or just "ID"
                    
                    match_found = False
                    for part in header_parts:
                        # part might be "ENST00000641515.2" or "ENST00000641515"
                        if part in transcript_ids:
                            match_found = True
                            break
                        # Also check without version if the set has it? 
                        # Our set has versions if GTF has them. 
                        # Usually FASTA headers match GTF IDs.
                    
                    if match_found:
                        write_record = True
                        count += 1
                        f_out.write(line)
                    else:
                        write_record = False
                elif write_record:
                    f_out.write(line)
    except Exception as e:
        print(f"Error processing FASTA: {e}")
        sys.exit(1)
                
    print(f"Extracted {count} records to {output_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Extract FASTA records matching transcripts in GTF for a specific chromosome.')
    parser.add_argument('--gtf', required=True, help='Path to GTF file')
    parser.add_argument('--fasta', required=True, help='Path to input FASTA file (can be .gz)')
    parser.add_argument('--output', required=True, help='Path to output FASTA file')
    parser.add_argument('--chrom', default="20", help='Chromosome to extract (default: 20)')
    
    args = parser.parse_args()
    
    extract_transcripts(args.gtf, args.fasta, args.output, args.chrom)
