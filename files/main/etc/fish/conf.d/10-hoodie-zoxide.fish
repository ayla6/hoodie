# zoxide: fuzzy "cd". Bound to cd (--cmd cd) so muscle memory still works;
# cd .. / cd /abs/path still behave like builtin cd, cd <fuzzy> jumps.
if type -q zoxide
    zoxide init fish --cmd cd | source
end
