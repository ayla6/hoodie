# Fedora's default PATH omits ~/.local/bin; add it for user-installed tools
# (cargo, pipx, ...). Idempotent: fish_add_path persists it in fish_user_paths.
fish_add_path "$HOME/.local/bin"
