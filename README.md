# my_config
Read common errors section.

# Install neovim kickstart, quarto, and zotero
## If you installed using package manager and it was a outdated version 
I initially installed an outdated version of neovim distro (not compatible with plugins).
```{bash}
sudo apt remove neovim
sudo apt autoclean && sudo apt autoremove
apt-get update and upgrade.
sudo apt-get install build-essential make ripgrep unzip gcc xclip git xsel wslu fzf
sudo apt install tmux 
```

Install treesitter cli binary
```{bash}
wget https://github.com/tree-sitter/tree-sitter/releases/download/v0.22.6/tree-sitter-linux-x64.gz
gunzip tree-sitter-linux-x64.gz
chmod +x tree-sitter-linux-x64
mv tree-sitter-linux-x64 /usr/local/bin/tree-sitter
```
If you installed some treesitter libraries that you dont need, remove them from the treesitter.lua file and uninstall them using :TSUninstall {lang}.

Install nodejs
```{bash}
apt install npm
```
or from source 
```{bash}
wget https://nodejs.org/dist/latest/node-v22.5.1-linux-x64.tar.gz
tar xzvf node-v22.5.1-linux-x64.tar.gz
cd node-v22.5.1-linux-x64
export PATH=$PATH:~/node-v22.5.1-linux-x64/bin
```
This is required for the latex treesitter.

## Install neovim
Download most recent neovim release, decompress and create symbolic link.
```{bash}
curl -L -o nvim-linux64.tar.gz https://github.com/neovim/neovim/releases/download/stable/nvim-linux64.tar.gz
tar -xzvf nvim-linux64.tar.gz
sudo ln -s ~/nvim-linux64/bin/nvim /usr/local/bin/nvim
```
If you are working on a server that allows you to install software and the symbolic link is not pointing corretly, then you can edit your .bashrc file to create an alias to nvim.
If you have already downloaded and unzipped neovim previously, only the first two steps are required. Probably could setup a cron job to update automatically.
Run neovim command $nvim to confirm that "installation" was succesful. 


## Before cloning neovim configuration 
This neovim config is meant to be used with the my_config directory to manage my dotfiles and neovim configuration in one repository. (for now) 

This requires you to setup symbolic links from this repository to the ~/.config/nvim folder.
Create the my_config directory. Move the different files to the my_config directory then create the symbolic links. There is one example below. 
```{bash}
mkdir my_config
mv ~/.config/nvim ~/my_config/nvim
ln -s ~/my_config/nvim ~/.config/
```
Use git status to check that the files within the nvim directory are now part of the my_config directory. When first cloned, the nvim directory is treated as a submodule. This could be useful for some.

Run checkhealth to see errors for any plugins and run :Lazy and U to update plugins.

## Alternative vimrc file
I also have a vimrc file with a pretty minimal set of options enabled that I can use in my institution's linux cluster since I dont want to mess around with installing a lot of files to be able to use my neovim configuration there.
```{bash}
rm ~/.vimrc # if there is a file there
ln -s ~/my_config/dotfiles/vimrc ~/.vimrc
```

## Install quarto  
You can check the current version of quarto at the website but you can technically with any version. 
```{bash}
export QUARTO_VERSION="1.4.550"
sudo curl -o quarto.tar.gz -L "https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-amd64.tar.gz"
mkdir quarto/
sudo tar -xzvf quarto.tar.gz -C quarto/ # Adjust this line if you want. For example, to have different quarto installations.
~/quarto/quarto-"${QUARTO_VERSION}"/bin/quarto check # Reverify this line depending on how it extracted
sudo ln -s ~/quarto/quarto-${QUARTO_VERSION}/bin/quarto /usr/local/bin/quarto
```

The rest of the section is alternative distributions that can be used and some requirements for some plugins that need to be configured before they can work appropriately. 
I have not extensively tested the distributions below but from my quick impressions, the LazyNvim distribution seems to be the best out-of-the-box that balances completeness but also extensibility. 

## Install other requirements for full utilization of quarto and kickstart plugin
```{bash}
quarto install tinytex
sudo apt install python3-pip
python3 -m pip install jupyter
#sudo apt install r-base
sudo apt-get install kitty # Quick message when I run nvim shows that command cant be found. Dont know much about kitty yet.
sudo apt install imagemagick # Quick message said convert not found, which is part of imagemagick.
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash
source ~/.bashrc # Check by running $nvm
nvm install --lts
node --version
# Add to bashrc to make permanent
export PATH="$HOME/.local/bin:$PATH"
```

See 000_install_R_4.2.0.sh to install R 4.2.0 which is the R available in my institution's linux cluster.

## Install Pandoc 
Download and uncompress pandoc
1. Download using curl and uncompress using tar
```{bash}
mkdir pandoc/
curl -L -o pandoc.tar.gz https://github.com/jgm/pandoc/releases/download/3.2/pandoc-3.2-linux-amd64.tar.gz
tar -xvzf pandoc.tar.gz --strip-components=1 -C pandoc/
```
### Set up symbolic link 
2. Use sudo ln to create a symbolic link.
```{bash}
sudo ln -s ~/pandoc/bin/pandoc /usr/local/bin/pandoc
pandoc --version #Verify that it installed correctly
```

## Install dependencies 
3. Use apt-get to install different dependencies for conversion
```{bash}
sudo apt install texlive-fonts-recommended librsvg2-bin texlive-latex-recommended texlive-xetex texlive-latex-base
```

