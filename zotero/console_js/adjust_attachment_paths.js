/*
 * Attachment Path Adjuster Script for Zotero (Upgraded)
 *
 * This script updates attachment file paths by replacing an old base path
 * with a new one. The script processes items in batches, yielding between
 * batches (and pausing during sync) and logging detailed debug messages.
 *
 * Upgrades:
 * 1. All changes are made in memory and, if live (dryRun==false), are applied
 *    within a single transaction when processing is complete.
 * 2. A global cancellation flag is supported. Call requestCancel() to trigger
 *    a safe exit from the processing loop without leaving the database in an
 *    inconsistent state.
 *
 * Usage:
 *  - Set dryRun to true for a dry-run (no database changes) or false for a live update.
 *  - Optionally set an adjustmentLimit for processing (e.g., for testing).
 *  - To cancel, call requestCancel() from the console.
 *
 * Author: LEMR
 * Date: 2025-02-12 (updated)
 */

// Global cancellation flag
let cancelRequested = false;
// Function to signal cancellation (type "requestCancel()" in the console to stop early)
function requestCancel() {
  cancelRequested = true;
  Zotero.debug("Cancellation requested by user.");
}

async function adjustAttachmentPaths(dryRun = true, adjustmentLimit = null) {
  try {
    if (!Zotero || !Zotero.Items) {
      Zotero.debug("Zotero API not available");
      return;
    }
    Zotero.debug("Starting attachment path adjustment...");
    Zotero.debug(`Dry-run mode: ${dryRun ? "ON" : "OFF"}`);
    Zotero.debug(`Adjustment limit: ${adjustmentLimit ? adjustmentLimit : "No limit"}`);

    // Define the old and new base paths (adjust these as needed for each device)
    const oldBasePath = "C:\\Users\\Luis\\Dropbox (MIT)\\";
    const newBasePath = "C:\\Users\\Luised94\\MIT Dropbox\\Luis Martinez";
    
    // Delay to ensure Zotero is ready.
    await Zotero.Promise.delay(1000);
    
    // Retrieve user library items
    let items = await Zotero.Items.getAll(Zotero.Libraries.userLibraryID);
    Zotero.debug("Items retrieved successfully");
    Zotero.debug(`Total items in library: ${items ? items.length : 0}`);
    if (!items || !items.length) {
      Zotero.debug("No items found in library");
      return;
    }
    let adjustedCount = 0;
    let processedItems = 0;
    let errorCount = 0;
    const BATCH_SIZE = 100;
    const BATCH_DELAY = 100;
    const sampleFiles = []; // Stores first 10 adjusted attachment info for verification
    
    Zotero.debug("Starting item processing...");

    // Define an internal function to process all items.
    let updateTransaction = async () => {
      processLoop:
      for (let i = 0; i < items.length; i += BATCH_SIZE) {
        const batch = items.slice(i, i + BATCH_SIZE);
        for (let item of batch) {
          // Check the cancellation flag at a safe checkpoint.
          if (cancelRequested) {
            Zotero.debug("Cancellation detected. Exiting processing loop gracefully.");
            break processLoop;
          }
          processedItems++;
          if (!item.isRegularItem()) continue;
          let attachmentIDs = item.getAttachments();
          if (!attachmentIDs.length) continue;
          for (let attachmentID of attachmentIDs) {
            if (adjustmentLimit && adjustedCount >= adjustmentLimit) {
              Zotero.debug(`Reached adjustment limit of ${adjustmentLimit}. Stopping processing.`);
              break processLoop;
            }
            let attachment = await Zotero.Items.getAsync(attachmentID);
            let currentPath = attachment.getFilePath();
            if (currentPath && currentPath.startsWith(oldBasePath)) {
              let newPath = currentPath.replace(oldBasePath, newBasePath);
              if (sampleFiles.length < 10) {
                sampleFiles.push({
                  old: currentPath,
                  new: newPath,
                  title: attachment.getField("title")
                });
              }
              Zotero.debug(`\nAttachment detected: ${attachment.getField("title")}`);
              Zotero.debug("  Old Path: " + currentPath);
              Zotero.debug("  New Path: " + newPath);
              if (!dryRun) {
                try {
                  // Update the attachment's path in memory.
                  attachment.attachmentPath = newPath;
                  adjustedCount++;
                  Zotero.debug("  Attachment path updated (in memory).");
                } catch (error) {
                  errorCount++;
                  Zotero.debug("  Error updating path: " + error);
                }
              } else {
                // In dry-run mode, only log the intended change.
                adjustedCount++;
                Zotero.debug("  Dry-run: No changes made.");
              }
            }
          }
          if (processedItems % 1000 === 0) {
            Zotero.debug(`Processed ${processedItems} items (adjusted ${adjustedCount} paths)...`);
          }
        }
        await Zotero.Promise.delay(BATCH_DELAY);
        // Pause processing while a sync is running.
        if (Zotero.Sync.running) {
          Zotero.debug("Sync is running. Pausing processing.");
          while (Zotero.Sync.running) {
            await Zotero.Promise.delay(1000);
          }
          Zotero.debug("Sync completed. Resuming processing.");
        }
      }
    };
    
    // If live update mode is active, wrap all updates in a single transaction;
    // otherwise, in dry-run mode, simply execute the processing logic.
    if (!dryRun) {
      await Zotero.DB.transaction(async () => {
        await updateTransaction();
      });
    } else {
      await updateTransaction();
    }
    
    Zotero.debug("\nProcess completed.");
    Zotero.debug("Total items processed: " + processedItems);
    Zotero.debug(`Total paths adjusted${dryRun ? " (dry-run)" : ""}: ${adjustedCount}`);
    Zotero.debug("Total errors encountered: " + errorCount);
    
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

// Execution examples:
// Use window.setTimeout to allow Zotero to finish startup before processing begins.

// Example 1: Dry-run test with an adjustment limit of 10.
window.setTimeout(() => {
  adjustAttachmentPaths(true, 10)
    .then(result => Zotero.debug(result))
    .catch(error => Zotero.debug("Error: " + error));
}, 1000);

// Example 2: For a full live update (no limit and saving changes in one transaction),
// uncomment the code below and run:
// window.setTimeout(() => {
//   adjustAttachmentPaths(false, null)
//     .then(result => Zotero.debug(result))
//     .catch(error => Zotero.debug("Error: " + error));
// }, 1000);
// To cancel the running process (if it takes too long), type the following in the Zotero console:
// requestCancel();
