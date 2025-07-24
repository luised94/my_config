name: [Item] Recall after reading
content: |-
// @use-markdown
// @author Claude,luised94
// <!-- VARIABLE DEFINITIONS -->
${{
// ===== GRAB ALL THE DATA UPFRONT =====
const item = topItem;
// To debug:
// Open debug output. 
// Use Zotero.debug() to inspect values in script.

// Basic bibliographic info
const title = item.getField("title") || "Untitled";
const date = item.getField("date") || "No date";
const url = item.getField("url") || "";
const abstract = item.getField("abstractNote") || "No abstract available";
const doi = item.getField("DOI") || "";
const bibtexKey = item.getField("citationKey") || "";
const notes = item.getNotes() || "";
const numberOfNotes = notes.length;

// Process creators (authors)
const creators = item.getCreators();
const authorList = creators.length > 0 
 ? creators.map(c => `${c.firstName} ${c.lastName}`).join(", ")
 : "No authors listed";
const firstAuthor = creators.length > 0 
 ? creators[0].lastName 
 : "Unknown";

// Process tags
const tags = item.getTags();
const tagList = tags.length > 0 
 ? tags.map(t => `#${t.tag}`).join(" ")
 : "No tags";
const hasImportantTag = tags.some(t => t.tag.toLowerCase().includes("important"));

// Get attachments and PDF info
const attachments = item.getAttachments();
const pdfAttachment = attachments.find(id => {
 const att = Zotero.Items.get(id);
 return att.isPDFAttachment();
});
const hasPDF = !!pdfAttachment;
const pdfLink = hasPDF ? `zotero://open/library/items/${Zotero.Items.get(pdfAttachment).key}` : "";

// Store everything in sharedObj for use throughout template
sharedObj.biblio = {
 title, date, url, abstract, doi,
 authorList, firstAuthor,
 tagList, hasImportantTag,
 hasPDF, pdfLink,
 bibtexKey, numberOfNotes
};

return ""; // Don't output anything here
}}$

# ${sharedObj.biblio.title}
## General Information
CitationKey: ${sharedObj.biblio.bibtexKey}
Number of notes: ${sharedObj.biblio.numberOfNotes}

## Free recall

## Assesment
Comprehension Rating (1-5):

Distractions:

## Notes

## Connections
