# vim: set ft=make :

# Install the Nix package manager via the Determinate installer
[group("Development")]
install-nix:
    #!/usr/bin/bash
    if command -v nix &>/dev/null; then
        echo "Nix is already installed."
        exit 0
    fi
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
        | sh -s -- install --no-confirm

# Install Rust via rustup (with rust-analyzer)
[group("Development")]
install-rust:
    #!/usr/bin/bash
    if ! command -v rustup &>/dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
            | sh -s -- -y --profile default
    fi
    rustup component add rust-analyzer
    echo "Rust toolchain installed. Source ~/.cargo/env to use it."

# Set fish as the default shell for the current user
[group("Development")]
set-fish-default:
    #!/usr/bin/bash
    if ! command -v fish &>/dev/null; then
        echo "fish is not installed on this system."
        exit 1
    fi
    sudo chsh -s "$(command -v fish)" "$USER"
    echo "fish set as the default shell. Re-login to take effect."
