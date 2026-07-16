/**
 * Add __in_progress tag when a file is opened, unless the item already
 * has __in_progress or __read.
 * @author luised94
 * @usage Actions & Tags action. Event: open file. Operation: script.
 * Canonical source per CONVENTIONS.md D6/A9; actions-zotero.yml is the
 * exported backup.
 */
if (!item) return;

const inProgressTag = "__in_progress";
const readTag = "__read";

async function addInProgressTag(targetItem) {
    if (!targetItem.hasTag(inProgressTag) && !targetItem.hasTag(readTag)) {
        targetItem.addTag(inProgressTag);
        await targetItem.saveTx();
        return `Added ${inProgressTag} tag to: ${targetItem.getField("title")}`;
    }
    return `No action needed for: ${targetItem.getField("title")}`;
}

if (item.isAttachment()) {
    const parentItem = Zotero.Items.getTopLevel([item])[0];
    const result = await addInProgressTag(parentItem);
    return result;
}
else if (item.isRegularItem()) {
    const result = await addInProgressTag(item);
    return result;
}
else {
    return "Selected item is neither an attachment nor a regular item.";
}
