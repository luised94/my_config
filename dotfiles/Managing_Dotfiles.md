# Managing dotfiles
This is a way to have all dotfiles in a single directory that can be easily placed under version control and synchronized to other locations. I use a similar strategy for neovim.

### 2025-08-01
this is out of date although mostly correct but instead dotfiles is part of a git repository and I just sync via Github.

## Before beginning
This file assumes that you have set the windows_path variable in your .bashrc file.

## Initial synchronization
If you are starting from scratch, you can move to the next section. If you started to set up the dotifles in two different computers and it isnt snchronized, you need to send and receive the files from the destination to make sure all files are present in both directories before synchronizing. This ensures that no files are accidentally deleted. Run rsync in both directions. 

rsync -av --progress ~/dotfiles/ "${windows_path}dotfiles/"
rsync -av --progress "${windows_path}dotfiles/" ~/dotfiles/

## Setting up dotfiles management
1. Create a folder for your dotfiles. 

'''{bash}
cd ~
mkdir dotfiles
'''

2. Move any dotfiles to dotfiles folder and then create a symbolic link to the place where the file would be seen by the operating system. 
Note: Symbolic links have to be absolute paths.
'''{bash}
mv ~/.bashrc mv ~/dotfiles/bashrc
ln -s ~/dotfiles/bashrc ~/.bashrc
'''

3. Place folder under version control using your favorite version control software.
In this we use git. 

'''{bash}
cd ~/dotfiles/ 
git init 
'''

4. Use rsync to synchronize your folder to server or shared directory.
For now, I only know how to use dropbox. 
'''{bash}
rsync -av ~/dotfiles/ /mnt/c/Users/<username>/'Dropbox (MIT)'/dotfiles
'''

Use --dry-run option to see if syncing is correct.

5. Automate using cron jobs and scripts.

