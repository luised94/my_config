# -*- coding: utf-8 -*-
"""
Created on Sun Apr 19 23:07:26 2020

@author: liusm
"""


from datetime import date
from intermine.webservice import Service
import pandas as pd

service = Service("https://yeastmine.yeastgenome.org/yeastmine/service", username = "", password = "")
lm=service.list_manager()

def query_to_csv(query, listTypes, type_of_ARS_List, views, headers):
    if len(query.rows()) > 0:
            #Create and open file to write query to csv
            today = str(date.today())
            filename = listTypes[i] + "_" + type_of_ARS_List[j] +'_info_' + today +'.csv'
            f = open(filename, 'w')

            #Create header string with column names. Has to be changed depending on columns and prefered names for them
            headerString = headers
            f.write(headerString)
    
            #Writing out the row data as csv. For every row, add the data as strings with comma (,) at end unless
            #it is last element, in which case add new line to be able to add other row data below. Write to file. 
            for row in query.rows():
                count = 1
                row_string = ''
                for view in views:
                    string_holder = str(row[view]).replace(',', '_' ) #string holder to be able to modify twice, replace , with _ to write to csv
                    if count == len(views_list):
                        row_string += string_holder.replace('\n', '') + '\n'  #replace all new line characters in output of rows, particularly phenotype summary 
                    else:
                        row_string += string_holder.replace('\n', '') + ','
                        count += 1
                f.write(row_string)
        
            f.close()
    else:
        print("No genes in " + list_type[i] + "_" + type_of_ARS_list[j])
        
def query_to_fasta(query, listTypes, type_of_ARS_List, view_for_fasta_heading, short_description, view_for_fasta_content):
    today = str(date.today())
    filename = list_type[i] + "_" + type_of_ARS_list[j] +'_info_' + today +'.fasta'
    f = open(filename, 'w')
    fasta_heading = view_for_fasta_heading
    Description = short_description
    fasta_content  = view_for_fasta_content
    

    for row in query.rows():
        row_string = '>'
        for view in fasta_heading:
            row_string += row[view] + " "        
            f.write(row_string + Description)
    
        sequence_to_write = row[fasta_content]
    
        index_to_add_new_line = [x for x in range(len(sequence_to_write)+1) if x % 40 == 0]
    
        for index in index_to_add_new_line:
            sequence_to_write = sequence_to_write[:index] + '\n' + sequence_to_write[index:]
        
        f.write(sequence_to_write + "\n")

    f.close()



#Import Excel file from analysis of genes done in R ARF and ORF analysis
df = pd.read_excel(r'C:\Users\liusm\Desktop\ARS and Gene Analysis\ARS_transcription_overlap.xlsx')
df.drop(df.filter(regex="Unname"),axis=1, inplace=True)
header_list = list(df.columns.values) #extract column names as list
type_of_ARS_list = list(df['Type_of_ARS'].values) # extract ARS type as list
list_type = header_list[2:] #extract header that you would like to interate through

#For headers of interest, split the string at ', ' to create list for genes 
for i in range(2,5): 
    for j in range(0,6):
        df[header_list[i]][j] = df[header_list[i]][j].split(', ') 

#Create list for each ARS type for the respective ARS in the list
for i in range(0,6):
    lm.create_list(content=df['ARS_List'][i],list_type="ARS",name="ARS_List_"+type_of_ARS_list[i])
    #Create list for each ARS type for the respective gene in the list
for i in range(3,5):
    for j in range(0,6):
        lm.create_list(content=df[header_list[i]][j],list_type="Gene",name=header_list[i]+"_"+type_of_ARS_list[j])
        
#List of views to extract     
views_list = ["secondaryIdentifier", "symbol", "name", "phenotypeSummary",
    "upstreamIntergenicRegion.sequence.length",
    "upstreamIntergenicRegion.sequence.residues",
    "downstreamIntergenicRegion.sequence.length",
    "downstreamIntergenicRegion.sequence.residues"]  
#Header Names
header_string = 'SystematicName,StandardName,Name,Phenotype,Upstream_Length,Upstream_Seq,Downstream_Length,Downstream_Seq\n'     

#For each list  extract the views in views list and print to csv
for i in range(1,3):  
   for j in range(0,6):
        query = service.new_query("Gene")

        query.add_view("secondaryIdentifier", "symbol", "name", "phenotypeSummary",
                       "upstreamIntergenicRegion.sequence.length",
                       "upstreamIntergenicRegion.sequence.residues",
                       "downstreamIntergenicRegion.sequence.length",
                       "downstreamIntergenicRegion.sequence.residues"    
                       )

        query.add_constraint("Gene", "IN", list_type[i] +"_"+ type_of_ARS_list[j], code = "A")
        query_to_csv(query, list_type, type_of_ARS_list,views_list,header_string)
        
#Example writing to fasta
        
# today = str(date.today())
# filename = list_type[1] + "_" + type_of_ARS_list[3] +'_info_' + today +'.fasta'
# f = open(filename, 'w')
# view_for_fasta_heading = ["secondaryIdentifier", "name"]
# view_for_fasta_content  = "upstreamIntergenicRegion.sequence.residues"
# short_Description = "Upstream Intergenic Sequence"

# for row in query.rows():
#     row_string = '>'
#     for view in view_for_fasta_heading:
#         row_string += row[view] + " "        
#     f.write(row_string + short_Description)
    
#     sequence_to_write = row[view_for_fasta_content]
    
#     index_to_add_new_line = [x for x in range(len(sequence_to_write)+1) if x % 40 == 0]
    
#     for index in index_to_add_new_line:
#         sequence_to_write = sequence_to_write[:index] + '\n' + sequence_to_write[index:]
        
#     f.write(sequence_to_write + "\n")

# f.close()
# df["gene_name"] = 'LOOK UP'
# df["gene_name2"] = 'LOOK UP'
# df["gene_name3"] = 'LOOK UP'
# print(df.head())

# for index, row in df.iterrows():
#         service = Service("https://yeastmine.yeastgenome.org/yeastmine/service")
#         query = service.new_query("Gene")
#         query.add_view(
#             "chromosome.primaryIdentifier", "primaryIdentifier", "secondaryIdentifier",
#             "featureType", "symbol", "name", "sgdAlias", "organism.shortName",
#             "qualifier", "chromosomeLocation.start", "chromosomeLocation.end",
#             "chromosomeLocation.strand", "description"
#         )
#         query.add_sort_order("Gene.primaryIdentifier", "ASC")
#         query.add_constraint("chromosome.primaryIdentifier", "=", row['chromosome'])
#         query.add_constraint("chromosomeLocation.start", "<=", str(row['base_nr']))
#         query.add_constraint("chromosomeLocation.end", ">", str(row['base_nr']))

#         for gene in query.rows():
#             # row['gene_name'] = gene['sgdAlias']
#             df.loc[index,'gene_name'] = gene['sgdAlias']
#             df.loc[index,'gene_name2'] = gene['name']
#             df.loc[index,'gene_name3'] = gene['symbol']
#             print(gene['sgdAlias'])

# df.to_csv('genes_fetch_'+str(confidence_value)+'.csv')
# print(df.tail())
