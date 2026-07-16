/**
 * Tag Google Books items with __add-metadata and __add-file so they
 * enter the metadata-completion and file-attachment workflows.
 * Detection: url contains www.google.com/books, or libraryCatalog
 * contains "google books".
 * @author luised94
 * @usage Actions & Tags action. Trigger manually or on item added.
 * Canonical source per CONVENTIONS.md D6/A9; extracted from the former
 * add-google-tag.js concatenation (superseded draft variant dropped).
 */
if (!item) return "No item selected.";

Zotero.debug("Starting Google Books tagging script");

const addMetadataTag = "__add-metadata";
const addFileTag = "__add-file";

async function tagGoogleBooksItem(targetItem) {
    Zotero.debug(`Processing item: ${targetItem.getField('title')}`);

    let isGoogleBooks = false;
    let url = targetItem.getField('url');
    let libraryCatalog = targetItem.getField('libraryCatalog');

    Zotero.debug(`URL: ${url}`);
    Zotero.debug(`Library Catalog: ${libraryCatalog}`);

    if (url && url.includes('www.google.com/books')) {
        isGoogleBooks = true;
        Zotero.debug("Google Books URL detected");
    }

    if (libraryCatalog && libraryCatalog.toLowerCase().includes('google books')) {
        isGoogleBooks = true;
        Zotero.debug("Google Books library catalog detected");
    }

    if (isGoogleBooks) {
        if (!targetItem.hasTag(addMetadataTag)) {
            targetItem.addTag(addMetadataTag);
            Zotero.debug(`Added ${addMetadataTag} tag`);
        }

        if (!targetItem.hasTag(addFileTag)) {
            targetItem.addTag(addFileTag);
            Zotero.debug(`Added ${addFileTag} tag`);
        }

        await targetItem.saveTx();
        return `Tagged Google Books item: ${targetItem.getField('title')}`;
    }

    return `Not a Google Books item: ${targetItem.getField('title')}`;
}

if (item.isRegularItem()) {
    Zotero.debug("Processing regular item");
    return await tagGoogleBooksItem(item);
} else if (item.isAttachment()) {
    Zotero.debug("Processing attachment");
    const parentItem = Zotero.Items.get(item.parentItemID);
    return await tagGoogleBooksItem(parentItem);
} else {
    Zotero.debug("Invalid item type");
    return "Selected item is neither a regular item nor an attachment.";
}
