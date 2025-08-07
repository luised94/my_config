
#Grabs doi records from tab-delimited file outputed by Web of Science.
#Can be used in conjunction with Zotero Magic Wand application to get many papers into Zotero.
#Dois are sent to clipboard. Paste them into Zotero Magic Wand. 
library(tidyverse)

publication_info <- data.frame(read.delim("C:/Users/Luis/Downloads/savedrecs.txt", sep = "\t"))  
colnames(publication_info)
publication_info$TC
rownames(publication_info)
top_DOI <- publication_info %>% filter(DI != "") %>% dplyr::select(TC, DI) %>% arrange(desc(TC)) %>% head() %>% dplyr::select(DI)
bottom_DOI <- publication_info %>% filter(DI != "") %>% dplyr::select(TC, DI) %>% arrange(desc(TC)) %>% filter(TC > 0) %>% tail() %>% dplyr::select(DI)
bind_rows(top_DOI, bottom_DOI)
write.table(bind_rows(top_DOI, bottom_DOI), "clipboard", row.names = F, quote = F, col.names = FALSE)
