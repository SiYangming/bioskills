#!/usr/bin/env python3
import sys

def process_stream(stdin, stdout):
    for line in stdin:
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 12:
            if not parts[10].endswith(","):
                parts[10] = parts[10] + ","
            if not parts[11].endswith(","):
                parts[11] = parts[11] + ","
        stdout.write("\t".join(parts) + "\n")

if __name__ == "__main__":
    process_stream(sys.stdin, sys.stdout)
