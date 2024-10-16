(async function() {
    const VALID_TAGS = ['__not_reading', '__in_progress', '__to_read', '__read', '__unopened'];
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

    for (let item of items) {
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
    }

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

    return "Statistics logged to debug output.";
})();
