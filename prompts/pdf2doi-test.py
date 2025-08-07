import pdf2doi 
import pandas as pd 
import os 


lwok_path = os.getcwd()

doi_results = pdf2doi.pdf2doi(lwok_path)
doi_df= pd.DataFrame(doi_results)

doi_df[doi_df.identifier_type != None]


doi_df.loc[:,["identifier","identifier_type","path","method"]].to_csv("pdf2doi-results.csv")
#Same as before 
doi_df.iloc[:,0:4].to_csv("pdf2doi-results.csv")

#After running, use command line to rename files in folder.


#Run this on command line
#pdf2doi -nws -google 2 -s "pdf2doi-results.txt" $(pwd)