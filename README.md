# my_config

# Configuring neovim kickstart, quarto, and zotero
## If you installed using package manager and it was a outdated version 
I initially installed an outdated version of neovim distro (not compatible with plugins).
```{bash}
sudo apt remove neovim
sudo apt autoclean && sudo apt autoremove
apt-get update and upgrade.
sudo apt-get install build-essential make ripgrep unzip gcc xclip git xsel 
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
ln -s ~/my_config/nvim ~/.config/nvim
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

1. You can check the current version of quarto at the website but you can technically with any version. $export QUARTO_VERSION="1.4.550"
2. sudo curl -o quarto.tar.gz -L "https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-amd64.tar.gz"
3. mkdir quarto/
3. sudo tar -xzvf quarto.tar.gz -C quarto/ (Adjust this line if you want. For example, to have different quarto installations.)
4. quarto/quarto-"${QUARTO_VERSION}"/bin/quarto check (Reverify this line depending on how it extracted)


The rest of the section is alternative distributions that can be used and some requirements for some plugins that need to be configured before they can work appropriately. 
I have not extensively tested the distributions below but from my quick impressions, the LazyNvim distribution seems to be the best out-of-the-box that balances completeness but also extensibility. 

## Install other requirements for full utilization of quarto and kickstart plugin
1. $quarto install tinytex
2. $sudo apt install python3-pip
3. $python3 -m pip install jupyter
4. $sudo apt install r-base
5. sudo apt-get install kitty (Quick message when I run nvim shows that command cant be found. Dont know much about kitty yet.)
6. sudo apt install imagemagick (Quick message said convert not found, which is part of imagemagick.)
7. curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash
8. source ~/.bashrc (Check by running $nvm)
9. nvm install --lts (Check installation with $node --version)

## Install Pandoc 

 Download and uncompress pandoc
1. Download using curl and uncompress using tar
```{bash}
mkdir pandoc/
curl -L -o pandoc.tar.gz https://github.com/jgm/pandoc/releases/download/3.2/pandoc-3.2-linux-amd64.tar.gz
tar -xvzf pandoc.tar.gz --strip-components=1 -C pandoc/

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

## Configure Zotero Settings
There are few modifications to the Zotero default settings.
1. General Settings
I disable snapshots from web pages.

2. Sync
I disable automatic syncing and link to my account. 

3. Advanced 
Choose the zotero storage folder of your choice in dropbox or other cloud storage provider. 
It should sync automatically for dropbox.

4. BetterBibtex
I change citation key to auth.fold + year. 
Make sure to refresh keys. 

## Other useful command line utilities
```{bash}
sudo apt install tmux 
```
