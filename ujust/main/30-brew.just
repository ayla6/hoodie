# vim: set ft=make :

# Install the Homebrew packages declared in the image Brewfile
[group("System")]
brew-bundle:
    #!/usr/bin/bash
    if ! command -v brew &>/dev/null; then
        echo "Homebrew is not installed on this system."
        exit 1
    fi
    brew bundle --file /usr/share/ublue-os/homebrew/Brewfile

# Install one or more packages via Homebrew
[group("System")]
brew-install packages="":
    #!/usr/bin/bash
    if ! command -v brew &>/dev/null; then
        echo "Homebrew is not installed on this system."
        exit 1
    fi
    if [[ -z "{{ packages }}" ]]; then
        echo "Usage: ujust brew-install <package> [package...]"
        exit 1
    fi
    brew install {{ packages }}
