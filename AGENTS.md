# AGENTS.md

Guidance for AI agents working in this repository.

## Project

hoodie is a personal Fedora Atomic (bootc) desktop image with GNOME and KDE
flavors, built from one Containerfile. Base images are
`ghcr.io/ublue-os/silverblue-main:44` (GNOME) and `kinoite-main:44` (KDE).

## Key commands

- Build an image (requires podman 5+; `just` optional):
  `just build [hoodie] [stable] [gnome|kde]`
- Lint/format justfiles: `just check`, `just fix`
- Shellcheck/shfmt: `just lint`, `just format`
- Build VMs/ISOs: `just build-qcow2|build-raw|build-iso [hoodie] [stable] [flavor]`
- Run a VM: `just run-vm-qcow2 [..]`

Validate changed files with `bash -n build/*.sh`, `jq . packages.json
services.json`, and `just check`.

## Gotchas

- **No `FROM base-${ARG}` in podman.** The flavor's base image must be passed
  as a full `--build-arg BASE_IMAGE=...` value. The Justfile extracts it from
  the `ARG BASE_IMAGE_GNOME|KDE="..."` line in the Containerfile — keep those
  ARGs as the single source of truth (Renovate bumps the pinned digests).
- **MOK keys**: the kernel is `sbsign`ed and NVIDIA kmod `kmodsign`ed in the
  image with keys under `/etc/pki/akmods/`. Builds receive the stable private
  key via the `mokkey` build secret (`--secret id=mokkey,src=<file>` /
  `MOK_PRIVATE_KEY_PATH`). Without it, a fresh key is generated (re-enrollment
  needed). Never add private keys to the repo; `cosign.key`/`cosign.pub` are
  gitignored.
- **Versionlocks**: mesa/libva/ffmpeg-ish codecs are distro-synced and locked
  in `build/02-fedora-packages.sh` so the CachyOS kernel's userland matches.
- **NVIDIA is Maxwell (MX130)** → the R580 final legacy driver
  (`akmod-nvidia-580xx`), not the current branch. ublue's akmods cache does not
  build it, so it is compiled during the build against the CachyOS kernel.
- **Flavor plumbing**: `packages.json`, `services.json`, `flatpaks/`,
  `ujust/`, and `files/` all support a `main` layer plus per-flavor
  (`gnome`/`kde`) layers. `files/<variant>/` is rsynced to `/`; ujust recipes
  are concatenated into `/usr/share/ublue-os/just/60-custom.just`; flatpak
  preinstalls live at `flatpaks/<variant>.preinstall`.
- **Images tags**: gnome ships unsuffixed (`hoodie:stable`), kde as
  `hoodie-kde:stable` — set via `IMAGE_FLAVOR`.
- **CachyOS swap**: done in `build/01-kernel.sh` via `rpm-ostree override
  remove kernel* --install kernel-cachyos ... --devel-matched`; the
  `-devel-matched` package is the akmod compile target. Must run before
  `build/04-nvidia.sh`.
