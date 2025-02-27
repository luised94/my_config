---
title: My personal configuration repository README
---
# my_config

## Introduction

## TODO
- [] Ensure all checks for quarto check are fulfilled or use wslview/w3m.
- [] vim_all does not handle files with spaces. Solutions: Enforce naming standard and upgrade vim_all to handle spaces better.
- [] Figure out how to export zotero bib files consistently and reliably. Maybe just export all the items.

## Errors I encountered during installation

### Working with dropbox files
Ensure that when you are moving a file from dropbox, it is downloaded. If you move a file from dropbox using wsl and the file isnt downloaded, it essentially deletes the file.

### Tree-sitter r_language_server lsp

Mason was giving me errors during installation of the r-languageserver.
To see how I resolved the issue, look at the -- R r-languageserver section and 001_setupR directory from my lab_utils repository.
Briefly, I installed r-languageserver via R using install.packages() and then setup the r-languageserver by itself in the lsp.lua config file.
This way, Mason doesnt try to install it everytime I open Neovim.
