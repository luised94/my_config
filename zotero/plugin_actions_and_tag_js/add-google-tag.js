
/**
 * Add __in_progress tag when file is opened if no __in_progress or __read tag present
 * @author [Your Name]
 * @usage Add to Zotero Actions and Tags plugin
 */

if (!item) return;

const addMetadataTag = '__add-metadata';
const addFileTag = '__add-file';
const catalogToMatch = 'google books';

/**
 * Add __read tag and Remove __in_progress tag for the selected item
 * @author [Your Name]
 * @usage See below
 */
if (!item) return;

if (item.isAttachment() || item.isNote()) {
    const parentItem = Zotero.Items.getTopLevel([item])[0];
    if (parentItem.hasTag("__in_progress") && !parentItem.hasTag("__read")) {
        parentItem.removeTag("__in_progress");
        parentItem.addTag("__read");
        await parentItem.saveTx();
        return `Marked as read: ${parentItem.getField("title")}`;
    } else {
        return `The parent item doesn't have __in_progress tag or already has __read tag. Please check!`;
    }
}
else if (item.isRegularItem()) {
    if (item.hasTag("__in_progress") && !item.hasTag("__read")) {
        item.removeTag("__in_progress");
        item.addTag("__read");
        await item.saveTx();
        return `Marked as read: ${item.getField("title")}`;
    } else {
        return `The item doesn't have __in_progress tag or already has __read tag. Please check!`;
    }
}
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
    return "What the hell kind of item did you add? It's neither a regular item nor an attachment.";
}
if (!item) return "No item selected, you moron.";

//Zotero.debug("Starting Google Books tagging script");

const addMetadataTag = '__add-metadata';
const addFileTag = '__add-file';
//const googleBooksUrl = 'www.google.com/books';
const catalogToMatch = 'google books';

//Zotero.debug(`Checking item: ${item.getField('title')}`);

//let shouldTag = false;

//if (item.getField('url')) {
//    Zotero.debug(`URL found: ${item.getField('url')}`);
//    if (item.getField('url').includes(googleBooksUrl)) {
//        Zotero.debug("URL is from Google Books");
//        shouldTag = true;
//    }
//}

if (item.getField('libraryCatalog').toLowerCase() === catalogToMatch ) {
    Zotero.debug(`Library catalog: ${item.getField('libraryCatalog')}`);
    if (item.getField('libraryCatalog').toLowerCase().includes("google books")) {
        Zotero.debug("Library catalog is Google Books");
        shouldTag = true;
    }
}

if (shouldTag) {
    Zotero.debug("Item qualifies for tagging");
    if (!item.hasTag(addMetadataTag)) {
        item.addTag(addMetadataTag);
        Zotero.debug(`Added ${addMetadataTag} tag`);
    } else {
        Zotero.debug(`${addMetadataTag} tag already present`);
    }
    
    if (!item.hasTag(addFileTag)) {
        item.addTag(addFileTag);
        Zotero.debug(`Added ${addFileTag} tag`);
    } else {
        Zotero.debug(`${addFileTag} tag already present`);
    }
    
    await item.saveTx();
    Zotero.debug("Item saved with new tags");
    return `Tagged item: ${item.getField('title')} with ${addMetadataTag} and ${addFileTag}`;
} else {
    Zotero.debug("Item does not qualify for tagging");
    return `No action needed for: ${item.getField('title')}`;
}
