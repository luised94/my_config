(async function() {
    const BATCH_SIZE = 100;
    const MAX_ITEMS_TO_PROCESS = 500;
    const VALID_TAGS = ['__in_progress', '__to_read', '__read', '__unopened'];

    let library = Zotero.Libraries.userLibrary;
    let items = await Zotero.Items.getAll(library.id);
    let processedCount = 0;
    let batchCount = 0;
    let stats = {
        noAction: 0,
        tagAdded: 0,
        tagReplaced: 0,
        unopenedAdded: 0
    };

    let progressWindow = new Zotero.ProgressWindow({closeOnClick: false});
    progressWindow.changeHeadline("Processing Zotero Items");
    progressWindow.show();
    let progressIndicator = new progressWindow.ItemProgress(
        "chrome://zotero/skin/tick.png",
        "Processing items..."
    );

    for (let i = 0; i < items.length && processedCount < MAX_ITEMS_TO_PROCESS; i += BATCH_SIZE) {
        let batch = items.slice(i, Math.min(i + BATCH_SIZE, items.length, i + MAX_ITEMS_TO_PROCESS - processedCount));
        let batchOutput = [];
        
        for (let item of batch) {
            if (item.isRegularItem() && !item.isAnnotation() && !item.isNote()) {
                let extra = item.getField('extra');
                let existingTags = item.getTags().filter(tag => VALID_TAGS.includes(tag.tag));
                let action = '';

                if (extra && extra.match(/Read_Status:\s*(.+)/)) {
                    let match = extra.match(/Read_Status:\s*(.+)/);
                    let status = match[1].trim().toLowerCase();
                    let newTag = `__${status.replace(/\s+/g, '_')}`;

                    if (existingTags.length > 0) {
                        if (existingTags.some(tag => tag.tag === '__unopened')) {
                            if (['__in_progress', '__read'].includes(newTag)) {
                                action = `Replace __unopened with ${newTag}`;
                                stats.tagReplaced++;
                                // Commented out save logic
                                /*
                                item.removeTag('__unopened');
                                item.addTag(newTag);
                                await item.saveTx();
                                */
                            } else if (newTag === '__to_read') {
                                action = `Add ${newTag}`;
                                stats.tagAdded++;
                                // Commented out save logic
                                /*
                                item.addTag(newTag);
                                await item.saveTx();
                                */
                            } else {
                                action = 'No action (Prioritize existing __unopened)';
                                stats.noAction++;
                            }
                        } else {
                            action = 'No action (Prioritize existing tag)';
                            stats.noAction++;
                        }
                    } else if (newTag !== '__new') {
                        action = `Add ${newTag}`;
                        stats.tagAdded++;
                        // Commented out save logic
                        /*
                        item.addTag(newTag);
                        await item.saveTx();
                        */
                    } else {
                        action = 'No action (New status)';
                        stats.noAction++;
                    }
                } else if (existingTags.length === 0) {
                    action = 'Add __unopened tag';
                    stats.unopenedAdded++;
                    // Commented out save logic
                    /*
                    item.addTag('__unopened');
                    await item.saveTx();
                    */
                } else {
                    action = 'No action (Existing tag without Read_Status)';
                    stats.noAction++;
                }
                
                batchOutput.push({
                    title: item.getField('title'),
                    currentTags: item.getTags().map(tag => tag.tag),
                    extraContent: extra,
                    action: action
                });
            }

            processedCount++;
            progressIndicator.setProgress(processedCount / Math.min(items.length, MAX_ITEMS_TO_PROCESS) * 100);
        }

        // Print batch output
        for (let item of batchOutput) {
            Zotero.debug("Title: " + item.title);
            Zotero.debug("Current Tags: " + item.currentTags.join(", "));
            Zotero.debug("Extra Content: " + item.extraContent);
            Zotero.debug("Proposed Action: " + item.action);
            Zotero.debug("-----------------------------------");
        }

        batchCount++;
        Zotero.debug(`Completed batch ${batchCount}. Items processed: ${processedCount}`);
        await Zotero.Promise.delay(10);
    }

    progressWindow.close();

    let resultMessage = `Processed ${processedCount} out of ${items.length} items in ${batchCount} batches.\n`;
    resultMessage += `Statistics:\n`;
    resultMessage += `No Action: ${stats.noAction}\n`;
    resultMessage += `Tags Added: ${stats.tagAdded}\n`;
    resultMessage += `Tags Replaced: ${stats.tagReplaced}\n`;
    resultMessage += `Unopened Tags Added: ${stats.unopenedAdded}\n`;
    resultMessage += `Check the debug output for details.`;

    Zotero.debug(resultMessage);
    return resultMessage;
})();
