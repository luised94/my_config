/**
 * Mark item as read: replace __in_progress with __read on the selected
 * item (or the parent of a selected attachment/note).
 * @author luised94
 * @usage Actions & Tags action. Trigger manually (menu/shortcut).
 * Canonical source per CONVENTIONS.md D6/A9; extracted from the former
 * add-google-tag.js concatenation.
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
else {
    return "Selected item is neither an attachment, a note, nor a regular item.";
}
