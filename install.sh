#!/bin/bash
#
# install.sh - Install synps-mouse-led for non-Arch Linux distributions
# Supports: systemd, OpenRC, runit, sysvinit
#

set -e

KERNEL_VERSION=$(uname -r)
KERNEL_MAJOR=$(echo "$KERNEL_VERSION" | cut -d. -f1)
KERNEL_MINOR=$(echo "$KERNEL_VERSION" | cut -d. -f2)
INSTALL_PREFIX="${PREFIX:-/usr}"
MODULES_DIR="/lib/modules/$KERNEL_VERSION"
EXTRAMODULES_DIR="$MODULES_DIR/extramodules"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

check_root() {
	if [ "$(id -u)" -ne 0 ]; then
		error "This script must be run as root"
	fi
}

check_kernel() {
	if [ "$KERNEL_MAJOR" -lt 6 ] || ([ "$KERNEL_MAJOR" -eq 6 ] && [ "$KERNEL_MINOR" -lt 12 ]); then
		error "Kernel 6.12+ required. Current: $KERNEL_VERSION"
	fi
	info "Kernel version: $KERNEL_VERSION"
}

detect_init_system() {
	if [ -d /run/systemd/system ]; then
		echo "systemd"
	elif [ -x /sbin/openrc-run ]; then
		echo "openrc"
	elif [ -d /etc/runit ]; then
		echo "runit"
	elif [ -d /etc/init.d ]; then
		echo "sysvinit"
	else
		echo "unknown"
	fi
}

build_module() {
	info "Building psmouse kernel module..."

	# Download kernel source
	SRC_DIR=$(mktemp -d)
	cd "$SRC_DIR"

	info "Downloading kernel source for $KERNEL_VERSION..."
	if ! git archive --remote=git://repo.or.cz/linux.git "linux-${KERNEL_MAJOR}.${KERNEL_MINOR}.y" drivers/input/mouse | tar -x 2>/dev/null; then
		# Fallback: try to use kernel headers
		if [ -d "$MODULES_DIR/build" ]; then
			info "Using kernel headers from $MODULES_DIR/build"
			cp -r "$MODULES_DIR/build/drivers/input/mouse" .
		else
			error "Cannot find kernel source or headers"
		fi
	fi

	# Apply patch
	info "Applying kernel patch..."
	cd drivers/input/mouse
	patch -p1 -i "$SCRIPT_DIR/kernel.patch"

	# Build
	info "Compiling psmouse.ko..."
	if command -v clang &>/dev/null && [ -f "$MODULES_DIR/build/Makefile" ]; then
		make -C "$MODULES_DIR/build" M="$PWD" CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy psmouse.ko
	else
		make -C "$MODULES_DIR/build" M="$PWD" psmouse.ko
	fi

	# Compress
	xz -f psmouse.ko

	# Install
	info "Installing psmouse.ko.xz..."
	mkdir -p "$EXTRAMODULES_DIR"
	cp psmouse.ko.xz "$EXTRAMODULES_DIR/"
	depmod

	# Cleanup
	cd /
	rm -rf "$SRC_DIR"
}

install_daemon() {
	info "Installing synps-led-daemon..."

	# Compile daemon
	gcc -O2 -o synps-led-daemon "$SCRIPT_DIR/synps-led-daemon.c"
	install -D -m 0755 synps-led-daemon "$INSTALL_PREFIX/bin/synps-led-daemon"
	rm -f synps-led-daemon
}

install_service() {
	local init_system=$1
	info "Installing service for $init_system..."

	case "$init_system" in
		systemd)
			install -D -m 0644 "$SCRIPT_DIR/synps-led-daemon.service" \
				"$INSTALL_PREFIX/lib/systemd/system/synps-led-daemon.service"
			systemctl daemon-reload
			systemctl enable --now synps-led-daemon.service
			;;
		openrc)
			install -D -m 0755 "$SCRIPT_DIR/synps-led-daemon.openrc" \
				/etc/init.d/synps-led-daemon
			rc-update add synps-led-daemon default
			rc-service synps-led-daemon start
			;;
		runit)
			mkdir -p /etc/runit/sv/synps-led-daemon
			cp "$SCRIPT_DIR/synps-led-daemon.runit" /etc/runit/sv/synps-led-daemon/run
			chmod +x /etc/runit/sv/synps-led-daemon/run
			ln -sf /etc/runit/sv/synps-led-daemon /var/service/
			;;
		sysvinit)
			install -D -m 0755 "$SCRIPT_DIR/synps-led-daemon.sysvinit" \
				/etc/init.d/synps-led-daemon
			chmod +x /etc/init.d/synps-led-daemon
			update-rc.d synps-led-daemon defaults
			/etc/init.d/synps-led-daemon start
			;;
		*)
			warn "Unknown init system. Daemon installed but not enabled."
			warn "Run manually: /usr/bin/synps-led-daemon"
			;;
	esac
}

uninstall() {
	info "Uninstalling synps-mouse-led..."

	# Detect init system and stop service
	local init_system=$(detect_init_system)
	info "Detected init system: $init_system"

	case "$init_system" in
		systemd)
			systemctl disable --now synps-led-daemon.service 2>/dev/null || true
			rm -f "$INSTALL_PREFIX/lib/systemd/system/synps-led-daemon.service"
			systemctl daemon-reload
			;;
		openrc)
			rc-service synps-led-daemon stop 2>/dev/null || true
			rc-update del synps-led-daemon default 2>/dev/null || true
			rm -f /etc/init.d/synps-led-daemon
			;;
		runit)
			rm -f /var/service/synps-led-daemon 2>/dev/null || true
			rm -rf /etc/runit/sv/synps-led-daemon
			;;
		sysvinit)
			/etc/init.d/synps-led-daemon stop 2>/dev/null || true
			update-rc.d synps-led-daemon remove 2>/dev/null || true
			rm -f /etc/init.d/synps-led-daemon
			;;
	esac

	# Remove daemon
	rm -f "$INSTALL_PREFIX/bin/synps-led-daemon"

	# Remove module
	rm -f "$EXTRAMODULES_DIR/psmouse.ko.xz"
	depmod

	info "Uninstall complete."
}

# Main
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

case "${1:-install}" in
	install)
		check_root
		check_kernel

		# Detect init system FIRST before installing anything
		INIT_SYSTEM=$(detect_init_system)
		info "Detected init system: $INIT_SYSTEM"

		build_module
		install_daemon
		install_service "$INIT_SYSTEM"

		info "Installation complete!"
		info "Double-tap the LED button area to toggle the touchpad LED."
		;;
	uninstall)
		check_root
		uninstall
		;;
	*)
		echo "Usage: $0 {install|uninstall}"
		exit 1
		;;
esac
