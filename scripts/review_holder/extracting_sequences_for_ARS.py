# -*- coding: utf-8 -*-
"""
Created on Thu Apr 23 15:08:27 2020

@author: liusm
"""
from Bio import SeqIO
from Bio.SeqRecord import SeqRecord
from Bio.Seq import Seq
from Bio.Alphabet import IUPAC
import pandas as pd


chromosome_list = []
for seq_record in SeqIO.parse("C:/Users/liusm/Desktop/ARS_and_Gene_Analysis/S288C_reference_sequence.fsa", "fasta"):
    chromosome_list.append(seq_record)
    
str(chromosome_list[0].seq[1000:1100]) 


df = pd.read_excel(r'C:\Users\liusm\Desktop\ARS_and_Gene_Analysis\Origin_Data_Hawkins_2013.xlsx', 'Sheet1')
df.drop(df.filter(regex="Unname"),axis=1, inplace=True)
df = df.drop(df.index[459:476])


df_shape = df.shape
sequences = []
for i in range(0, df_shape[0]):
   
    start = int(df.iloc[i, 1]) - 200
    end = int(df.iloc[i, 1]) + 200
    
    ars_chr = int(df.iloc[i,0])-1
   
    sequences.append(str(chromosome_list[ars_chr].seq[start:end]))
   
    
df['Sequence'] = sequences
print(df['Sequence'][0])
seqs = []
for i in range(0, df_shape[0]):
    
    seq = SeqRecord(Seq(df['Sequence'][i], IUPAC.unambiguous_dna), id = "ARS_" + str(i+1)+ "_"+ str(df.iloc[i, 0]), description = "Sequence")
    seqs.append(seq)
    
    
SeqIO.write(seqs, "ARS_Hawkins.fsa", "fasta")
# rec3 = SeqRecord(
# Seq(
# "MVTVEEFRRAQCAEGPATVMAIGTATPSNCVDQSTYPDYYFRITNSEHKVELKEKFKRMC"
# "EKSMIKKRYMHLTEEILKENPNICAYMAPSLDARQDIVVVEVPKLGKEAAQKAIKEWGQP"
# "KSKITHLVFCTTSGVDMPGCDYQLTKLLGLRPSVKRFMMYQQGCFAGGTVLRMAKDLAEN"
# 66
# "NKGARVLVVCSEITAVTFRGPNDTHLDSLVGQALFGDGAAAVIIGSDPIPEVERPLFELV"
# "SAAQTLLPDSEGAIDGHLREVGLTFHLLKDVPGLISKNIEKSLVEAFQPLGISDWNSLFW"
# "IAHPGGPAILDQVELKLGLKQEKLKATRKVLSNYGNMSSACVLFILDEMRKASAKEGLGT"
# "TGEGLEWGVLFGFGPGLTVETVVLHSVAT",
# generic_protein,
# ),
# id="gi|13925890|gb|AAK49457.1|",
# description="chalcone synthase [Nicotiana tabacum]",
# )
# my_records = [rec1, rec2, rec3]