// @use-markdown
// @author Claude,luised94,justin_skycak_inspired
${{
// ===== GRAB ALL THE DATA UPFRONT =====
const item = topItem;
const title = item.getField("title") || "Untitled";
const date = item.getField("date") || "No date";
const url = item.getField("url") || "";
const abstract = item.getField("abstractNote") || "No abstract available";
const doi = item.getField("DOI") || "";
const bibtexKey = item.getField("citationKey") || "";
const notes = item.getNotes() || "";
const numberOfNotes = notes.length;

const creators = item.getCreators();
const authorList = creators.length > 0
 ? creators.map(c => `${c.firstName} ${c.lastName}`).join(", ")
 : "No authors listed";

const tags = item.getTags();
const tagList = tags.length > 0
 ? tags.map(t => `#${t.tag}`).join(" ")
 : "No tags";

const attachments = item.getAttachments();
const pdfAttachment = attachments.find(id => {
 const att = Zotero.Items.get(id);
 return att.isPDFAttachment();
});
const hasPDF = !!pdfAttachment;
const pdfLink = hasPDF ? `zotero://open/library/items/${Zotero.Items.get(pdfAttachment).key}` : "";

sharedObj.biblio = {
 title, date, url, abstract, doi,
 authorList, tagList, hasPDF, pdfLink, bibtexKey, numberOfNotes
};
return "";
}}$

# ${sharedObj.biblio.title}

## Metadata
- Authors: ${sharedObj.biblio.authorList}
- Date: ${sharedObj.biblio.date}
- Citation Key: ${sharedObj.biblio.bibtexKey}
- Tags: ${sharedObj.biblio.tagList}
- PDF: ${sharedObj.biblio.hasPDF ? "Available" : "None"}
- Notes: ${sharedObj.biblio.numberOfNotes}

---

## Pre-Reading Predictions
What do I expect this to argue?

What questions might it answer?

How does this relate to what I know?

What do I already know about this topic?

What related papers/concepts come to mind?

What gaps in my understanding might this fill?

---

## Active Reading

### Key Claims
1.
2.
3.

### Questions While Reading
-
-
-

### Confusion Points
-
-

---

## Post-Reading

### Free Recall Test
Without looking back, what were the main points?

### Main Contribution
What's the big idea?

### Critical Assessment
Strengths:

Weaknesses:

---

## Connections

### Related Papers
- @citationkey1 - relationship
- @citationkey2 - relationship

### Implications for My Work
How might I use this?

What should I read next?

---

## Review Cues
Key concepts to remember:

1.

2.

3.

## Session Metadata
- **Date:**
- **Reading Time:**
- **Comprehension (1-5):**
- **Effort Required (1-5):**
- **Interest Level (1-5):**
- **Distractions:**

Review dates: [ ] +1d [ ] +3d [ ] +1w [ ] +2w
