/*
 * Attachment Path Adjuster Script for Zotero
 *
 * This script is designed for use in the Zotero JavaScript Console
 * (Tools  Developer  Run JavaScript) to update attachment file paths
 * in the Zotero database. It identifies attachments whose file paths start
 * with an old base path and replaces them with a new base path.
 *
 * Key Features:
 *  - Batch processing with asynchronous yielding (using Zotero.Promise.delay)
 *    to avoid UI blocking during operations.
 *  - Dry-run mode to preview changes without altering the database.
 *  - Ability to limit the number of processed items for testing.
 *  - Sync detection to pause processing when Zotero is synchronizing.
 *  - Detailed debug logs highlighting progress, errors, and a sample list
 *    of changed attachments for verification.
 *
 * Note: This script only updates the Zotero database references without
 * moving the actual files on disk.
 *
 * Usage:
 *  - Set the 'dryRun' parameter to true for a test run.
 *  - Adjust the 'itemLimit' parameter to process a specific number of items.
 *  - Uncomment the desired execution block at the bottom to run the script.
 *
 * Author: LEMR
 * Date: 2025-02-12
 */
// verify rebollo, yeom, zhang, wood, speck


async function adjustAttachmentPaths(dryRun = true, adjustmentLimit = null) {
  try {
    // Check Zotero API availability
    if (!Zotero || !Zotero.Items) {
      Zotero.debug("Zotero API not available");
      return;
    }

    Zotero.debug("Starting attachment path adjustment...");
    Zotero.debug(`Dry-run mode: ${dryRun ? "ON" : "OFF"}`);
    Zotero.debug(`Adjustment limit: ${adjustmentLimit ? adjustmentLimit : "No limit"}`);

    // Define paths: Uncomment these manually to account for computer device.
    //const oldBasePath = "C:\\Users\\liusm\\Dropbox (MIT)\\";
    //const oldBasePath = "C:\\Users\\Luised94\\Dropbox (MIT)\\";
    const oldBasePath = "C:\\Users\\Luis\\Dropbox (MIT)\\";
    const newBasePath = "C:\\Users\\Luised94\\MIT Dropbox\\Luis Martinez";
    //const newBasePath = "C:\\Users\\liusm\\MIT Dropbox\\Luis Martinez\\";


    // Initial delay to ensure Zotero is ready
    await Zotero.Promise.delay(1000);

    // Get items from the user library
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
    const sampleFiles = []; // Store first 10 adjusted files for verification

    Zotero.debug("Starting item processing...");

    // Use a labeled outer loop for breaking on adjustment limit
    processLoop:
    for (let i = 0; i < items.length; i += BATCH_SIZE) {
      const batch = items.slice(i, i + BATCH_SIZE);
      
      // Process each item in the current batch
      for (let item of batch) {
        processedItems++;

        // Skip non-regular items
        if (!item.isRegularItem()) continue;

        let attachmentIDs = item.getAttachments();
        if (!attachmentIDs.length) continue;

        for (let attachmentID of attachmentIDs) {
          // Exit early if adjustment limit is reached
          if (adjustmentLimit && adjustedCount >= adjustmentLimit) {
            Zotero.debug(`Reached adjustment limit of ${adjustmentLimit}. Stopping processing.`);
            break processLoop;
          }

          let attachment = await Zotero.Items.getAsync(attachmentID);
          let currentPath = attachment.getFilePath();
          
          if (currentPath && currentPath.startsWith(oldBasePath)) {
            let newPath = currentPath.replace(oldBasePath, newBasePath);

            // Store sample files (first 10 adjustments)
            if (sampleFiles.length < 10) {
              sampleFiles.push({
                old: currentPath,
                new: newPath,
                title: attachment.getField("title")
              });
            }

            Zotero.debug(`\nAttachment detected: ${attachment.getField("title")}`);
            Zotero.debug(`  Old Path: ${currentPath}`);
            Zotero.debug(`  New Path: ${newPath}`);

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

        // Progress updates every 1000 processed items
        if (processedItems % 1000 === 0) {
          Zotero.debug(`Processed ${processedItems} items (adjusted ${adjustedCount} paths)...`);
        }
      }

      // Yield after each batch
      await Zotero.Promise.delay(BATCH_DELAY);
      
      // Pause during sync
      if (Zotero.Sync.running) {
        Zotero.debug("Sync is running. Pausing processing.");
        while (Zotero.Sync.running) {
          await Zotero.Promise.delay(1000);
        }
        Zotero.debug("Sync completed. Resuming processing.");
      }
    }

    Zotero.debug("\nProcess completed.");
    Zotero.debug(`Total items processed: ${processedItems}`);
    Zotero.debug(`Total paths adjusted${dryRun ? " (dry-run)" : ""}: ${adjustedCount}`);
    Zotero.debug(`Total errors encountered: ${errorCount}`);

    // Output sample files
    if (sampleFiles.length > 0) {
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

// Test dry-run with all items (for testing, adjust itemLimit as needed)
// Uncomment one of the following execution blocks:
// Example: Dry-run with a limit of 10 adjustments
window.setTimeout(() => {
  adjustAttachmentPaths(true, 10)
    .then(result => Zotero.debug(result))
    .catch(error => Zotero.debug("Error: " + error));
}, 1000);

// Dry-run test with no limit:
// window.setTimeout(() => {
//   adjustAttachmentPaths(true, null)
//     .then(result => Zotero.debug(result))
//     .catch(error => Zotero.debug("Error: " + error));
// }, 1000);

// Actual update with a limit of 10 items:
// window.setTimeout(() => {
//   adjustAttachmentPaths(false, 10)
//     .then(result => Zotero.debug(result))
//     .catch(error => Zotero.debug("Error: " + error));
// }, 1000);

// Full update with no limit:
// window.setTimeout(() => {
//   adjustAttachmentPaths(false, null)
//     .then(result => Zotero.debug(result))
//     .catch(error => Zotero.debug("Error: " + error));
// }, 1000);