## Setup symbolic links for bashrc.
Remove all gz files that were downloaded when install quarto, nvim, R and pandoc.
```{bash}
# Remove any bashrc. Backup if necessary.
rm ~/.bashrc
sudo ln -s ~/my_config/dotfiles/bashrc ~/.bashrc
# I have a second for bashrc for when I work in linux cluster. Perform same action.
```
## Install zotero
Since I use windows, I just download and install it from their website (Zotero)[https://www.zotero.org/download/]
Zotero has limited storage for free members. I used dropbox and links to be able to have essentially unlimited storage. This can be changed to a hard drive or server but I havent tried to set this up.

## Awesome plugins for zotero 

Some of these are required for integration with neovim and quarto.
- [BetterBibtex](https://retorque.re/zotero-better-bibtex/)
- [Reading List](https://github.com/Dominic-DallOsto/zotero-reading-list)
- [Zoplicate](https://chenglongma.com/zoplicate/)
- [BetterNotes](https://github.com/windingwind/zotero-better-notes#readme)
- [Zotfile](https://github.com/jlegewie/zotfile)

I have some copies of the xpi files I used previously in my dropbox.
## Configure Zotero Settings
There are few modifications to the Zotero default settings.
### General Settings

- Appearance and Language: Set color scheme to dark. Language to automatic and Item Pane header to Title, Creator, Year
- File Handling:
Enable all three options in file handling. 
I usually allow snapshots for websites to grab htmls for blogs. Zotero7 supports html and epub annotation.
- File Renaming:
Enable automatic renaming to PDF and Ebook. Havent used zotero for other types of media.
Click 'Customize Filename Format':
Set Filename Template:
{{ authors name="family" join="_" max="1" suffix="_" replaceFrom="\s+" replaceTo="_" regexOpts="g" }}{{ year suffix="_" }}{{ title truncate="50" case="sentence" join="_" replaceFrom="\s+" replaceTo="_" regexOpts="g" }}
- Reader: Leave defaults.
- Locate: Leave defaults.
- Miscellaneous: Leave defaults.
- Groups: Leave defaults.

### Sync
I disable automatic syncing and link to my account. 
- File syncing: Enable and download at sync time.

### Export
- Quick Copy: Set item format to Chicago Manual of Style 17th edition full note. Set Note Format to Markdown + Rich Text and enable Include Zotero Links.

### Cite
Leave defaults. Install Microsoft Word add on if required.

### Advanced 
- Miscellaneous: Enable automatic check and report broken site translators.
- Files and Folders: 
Set base directory to 'C:\Users\Luis\Dropbox (MIT)\zotero-storage'
Set data directory to 'C:\Users\Luis\Zotero'

Choose the zotero storage folder of your choice in dropbox or other cloud storage provider. 
It should sync automatically for dropbox.

### Actions and Tags
Import the actions-zotero.yml from the my_config repository.

### Attanger
- Source path: Set Root directory to C:\Users\Luis\Downloads
- Attach Type: Set to Link.
- Destination Path: Set to C:\Users\Luis\Dropbox (MIT)\zotero-storage. Set subfolder to {{ authors name="family" join="_" max="1" }}. Leave parse forward slashes.
- Other settings: Leave enabled. Set 'Types of Attachments for Renaming/Moving' to 'pdf,doc,docx,txt,rtf,djvu,epub,html,mobi'

This an important plugin to circumvent storage issues.

### BetterBibtex
- Citation keys: Set Citation key formula to 'auth.fold + year'
Enable citation key search and force citation key to plain text.
Enable ignore upper/lowercase when comparing for uniqueness.
Keep keys unique across all libraries.
Set postfixed keys.
Enable BibLatex extended name and extract JSTOR from URL into eprint fields.
Leave others as default.

Refresh keys if necessary.

### Better Notes
- Basic: Enable 'take over opening note' and 'take over exporting notes'
- Note Editor: Enable show note linkes in outline, magic key to show command palette, use enhanced markdown paste.
- Sync: Leave as default.
- Template:
- Note from Annotaiton: Enable.

### Zoplicate
Set Action Preferences to Always Ask. Set Master Item Preferences to Earliest added and append duplicate counts.

### Zotero OCR
Set location to C:\Program Files\Tesseract-OCR\tesseract.exe
Set location to C:\Users\Luis\Desktop\poppler-24.02.0\Library\bin\pdftoppm.exe
Leave defaults forlanguage, dpi and segmentation mode.
Enable output to pdf with text layer, import resulting PDF as copy.

Test the configuration by running the plugin. If the resulting pdf has the text layer as is not corrupted, then enable overwrite PDF.

Useful for fixing some text overlays that mess with annotations.

## TODO
-[] Ensure all checks for quarto check are fulfilled or use wslview/w3m.

## Errors I encountered during installation

### Working with dropbox files
Ensure that when you are moving a file from dropbox, it is downloaded. If you move a file from dropbox using wsl and the file isnt downloaded, it essentially deletes the file.

### Tree-sitter r_language_server lsp

Mason was giving me errors during installation of the r-languageserver.
To see how I resolved the issue, look at the -- R r-languageserver section and 001_setupR directory from my lab_utils repository.
Briefly, I installed r-languageserver via R using install.packages() and then setup the r-languageserver by itself in the lsp.lua config file.
This way, Mason doesnt try to install it everytime I open Neovim.
