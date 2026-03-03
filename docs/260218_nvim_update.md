# Neovim Update & Migration Guide (February 18, 2026)

This document covers two critical fixes made during the February 18, 2026 update session:
1. **Shell Environment:** Restored `nvm` to enable npm-dependent LSP servers
2. **LuaSnip Plugin:** Fixed git submodule corruption and pinned to stable releases

---

## Prerequisites: Fix Shell Environment First

**Issue:** Mason-installed LSP servers that depend on `npm` (like `bash-language-server`) were failing because `nvm` was not initialized in the shell.

### On Your Current Machine (if needed)
If `npm` commands don't work or Mason can't install npm-based servers, restore nvm in your `.bashrc`:

```bash
# Add to ~/.bashrc (usually near the end)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # Optional: bash completion
```

Then reload your shell:
```bash
source ~/.bashrc
```

Verify npm is available:
```bash
npm --version
node --version
```

### On New Machines
Ensure `nvm` is installed and sourced in `.bashrc` **before** opening Neovim. Mason needs `npm` in your PATH to install JavaScript/TypeScript-based language servers.

---

## Migration Instructions for Other Devices

Follow these steps in order to replicate both the R LSP and LuaSnip fixes on other machines.

### 1. Update Your Neovim Config (Git)
Pull the latest changes from your configuration repository:

```bash
cd ~/.config/nvim  # or wherever your config lives
git pull
```

### 2. Install Build Tools (Ubuntu/WSL Only)
LuaSnip's `jsregexp` build step requires a C compiler and cmake:

```bash
sudo apt update
sudo apt install -y git build-essential cmake
```

**Note:** If you're not on Ubuntu/WSL or don't need snippet transformations, you can skip this step and comment out `build = "make install_jsregexp"` in your LuaSnip plugin spec.

### 3. Clean and Reinstall Plugins
Remove deprecated/corrupted plugins and install updates:

Open Neovim and run:
```vim
:Lazy clean
:Lazy sync
```

**Expected outcomes:**
- Old `cmp-nvim-r` plugin will be removed
- LuaSnip will be reinstalled at the pinned `v2.*` version
- The `make install_jsregexp` build step will run (if build tools are installed)

Restart Neovim after this step.

### 4. Install R Language Server Package

The R LSP requires the `languageserver` R package to be installed.

#### For Global Use (Standalone scripts, non-renv projects):
Run this in your terminal:
```bash
R --slave -e "install.packages('languageserver', repos='https://cran.rstudio.com/')"
```

#### For renv Projects:
Navigate to your project root and install it into the project library:
```bash
cd ~/path/to/my-renv-project
R --slave -e "renv::install('languageserver')"
```

**Tip:** For projects that use both approaches, you may want both a global install (for quick scripts) and project-specific installs (for reproducible environments).

### 5. Verify Everything Works

#### Check R LSP:
Open an R file in Neovim and run:
```vim
:LspInfo
```
You should see `r_language_server` listed as **"Attached"** with filetypes `r`, `rmd`, `quarto`.

#### Check Bash LSP:
Open a `.sh` file and run:
```vim
:LspInfo
```
You should see `bashls` (bash-language-server) listed as **"Attached"**.

If it's not attached, verify npm is available:
```bash
npm --version
```

#### Check LuaSnip:
In insert mode in any file, try triggering a snippet. For Lua files, you can test with:
```lua
req<tab>  # Should expand to require("")
```

If snippets don't work, run:
```vim
:Lazy log LuaSnip
```
to check if the build step completed successfully.

---

## Troubleshooting

### Mason can't install bash-language-server
**Symptom:** Mason shows "npm not available" when trying to install `bashls`.

**Solution:** Ensure nvm is sourced in your `.bashrc` (see Prerequisites section above), then restart your terminal and Neovim.

### LuaSnip build step fails
**Symptom:** `make install_jsregexp` fails during `:Lazy sync`.

**Solutions:**
1. Install build tools: `sudo apt install -y build-essential cmake` (Ubuntu/WSL)
2. Or comment out `build = "make install_jsregexp"` in your LuaSnip spec-jsregexp is optional; snippets will still work but transformations will be simpler.

### R LSP won't attach to standalone scripts
**Symptom:** LSP works in `.Rproj` projects but not in `~/my_script.R`.

**Solution:** The new config includes a fallback to use the file's directory as root_dir. If this still fails:
1. Verify `languageserver` is installed globally: `R -e "library(languageserver)"`
2. Check `:LspLog` for errors about missing packages.

### LuaSnip still shows update errors after migration
**Symptom:** `:Lazy sync` still reports git submodule errors for LuaSnip.

**Solution:** Manually remove and reinstall:
```bash
rm -rf ~/.local/share/nvim/lazy/LuaSnip
```
Then in Neovim: `:Lazy sync`

---

## Summary of Changes

### R LSP (Previous Session)
- Removed deprecated `cmp-nvim-r` plugin
- Configured `r_language_server` manually with improved root detection
- Added fallback to file directory for standalone scripts

### Shell Environment (Current Session)
- Restored nvm initialization in `.bashrc`
- Fixed npm availability for Mason

### LuaSnip (Current Session)
- Fixed git submodule corruption
- Pinned to `v2.*` stable release series
- Added optional `jsregexp` build step for snippet transformations
