## Introduction
Creating a neovim configuration from scratch. The main purpose is to learn about neovim, lua, plugins, etc. At the end, it should be a personal configuration. 
My main requirements are: Writing, R and bash programming, Zotero, Quarto, Markdown. 
I started using the kickstart configuration as a stable config. I decided to set up a configuration "from scratch", referencing popular distribution, to get a better sense of configuring neovim and its plugins. Most of my setup derives from kickstart and other more popular distributions. 

## Installation 
Reference the neovim-config.md file to see how neovim was installed.

To install this configuration:
```{bash}
git clone -b feature/nvim-from-scratch https://github.com/luised94/my_config.git
```

## Description
### Version 1 
Very simple configuration. Mostly copy pasted from kickstart. 
- Core 
keymaps.lua
options.lua
Configure keymaps and options. Some plugin-specific keymaps are found with the plugins.

- lazy-bootstrap and plugins
lazy-bootstrap.lua configures lazy.nvim which is the plugin manager. This file also loads all files found in the plugins directory. These files must return a table with configuration settings. They should be self-contained. This can be verified by commenting all of the lines of each file and reopening neovim.

1. autocompletion.lua

2. autopairs.lua
Autopair brackets, parenthesis and quotes.

3. breaking_bad_habits.lua
Contains two plugins that helps delevop better vim habits, hardtime and precognition.

4. colorscheme.lua

5. dashboard.lua
Could serve as the file to place dashboard settings but currently has a funny plugin, btw.nvim.

6. lsp.lua

7. telescope.lua

8. treesitter.lua

9. which-key.lua

## TODO
* Figure out how to specify how to git clone the specific nvim folder without cloning the my_config repository.
* Configure setup for R.
* Configure setup for bash.
* Configure setup for Zotero and citations.
* Configure setup for quarto. 
* Setup for multiple files and navigation.
* Configure any writing settings
* Integration with Tmux. 

## References 
[Kickstart Neovim](https://github.com/nvim-lua/kickstart.nvim)
[Teaching Neovim From Scratch To A Noob](https://www.youtube.com/watch?v=-ybCiHPWKNA)
[The Only Video You Need to Get Started with Neovim ](https://www.youtube.com/watch?v=m8C0Cq9Uv9o&t=1s)
[0 to LSP : Neovim RC From Scratch](https://www.youtube.com/watch?v=w7i4amO_zaE)
[From 0 to IDE in NEOVIM from scratch | FREE COURSE // EP 1](https://www.youtube.com/watch?v=zHTeCSVAFNY)
