(async function() {
    const BATCH_SIZE = 100;
    const MAX_ITEMS_TO_PROCESS = 500; // Set to a number or "Infinity" for testing
    const VALID_TAGS = ['__not_reading', '__in_progress', '__to_read', '__read', '__unopened'];

    const library = Zotero.Libraries.userLibrary;
    const items = await Zotero.Items.getAll(library.id);
    let processedCount = 0;
    let batchCount = 0;
    // Configuration object
    const config = {
        dryRun: true, // Set to false to actually apply changes
        verbosity: 2  // 0: silent, 1: basic info, 2: detailed info
    };

    // Logging function
    const log = (message, level = 1) => {
        if (config.verbosity >= level) {
            Zotero.debug(message);
        }
    };
    
    log(`Starting processing with dry run: ${config.dryRun}`, 1);
    const stats = {
        noAction: 0,
        invalidTag: 0,
        tagAdded: 0,
        tagReplaced: 0,
        unopenedAdded: 0,
        multipleTagsResolved: 0
    };

    const progressWindow = new Zotero.ProgressWindow({closeOnClick: false});
    progressWindow.changeHeadline("Processing Zotero Items");
    progressWindow.show();
    const progressIndicator = new progressWindow.ItemProgress(
        "chrome://zotero/skin/tick.png",
        "Processing items..."
    );

    for (let i = 0; i < items.length && processedCount < MAX_ITEMS_TO_PROCESS; i += BATCH_SIZE) {
        const batch = items.slice(i, Math.min(i + BATCH_SIZE, items.length, i + MAX_ITEMS_TO_PROCESS - processedCount));
        const batchOutput = [];
        
        for (const item of batch) {
            if (item.isRegularItem() && !item.isAnnotation() && !item.isNote()) {
                const extra = item.getField('extra');
                const allTags = item.getTags();
                const validTags = allTags.filter(tag => VALID_TAGS.includes(tag.tag));
                let action = '';

                const readStatusMatch = extra ? extra.match(/Read_Status:\s*(.+)/) : null;
                const readStatus = readStatusMatch ? readStatusMatch[1].trim().toLowerCase() : null;

                if (readStatus) {
                    const newTag = readStatus === 'not reading' ? '__not_reading' : `__${readStatus.replace(/\s+/g, '_')}`;
                    
                    if (validTags.length > 0) {
                        if (validTags.some(tag => tag.tag === '__unopened')) {
                            if (['__in_progress', '__read', '__not_reading'].includes(newTag)) {
                                action = `Replace __unopened with ${newTag}`;
                                stats.tagReplaced++;
                                // if (!config.dryRun) {
                                //  item.removeTag('__unopened');
                                //  item.addTag(newTag);
                                // }
                            } else if (newTag === '__to_read') {
                                action = `Add ${newTag}`;
                                stats.tagAdded++;
                                // if (!config.dryRun) {
                                //  item.addTag(newTag);
                                // }
                            } else {
                                action = 'No action (Prioritize existing __unopened)';
                                stats.noAction++;
                            }
                        } else if (validTags.length > 1) {
                            action = `Resolve multiple tags: ${validTags.map(t => t.tag).join(', ')}`;
                            stats.multipleTagsResolved++;
                            // Implement logic to resolve multiple tags
                        } else {
                            action = 'No action (Existing valid tag matches Read_Status)';
                            stats.noAction++;
                        }
                    } else if (newTag !== '__new') {
                        action = `Add ${newTag}`;
                        stats.tagAdded++;
                        // if (!config.dryRun) {
                        //  item.addTag(newTag);
                        // }
                    } else {
                        action = 'No action (New status)';
                        stats.noAction++;
                    }
                } else if (validTags.length === 0) {
                    if (allTags.length === 0 || !allTags.some(tag => tag.tag.startsWith('__'))) {
                        action = 'Add __unopened tag';
                        stats.unopenedAdded++;
                        if (!config.dryRun) {

                        // item.addTag('__unopened');
                        }
                    } else {
                        action = 'No action (Existing non-valid double underscore tag)';
                        stats.invalidTag++;
                    }
                } else {
                    action = 'No action (Existing valid tag without Read_Status)';
                    stats.noAction++;
                }

                batchOutput.push({
                    title: item.getField('title'),
                    currentTags: allTags.map(tag => tag.tag),
                    extraContent: extra,
                    action: action
                });

                // Uncomment to apply changes
                // if (!config.dryRun) {
                // await item.saveTx();
                // }
            }

            processedCount++;
            progressIndicator.setProgress(processedCount / Math.min(items.length, MAX_ITEMS_TO_PROCESS) * 100);
        }

        // Print batch output
        log(`Batch ${batchCount + 1} output:`, 2);
        batchOutput.forEach(item => {
            log(`Title: ${item.title}`, 2);
            log(`Current Tags: ${item.currentTags.join(", ")}`, 2);
            log(`Extra Content: ${item.extraContent}`, 2);
            log(`Proposed Action: ${item.action}`, 2);
            log("-----------------------------------", 2);
        });

        batchCount++;
        log(`Completed batch ${batchCount}. Items processed: ${processedCount}`, 1);
        await Zotero.Promise.delay(10);
    }

    progressWindow.close();

    const resultMessage = [
        `Processed ${processedCount} out of ${items.length} items in ${batchCount} batches.`,
        "Statistics:",
        `No Action: ${stats.noAction}`,
        `Invalid Tag: ${stats.invalidTag}`,
        `Tags Added: ${stats.tagAdded}`,
        `Tags Replaced: ${stats.tagReplaced}`,
        `Unopened Tags Added: ${stats.unopenedAdded}`,
        `Multiple Tags Resolved: ${stats.multipleTagsResolved}`,
        "Check the debug output for details."
    ].join('\n');
    resultMessage.split('\n').forEach(line => log(line, 1));
    return resultMessage;
})();
