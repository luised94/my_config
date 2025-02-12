async function adjustAttachmentPaths(dryRun = true, itemLimit = null) {
  try {
    Zotero.debug("Starting attachment path adjustment...");
    Zotero.debug(`Dry-run mode: ${dryRun ? "ON" : "OFF"}`);
    Zotero.debug(`Item limit: ${itemLimit ? itemLimit : "No limit"}`);

    // Define paths
    const oldBasePath = "C:\\Users\\Luis\\Dropbox (MIT)\\";
    const newBasePath = "C:\\Users\\Luised94\\MIT Dropbox\\Luis Martinez\\";

    // Check Zotero API
    if (!Zotero || !Zotero.Items) {
      Zotero.debug("Zotero API not available");
      return;
    }

    // Initial delay to ensure Zotero is ready
    await Zotero.Promise.delay(1000);

    // Get items with user library specification
    let items;
    try {
      items = await Zotero.Items.getAll(Zotero.Libraries.userLibraryID);
      Zotero.debug("Items retrieved successfully");
      Zotero.debug(`Total items in library: ${items ? items.length : 0}`);
    } catch (e) {
      Zotero.debug("Error getting items: " + e);
      return;
    }

    if (!items || !items.length) {
      Zotero.debug("No items found in library");
      return;
    }

    let adjustedCount = 0;
    let processedItems = 0;
    let errorCount = 0;
    const BATCH_SIZE = 100;
    const BATCH_DELAY = 100;
    const sampleFiles = []; 

    Zotero.debug("Starting item processing...");
    
    // Process items in batches
    for (let i = 0; i < items.length; i += BATCH_SIZE) {
      if (itemLimit && processedItems >= itemLimit) {
        Zotero.debug(`Reached item limit of ${itemLimit}. Stopping processing.`);
        break;
      }
      const batch = items.slice(i, i + BATCH_SIZE);
      
      // Process each batch
      for (let item of batch) {
        
        if (itemLimit && processedItems >= itemLimit) {
            Zotero.debug(`Reached item limit of ${itemLimit}. Stopping processing.`);
          break;
        }
        processedItems++;
        // Skip non-regular items
        if (!item.isRegularItem()) continue;

        // Get all attachments for this parent item
        let attachmentIDs = item.getAttachments();
        if (!attachmentIDs.length) continue;

        for (let attachmentID of attachmentIDs) {
          let attachment = await Zotero.Items.getAsync(attachmentID);
          
          let currentPath = attachment.getFilePath();
          if (currentPath && currentPath.startsWith(oldBasePath)) {
            let newPath = currentPath.replace(oldBasePath, newBasePath);

            // Verify file exists in old location
            //let fileExists = await attachment.fileExists();
            //if (!fileExists) {
            //  Zotero.debug(`WARNING: Source file not found: ${currentPath}`);
            //  errorCount++;
            //  continue;
            //}
            // Store sample files if limit is set
            if (itemLimit && sampleFiles.length < 10) {
              sampleFiles.push({
                old: currentPath,
                new: newPath,
                title: attachment.getField("title")
              });
            }

            Zotero.debug(`\nAttachment detected: ${attachment.getField("title")}`);
            Zotero.debug(`  Old Path: ${currentPath}`);
            Zotero.debug(`  New Path: ${newPath}`);
            //Zotero.debug(`  File exists: ${fileExists ? "Yes" : "No"}`);

            if (!dryRun) {
              try {
                attachment.attachmentPath = newPath;
                await attachment.saveTx();
                adjustedCount++;
                Zotero.debug("  Attachment path updated successfully.");
              } catch (error) {
                errorCount++;
                Zotero.debug("  Error updating path: " + error);
              }
            } else {
              adjustedCount++;
              Zotero.debug("  Dry-run: No changes made.");
            }
          }
        }

        // Progress updates
        if (processedItems % 1000 === 0) {
          Zotero.debug(`Processed ${processedItems} of ${items.length} items...`);
          Zotero.debug(`Current stats - Adjusted: ${adjustedCount}, Errors: ${errorCount}`);
        }
      }
      // Yield fully after each batch
      await Zotero.Promise.delay(200); 
      // Delay allows other processes to run
      //await new Promise(resolve => setTimeout(resolve, BATCH_DELAY));
      // Check for sync or other interruptions
      if (Zotero.Sync.running) {
        Zotero.debug("Sync is running. Pausing processing.");
        while (Zotero.Sync.running) {
          await Zotero.Promise.delay(1000); // Wait until sync finishes
        }
        Zotero.debug("Sync completed. Resuming processing.");
      }
      if (i % (BATCH_SIZE * 10) === 0) {
        await new Promise(resolve => setTimeout(resolve, 500));
      }
    }

    Zotero.debug("\nProcess completed.");
    Zotero.debug(`Total items processed: ${processedItems}`);
    Zotero.debug(`Total paths adjusted${dryRun ? " (dry-run)" : ""}: ${adjustedCount}`);
    Zotero.debug(`Total errors encountered: ${errorCount}`);
    
    // Display sample files if limit was used
    if (itemLimit && sampleFiles.length > 0) {
      Zotero.debug("\nSample files processed:");
      sampleFiles.forEach((file, index) => {
        Zotero.debug(`  ${index + 1}. ${file.title}`);
        Zotero.debug(`     Old: ${file.old}`);
        Zotero.debug(`     New: ${file.new}`);
      });
    }
    
    return `Adjusted ${adjustedCount} paths${dryRun ? " (dry-run)" : ""}. Errors: ${errorCount}`;
  } catch (error) {
    Zotero.debug("Fatal error: " + error);
    return `Error: ${error}`;
  }
}

// Test run with 10 items limit
/*
window.setTimeout(() => {
  // For initial testing: dry run with 10 items
  adjustAttachmentPaths(true, 10)
    .then(result => Zotero.debug(result))
    .catch(error => Zotero.debug("Error: " + error));
}, 1000);
*/

// Test dry-run with all.
/*
*/
window.setTimeout(() => {
  adjustAttachmentPaths(true, null)
    .then(result => Zotero.debug(result))
    .catch(error => Zotero.debug("Error: " + error));
}, 1000);


// For actual update with only 10 test items (uncomment when ready):
/*
window.setTimeout(() => {
  // First update 10 items
  adjustAttachmentPaths(false, 10)
    .then(result => Zotero.debug(result))
    .catch(error => Zotero.debug("Error: " + error));
}, 1000);
*/

// For full update (uncomment when ready):
/*
window.setTimeout(() => {
  // Update all items
  adjustAttachmentPaths(false, null)
    .then(result => Zotero.debug(result))
    .catch(error => Zotero.debug("Error: " + error));
}, 1000);
*/
