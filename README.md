# diyar-os — ديار نظام التشغيل

> A modern Arabic-first Linux distribution built on Debian 12
> توزيعة لينكس عربية حديثة مبنية على ديبيان 12

---

## Repository structure

```
diyar-os/
├── auto/
│   ├── config              ← lb config parameters (architecture, mirror, packages)
│   ├── build               ← calls lb build
│   └── clean               ← calls lb clean
├── config/
│   ├── package-lists/
│   │   ├── 00-base.list.chroot       base system + kernel
│   │   ├── 01-desktop.list.chroot    XFCE4 + LightDM
│   │   ├── 02-arabic.list.chroot     fonts + IBus + shaping libs
│   │   ├── 03-installer.list.chroot  rsync, parted, grub (installer deps)
│   │   └── 04-apps.list.chroot       Firefox, LibreOffice, VLC
│   ├── hooks/live/
│   │   ├── 0010-vazirmatn-font.hook.chroot
│   │   ├── 0020-arabian-shield.hook.chroot
│   │   ├── 0030-diyar-installer.hook.chroot
│   │   ├── 0040-arabic-system.hook.chroot
│   │   ├── 0050-xfce4-desktop.hook.chroot
│   │   ├── 0060-lightdm.hook.chroot
│   │   └── 0099-cleanup.hook.chroot
│   └── archives/           (optional: custom apt repos)
├── scripts/
│   └── build.sh            master build entrypoint
└── README.md
```

---

## Build requirements

- Debian 12 (Bookworm) host machine **or** VM/container
- Root access
- ~20 GB free disk space
- Internet connection (downloads packages during build)
- RAM: 4 GB minimum, 8 GB recommended

---

## Quick build

```bash
# Install live-build
sudo apt-get install live-build debootstrap

# Clone both repos
git clone https://github.com/RiyadhNoori/diyar-os
git clone https://github.com/RiyadhNoori/diyar-installer

# Build
cd diyar-os
sudo bash scripts/build.sh

# Output: diyar-os-1.0-amd64.iso (~2-3 GB)
```

For a clean rebuild:
```bash
sudo bash scripts/build.sh --clean
```

---

## What the build produces

A hybrid ISO that:
- Boots as a **live session** (autologin as user `diyar`)
- Has the **Diyar Installer** desktop shortcut — click to install to HDD
- Supports **BIOS and UEFI** booting
- Ships with:
  - Arabian Shield rendering engine (`libarabian-shield.so`)
  - Vazirmatn + Amiri + Noto Arabic fonts
  - XFCE4 with full RTL layout
  - IBus Arabic input (`Alt+Shift` to toggle)
  - Firefox ESR with Arabic UI
  - LibreOffice with Arabic support

---

## Test the ISO

```bash
# In QEMU (fast, no USB needed)
qemu-system-x86_64 \
    -cdrom diyar-os-amd64.iso \
    -m 2048 \
    -enable-kvm \
    -vga virtio

# Write to USB
sudo dd if=diyar-os-amd64.iso of=/dev/sdX bs=4M status=progress
sync
```

---

## Hook execution order

| Hook | What it does |
|---|---|
| `0010` | Downloads + installs Vazirmatn font |
| `0020` | Builds `arabian-shield-linux-core` from source |
| `0030` | Installs `diyar-installer` into the live system |
| `0040` | Configures Arabic locale, keyboard, fontconfig |
| `0050` | Writes XFCE4 RTL configs into `/etc/skel` |
| `0060` | Configures LightDM greeter + autologin |
| `0099` | Strips build tools, cleans apt cache, rebuilds initramfs |

---

## Related repos

| Repo | Role |
|---|---|
| `arabian-shield-linux-core` | C library: FriBidi + Pango Arabic rendering |
| `diyar-installer` | rsync-based HDD installer (replaces Calamares) |
| `diyar-os` | This repo — live-build ISO configuration |

---

*ديار — وطن رقمي حقيقي*
