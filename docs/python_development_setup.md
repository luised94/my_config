---
title: Python development setup on wsl
---
DATE UPDATED: 2025-05-15

# Introduction

This file documents the tools I use to work with python. I went with uv since it seemed to provide the most comprehensive tooling. Uv can call ruff and ty as well.

```{bash}
curl -LsSf https://astral.sh/uv/install.sh | sh
uv --version
# You can use ruff and ty via uv
uvx ruff --version
uvx ty --version
```

Use uv for virtual environment management.
