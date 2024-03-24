# Configuring neovim kickstart, quarto, and zotero
## If you installed using package manager and it was a outdated version 
1. sudo apt remove neovim
2. sudo apt autoclean && sudo apt autoremove
3. Run $apt-get update and upgrade.
4. Run $sudo apt-get install build-essential.
## Install quarto  

1. You can check the current version of quarto at the website but you can technically with any version. $export QUARTO_VERSION="1.4.550"
2. sudo curl -o quarto.tar.gz -L "https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-amd64.tar.gz"
3. sudo tar -xzf quarto.tar.gz -C /opt/ (Adjust this line if you want. For example, to have different quarto installations.)
4. /opt/quarto-"${QUARTO_VERSION}"/bin/quarto check (Reverify this line depending on how it extracted)


## Install the neovim and quarto kickstarter 
1. curl -L -o nvim-linux64.tar.gz https://github.com/neovim/neovim/releases/download/stable/nvim-linux64.tar.gz (Follow redirects and name of output file)
2. Run tar xzvf nvim-linux64.tar.gz. Run ./nvim-linux64/bin/nvim to check that it works. 
3. Make directory for kickstart config. mkdir -p ~/.config/nvim
4. If you installed the previous kickstart.nvim config, run rm -rf ~/.config/nvim to delete the lua configurations.
5. Remake the directory. $mkdir -p ~/.config/nvim
6. Run $git clone https://github.com/jmbuhr/quarto-nvim-kickstarter.git ~/.config/nvim
7. Run nvim and it should install. 
8. Create the symbolic links. 
$sudo ln -s ~/nvim-linux64/bin/nvim /usr/local/bin/nvim
$sudo ln -s /opt/quarto-${QUARTO_VERSION}/bin/quarto /usr/local/bin/quarto

## Optional: Install other requirements for full utilization of quarto and kickstart plugin
1. $quarto install tinytex
2. $sudo apt install python3-pip
3. $python3 -m pip install jupyter
4. $sudo apt install r-base
5. sudo apt-get install kitty (Quick message when I run nvim shows that command cant be found. Dont know much about kitty yet.)
6. sudo apt install imagemagick (Quick message said convert not found, which is part of imagemagick.)
7. curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash
8. source ~/.bashrc (Check by running $nvm)
9. nvm install --lts (Check installation with $node --version)
Tested: 2024_02_22

## Alternative: Install kickstart.nvim
1. git clone https://github.com/nvim-lua/kickstart.nvim.git ~/.config/nvim (Can probably use git clone command as well.)
2. Run nvim and it should install. It should be apparent that it worked from how the menu looks. You should write on a file and see snippet to ensure that kickstart worked. 
3. sudo ln -s ~/nvim-linux64/bin/nvim /usr/local/bin/nvim

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
