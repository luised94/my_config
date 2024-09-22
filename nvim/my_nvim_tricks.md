# Introduction
Some moves and commands that I use in neovim.

## Working with multiple files in a project

Use a find command to search for files then pass to neovim with process substitution. 
```{bash}
nvim $(find . -type f -name "*.lua")
```
Then all files will be opened in the buffer and you can use fzf/telescope to search the files. 
There are also commands such as next and prev to move between buffers and the b[count] to move to a particular buffer.
