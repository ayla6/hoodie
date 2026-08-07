# hoodie

A personal Fedora Atomic (bootc) desktop image built on
[ublue-os main](https://github.com/ublue-os/main) Silverblue/Kinoite, with the
[CachyOS kernel](https://github.com/CachyOS) baked in, a self-signed Secure Boot
(MOK) key, the legacy NVIDIA 580xx driver for an MX130, and a curated set of
gaming and development tooling.

## Variants

| Flavor | Image | Base |
| --- | --- | --- |
| GNOME (default) | `ghcr.io/ayla6/hoodie:stable` | `ghcr.io/ublue-os/silverblue-main:44` |
| KDE | `ghcr.io/ayla6/hoodie-kde:stable` | `ghcr.io/ublue-os/kinoite-main:44` |

## What's included

- **CachyOS kernel** (BORE scheduler, 1000Hz), installed via `rpm-ostree
  override` and signed with the hoodie MOK key.
- **Secure Boot**: the kernel is `sbsign`ed and the NVIDIA module is
  `kmodsign`ed with the same key (`/etc/pki/akmods/`). Enroll once with
  `ujust enroll-secure-boot-key`. The private key is never shipped in the
  image; builds pass it as the `mokkey` build secret. The public key lives in
  the repo as [`secure_boot.der`](secure_boot.der) — enroll it before
  installation with:

  ```sh
  sudo mokutil --timeout -1
  sudo mokutil --import secure_boot.der
  ```

  Enter `hoodie` if prompted for a password.
- **NVIDIA 580xx** (Maxwell) driver with power management, Flatpak runtime sync,
  and a legacy-hardware helper.
- **Gaming**: Steam, gamescope Wayland session, mangohud, vkBasalt,
  umu-launcher, vulkan-tools.
- **Performance**: zram (lz4) at 100% of RAM, tuned sysctls, kyber/bfq IO
  schedulers, GPU-reset udev rules, memlock for gamescope, beesd BTRFS
  dedupe timer, systemd-oomd.
- **Keyboard**: Colemak-DH Wide ISO set as the default layout on both desktops
  (GNOME dconf, KDE kxkbrc). The stock layout already ships the AltGr accent
  layer. input-remapper (with the 8BitDo controller) for remapping.
- **Display color**: the HDMI port lives on the Intel iGPU — `ujust rgb-full`
  forces full RGB range (X11) to fix washed-out colors.
- **Development**: fish + fcitx5, Tailscale, Syncthing, Homebrew (see
  Brewfile), Rust/Nix via `ujust install-rust` / `ujust install-nix`,
  distrobox, neovim, and friends.
- **Apps**: Flathub-only (Fedora repos are removed on first boot); curated
  preinstalls in `flatpaks/`.

## Install

Build the ISO (or download a release) and boot it:

```sh
just build-iso        # gnome
just build-iso hoodie stable kde
```

Or rebase an existing Fedora Atomic system:

```sh
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/ayla6/hoodie:stable
sudo systemctl reboot
```

## Building locally

Requirements: podman (5+), just, and optionally a MOK private key file.

```sh
just build            # hoodie:stable (gnome)
just build hoodie stable kde   # hoodie-kde:stable
MOK_PRIVATE_KEY_PATH=./secure_boot.key just build
```

To test inside a VM or produce install media, see `just --list` for
`build-qcow2`, `build-raw`, `build-iso`, and the `run-vm-*` recipes.

## Repository layout

```
Containerfile        # flavor-aware build, base digests pinned here
Justfile             # build / test / VM tooling
hoodie.env           # image name, flavor, default tag
build/               # numbered build steps (01-kernel … 09-cleanup)
files/main|gnome|kde # overlay tree, rsynced into the image
flatpaks/            # first-boot Flathub preinstalls, per flavor
ujust/main/          # just recipes installed as `ujust`
iso/                 # BIB kickstart + disk configs
packages.json        # per-flavor dnf package lists
services.json        # per-flavor systemd unit enablement
```

The two variants are built by the same Containerfile; the `IMAGE_FLAVOR`
build-arg and the per-flavor `BASE_IMAGE` ARG select the base and the overlays.

## CI

`.github/workflows/build.yml` builds and pushes both flavors on a schedule and
on merge. It needs two repository secrets:

- `SIGNING_SECRET` — the Cosign private key (image signatures).
- `MOK_PRIVATE_KEY` — the PEM private key used to sign the kernel/NVIDIA
  module. If unset, builds generate a throwaway key (you'd have to re-enroll).

`.github/workflows/build-disk.yml` builds ISOs and qcow2 images on demand.
