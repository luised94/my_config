name: [Item] Recall after reading
comment: This template may be too long. Not sure.
content: |-
// @use-markdown
// @author Claude,luised94,justin_skycak_inspired
${{
// ===== GRAB ALL THE DATA UPFRONT =====
const item = topItem;
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

## Metadata
- **First Author:** ${sharedObj.biblio.firstAuthor}
- **Date:** ${sharedObj.biblio.date}
- **Citation Key:** ${sharedObj.biblio.bibtexKey}
- **Tags:** ${sharedObj.biblio.tagList}
- **Notes:** ${sharedObj.biblio.numberOfNotes}
- **PDF:** ${sharedObj.biblio.hasPDF ? `[Open PDF](${sharedObj.biblio.pdfLink})` : "No PDF"}

---

## Pre-Reading Phase

### Initial Predictions
*Before reading, based on title/abstract/skimming:*
- What do I expect this paper to argue?
- What questions do I think it will answer?
- How might this relate to what I already know?

### Prior Knowledge Activation
- What do I already know about this topic?
- What related papers/concepts come to mind?
- What gaps in my understanding might this fill?

---

## Active Reading Phase

### Key Claims & Evidence
*For each major claim, note:*

**Claim 1:**
- Evidence provided:
- Strength of evidence (1-5):
- My assessment:

**Claim 2:**
- Evidence provided:
- Strength of evidence (1-5):
- My assessment:

### Questions Generated While Reading
- [ ] Question 1:
- [ ] Question 2:
- [ ] Question 3:

### Confusion Points
*What didn't make sense? What needs clarification?*
-
-
-

---

## Post-Reading Processing

### Free Recall Test
*Without looking back, what are the main points I remember?*

### Accuracy Check
*After free recall, check against the paper. What did I miss or misremember?*
- Missed:
- Misremembered:

### The Big Picture
- **Main contribution:**
- **Why does this matter?**
- **What's the "so what" factor?**

### Critical Analysis
- **Strengths:**
- **Weaknesses/Limitations:**
- **What would I do differently?**
- **What questions remain unanswered?**

---

## Knowledge Integration

### Connections to Prior Knowledge
- **Confirms what I already knew:**
- **Contradicts what I thought:**
- **Extends my understanding by:**

### Related Work Links
*Link to other papers/concepts in my collection:*
*Use @citationkey to link*

### Implications for My Work
- **How might I apply this?**
- **What new research directions does this suggest?**
- **What should I read next?**

---

## Spaced Repetition Cues

### Key Concepts to Remember
1.
2.
3.

### Review Schedule
- [ ] Review in 1 day
- [ ] Review in 3 days
- [ ] Review in 1 week
- [ ] Review in 2 weeks

---

## Session Metadata
- **Date:**
- **Reading Time:**
- **Comprehension (1-5):**
- **Effort Required (1-5):**
- **Interest Level (1-5):**
- **Distractions:**
