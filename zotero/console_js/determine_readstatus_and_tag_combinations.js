(async function() {
    const VALID_TAGS = ['__not_reading', '__in_progress', '__to_read', '__read', '__unopened'];
    const BATCH_SIZE = 100;
    const MAX_ITEMS_TO_PROCESS = 500; // Adjust this number as needed

    const library = Zotero.Libraries.userLibrary;
    const items = await Zotero.Items.getAll(library.id);

    let stats = {
        total: 0,
        readStatusCounts: {},
        tagCombinations: {},
        noReadStatus: 0,
        noValidTags: 0,
        nonValidDoubleTags: 0
    };

    let processedCount = 0;
    let batchCount = 0;

    let progressWindow = new Zotero.ProgressWindow({closeOnClick: false});
    progressWindow.changeHeadline("Analyzing Zotero Items");
    progressWindow.show();
    let progressIndicator = new progressWindow.ItemProgress(
        "chrome://zotero/skin/tick.png",
        "Processing items..."
    );

    for (let i = 0; i < items.length && processedCount < MAX_ITEMS_TO_PROCESS; i += BATCH_SIZE) {
        let batch = items.slice(i, Math.min(i + BATCH_SIZE, items.length, i + MAX_ITEMS_TO_PROCESS - processedCount));
        
        for (let item of batch) {
            if (item.isRegularItem() && !item.isAnnotation() && !item.isNote()) {
                stats.total++;
                
                // Analyze Read_Status
                let extra = item.getField('extra');
                let readStatus = extra.match(/Read_Status:\s*(.+)/);
                if (readStatus) {
                    let status = readStatus[1].trim().toLowerCase();
                    stats.readStatusCounts[status] = (stats.readStatusCounts[status] || 0) + 1;
                } else {
                    stats.noReadStatus++;
                }

                // Analyze tags
                let allTags = item.getTags();
                let validTags = allTags.filter(tag => VALID_TAGS.includes(tag.tag));
                let validTagNames = validTags.map(tag => tag.tag).sort().join(',');

                if (validTags.length === 0) {
                    if (allTags.some(tag => tag.tag.startsWith('__'))) {
                        stats.nonValidDoubleTags++;
                    } else {
                        stats.noValidTags++;
                    }
                }

                // Combine Read_Status and valid tags
                let combination = (readStatus ? readStatus[1].trim().toLowerCase() : 'no_status') + '|' + (validTagNames || 'no_valid_tags');
                stats.tagCombinations[combination] = (stats.tagCombinations[combination] || 0) + 1;
            }

            processedCount++;
            progressIndicator.setProgress(processedCount / Math.min(items.length, MAX_ITEMS_TO_PROCESS) * 100);
        }

        batchCount++;
        Zotero.debug(`Completed batch ${batchCount}. Items processed: ${processedCount}`);
        await Zotero.Promise.delay(10); // Small delay between batches
    }

    progressWindow.close();

    // Sort and format results
    let formattedStats = {
        total: stats.total,
        readStatusCounts: Object.entries(stats.readStatusCounts)
            .sort(([,a],[,b]) => b-a)
            .reduce((r, [k, v]) => ({ ...r, [k]: v }), {}),
        tagCombinations: Object.entries(stats.tagCombinations)
            .sort(([,a],[,b]) => b-a)
            .reduce((r, [k, v]) => ({ ...r, [k]: v }), {}),
        noReadStatus: stats.noReadStatus,
        noValidTags: stats.noValidTags,
        nonValidDoubleTags: stats.nonValidDoubleTags
    };

    Zotero.debug("Library Statistics:");
    Zotero.debug(JSON.stringify(formattedStats, null, 2));

    return `Statistics logged to debug output. Processed ${processedCount} out of ${items.length} items in ${batchCount} batches.`;
})();
