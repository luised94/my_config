#!/usr/local/bin/R


SEARCH_DIRECTORY <- normalizePath(getwd())
DIRECTORY_DEPTH <- -1
EXCLUDED_DIRECTORIES <- c(
  ".git"
  ".venv"
  "build"
  "dist"
  "node_modules"
  "renv"
)
EXCLUDED_FILES <- c(
  ".Rprofile"
  ".bak"
  ".gitignore"
  ".log"
  ".swp"
  ".tmp"
  "renv.lock"
  "repository_aggregate.md"
)
