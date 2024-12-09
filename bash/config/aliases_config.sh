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
    "ga=git add"
    "gb=git branch"
    "gm=git merge --no-ff"
    "grm=git rebase main"
    "gc=git commit"
    "gps=git push"
    "gpl=git pull"
    "gl=git log --oneline --graph --decorate"
)
