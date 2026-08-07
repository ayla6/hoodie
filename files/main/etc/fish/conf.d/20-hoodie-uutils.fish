# Use uutils-coreutils (Rust) as the interactive replacements for the GNU
# coreutils. Only external commands are shadowed: fish builtins (cd, echo,
# printf, pwd, test, true, false, ...) keep their native implementation.
if type -q uu_ls
    set -l skip cd '[' echo printf pwd test true false
    for uu in /usr/bin/uu_*
        set -l name (path basename $uu | string replace -r '^uu_' '')
        if contains -- $name $skip
            continue
        end
        function $name --inherit-variable=uu --inherit-variable=name
            command $uu $argv
        end
    end
end
