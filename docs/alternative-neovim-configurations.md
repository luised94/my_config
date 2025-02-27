# Introduction 
If you do not want to configure neovim yourself, you can use any of the popular distributions available on github.

## Install kickstart.nvim
1. git clone https://github.com/nvim-lua/kickstart.nvim.git ~/my_config/ (Can probably use git clone command as well.)
2. Run nvim and it should install. It should be apparent that it worked from how the menu looks. You should write on a file and see snippet to ensure that kickstart worked. 
3. Clean up the neovim kickstart.nvim cloned repo so that it gets included into the git repository.
```{bash}
cd ~/my_config/nvim
rm -rf .git
rm .gitignore
git rm --cached ~/my_config/nvim/
git status
git add .
```

## Alternative: Install the quarto kickstarter 
```{bash}
#1. Remake the directory.
mkdir -p ~/.config/nvim
#2. Clone
git clone https://github.com/jmbuhr/quarto-nvim-kickstarter.git ~/.config/nvim
#3. Run nvim and it should install.
#4. Create the symbolic links 
sudo ln -s /opt/quarto-${QUARTO_VERSION}/bin/quarto /usr/local/bin/quarto
```

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
```{bash}
git clone https://github.com/pgosar/CyberNvim ~/.config/nvim
mkdir -pv ~/.config/nvim/lua/user
cp ~/.config/nvim/lua/example_user_config.lua ~/.config/nvim/lua/user/user_config.lua
```

## Download alternative distributions for inspection and copy/pasting
I also cloned the distros so I can look at the for inspiration.
1. git clone https://github.com/pgosar/CyberNvim ~/neovim-distros
2. git clone https://github.com/jmbuhr/quarto-nvim-kickstarter.git ~/neovim-distro
3. git clone https://github.com/LazyVim/starter ~/neovim-distro

