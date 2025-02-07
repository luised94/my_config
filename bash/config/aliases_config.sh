# Standard aliases
BASIC_ALIASES=(
    "ll=ls -alF"
    "la=ls -A"
    "l=ls -CF"
    "R=R --no-save"
    "explorer=explorer.exe ."
)

# Git aliases
GIT_ALIASES=(
    "gs=git status"
    "gd=git diff"
    "ogd=nvim < <(git diff)"
    "ogdc=nvim < <(git diff --cached)"
    "ogda=nvim < <(git diff HEAD)"
    "ga=git add"
    "gb=git branch"
    "gm=git merge"
    "gmnff=git merge --no-ff"
    "gc=git commit"
    "gco=git checkout"
    "gcb=git checkout -b"
    "grm=git rebase main"
    "gps=git push"
    "gpl=git pull"
    "gl=git log --oneline --graph --decorate"
    "gfap=git fetch --all --prune"
    "gitstart=git fetch --all --prune && git status && git pull && git rebase main && echo [X] Git workspace ready for coding!'"
    "syncall=sync_all_branches"
)

LABUTILS_ALIASES=(
    "edit_bmc_configs=nvim ~/data/*Bel/documentation/*_bmc_config.R ~/lab_utils/core_scripts/template_bmc_config.R ~/lab_utils/core_scripts/bmc_config.R"
)
