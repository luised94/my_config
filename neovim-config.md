# Configuring neovim kickstart, quarto, and zotero
## If you installed using package manager and it was a outdated version 
1. sudo apt remove neovim
2. sudo apt autoclean && sudo apt autoremove
3. Run $apt-get update and upgrade.
4. Run $sudo apt-get install build-essential.

## Install neovim
Download most recent neovim release, decompress and create symbolic link.
```{bash}
curl -L -o nvim-linux64.tar.gz https://github.com/neovim/neovim/releases/download/stable/nvim-linux64.tar.gz
tar -xzvf nvim-linux64.tar.gz
sudo ln -s ~/nvim-linux64/bin/nvim /usr/local/bin/nvim
```
Run neovim command $nvim to confirm that "installation" was succesful. 
## Before cloning neovim configuration 
This neovim config is meant to be used with the my_config directory to manage my dotfiles and neovimconfiguration in one repository. (for now) 

This requires you to setup symbolic links from this repository to the ~/.config/nvim folder.
Create the my_config directory. Move the different files to the my_config directory then create the symbolic links. There is one example below. 
```{bash}
mkdir my_config
mv ~/.config/nvim ~/my_config/nvim
ln -s ~/my_config/nvim ~/.config/nvim
```
## Install kickstart.nvim
1. git clone https://github.com/nvim-lua/kickstart.nvim.git ~/my_config/ (Can probably use git clone command as well.)
2. Run nvim and it should install. It should be apparent that it worked from how the menu looks. You should write on a file and see snippet to ensure that kickstart worked. 

## Install quarto  

1. You can check the current version of quarto at the website but you can technically with any version. $export QUARTO_VERSION="1.4.550"
2. sudo curl -o quarto.tar.gz -L "https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-amd64.tar.gz"
3. sudo tar -xzf quarto.tar.gz -C /opt/ (Adjust this line if you want. For example, to have different quarto installations.)
4. /opt/quarto-"${QUARTO_VERSION}"/bin/quarto check (Reverify this line depending on how it extracted)

The rest of the section is alternative distributions that can be used and some requirements for some plugins that need to be configured before they can work appropriately. 
I have not extensively tested the distributions below but from my quick impressions, the LazyNvim distribution seems to be the best out-of-the-box that balances completeness but also extensibility. 

## Alternatives: Install other requirements for full utilization of quarto and kickstart plugin
1. $quarto install tinytex
2. $sudo apt install python3-pip
3. $python3 -m pip install jupyter
4. $sudo apt install r-base
5. sudo apt-get install kitty (Quick message when I run nvim shows that command cant be found. Dont know much about kitty yet.)
6. sudo apt install imagemagick (Quick message said convert not found, which is part of imagemagick.)
7. curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash
8. source ~/.bashrc (Check by running $nvm)
9. nvm install --lts (Check installation with $node --version)

## Alternative: Install the quarto kickstarter 
1. Remake the directory. $mkdir -p ~/.config/nvim
2. Run $git clone https://github.com/jmbuhr/quarto-nvim-kickstarter.git ~/.config/nvim
3. Run nvim and it should install. 
4. Create the symbolic links. 
$sudo ln -s /opt/quarto-${QUARTO_VERSION}/bin/quarto /usr/local/bin/quarto

## Alternative: Install lazy.nvim
1. Back up files and clone the starter. 

```{bash}
mv ~/.config/nvim{,.bak}
mv ~/.local/share/nvim/{,.bak}
mv ~/.local/state/nvim/{,.bak}
mv ~/.cache/nvim/{,.bak}
git clone https://github.com/LazyVim/starter ~/.config/nvim
rm -rf ~/.config/nvim/.git
sudo apt install ripgrep
nvim
```
## Alternative: Install CyberNvim
1. Back up files as before.
'''{bash}
git clone https://github.com/pgosar/CyberNvim ~/.config/nvim
mkdir -pv ~/.config/nvim/lua/user
cp ~/.config/nvim/lua/example_user_config.lua ~/.config/nvim/lua/user/user_config.lua

## Download alternative distributions for inspection and copy/pasting
1. git clone https://github.com/pgosar/CyberNvim ~/.config/cyber_nvim 
2. git clone https://github.com/jmbuhr/quarto-nvim-kickstarter.git ~/.config/quarto_nvim
3. git clone https://github.com/LazyVim/starter ~/.config/lazy_nvim

## Other useful command line utilities

1. sudo apt install tmux visidata
