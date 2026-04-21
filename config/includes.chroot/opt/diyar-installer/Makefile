# =============================================================================
# Diyar Installer — Makefile
# =============================================================================

PREFIX        ?= /usr/local
SBIN          := $(PREFIX)/sbin
LIBDIR        := $(PREFIX)/lib/diyar-installer
CONFDIR       := /etc/diyar-installer
DESKTOP_DIR   := /usr/share/applications

INSTALLER_DIR := $(CURDIR)

.PHONY: install uninstall check

install:
	@echo "[INSTALL] Installing Diyar Installer..."
	install -d $(SBIN)
	install -d $(LIBDIR)/core
	install -d $(LIBDIR)/ui
	install -d $(LIBDIR)/hooks/post-install
	install -d $(LIBDIR)/conf
	install -d $(CONFDIR)

	# Core engine
	install -m755 core/engine.sh       $(LIBDIR)/core/engine.sh
	install -m644 core/disk.sh         $(LIBDIR)/core/disk.sh
	install -m644 core/chroot_setup.sh $(LIBDIR)/core/chroot_setup.sh
	install -m644 core/log.sh          $(LIBDIR)/core/log.sh

	# UI
	install -m755 ui/diyar-installer   $(LIBDIR)/ui/diyar-installer

	# Hooks
	install -m755 hooks/post-install/01-arabic-setup.sh \
	              $(LIBDIR)/hooks/post-install/

	# Config
	install -m644 conf/installer.conf  $(CONFDIR)/installer.conf

	# Entrypoint symlink
	ln -sf $(LIBDIR)/ui/diyar-installer $(SBIN)/diyar-installer

	# Desktop launcher
	install -m644 diyar-install.desktop $(DESKTOP_DIR)/

	@echo "[OK] Diyar Installer installed → $(SBIN)/diyar-installer"

uninstall:
	rm -f  $(SBIN)/diyar-installer
	rm -rf $(LIBDIR)
	rm -f  $(DESKTOP_DIR)/diyar-install.desktop
	@echo "[OK] Diyar Installer removed."

check:
	@echo "Checking dependencies..."
	@for cmd in rsync parted mkfs.ext4 grub-install blkid whiptail; do \
	    command -v $$cmd &>/dev/null \
	        && echo "  [OK] $$cmd" \
	        || echo "  [MISSING] $$cmd"; \
	done
