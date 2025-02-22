---
title: Installing lua5.1
---

We install lua5.1 because 5.1 is the version used in neovim. Most of my use of lua will be configuring neovim.

```{bash}
wget https://lua.org/ftp/lua-5.1.5.tar.gz
tar -xf lua-5.1.5.tar.gz
rm lua-5.1.5.tar.gz
cd lua-5.1.5/
make local
make linux install
~/lua-5.1.5/bin/lua --help
```
