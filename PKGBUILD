# Maintainer: Matthew Monaco <cx monaco dgbaley27>
#             Ivan           <vantu5z@mail.ru>

# http://kernel.opensuse.org/cgit/kernel-source/
# http://kernel.opensuse.org/cgit/kernel-source/commit/patches.drivers?id=940e57e2c66093f6fee481ab4224dd4294e3793f
# https://bugzilla.novell.com/768506
# https://bugzilla.novell.com/765524

_kver=6.19
_gitroot=git://repo.or.cz/linux.git
_gitcommit=linux-$_kver.y
_cur_kernel="$(uname -r)"
_EXTRAMODULES=$(readlink -f /usr/lib/modules/"$_cur_kernel/extramodules")

pkgname=synps-mouse-led
pkgver=$_kver
pkgrel=1
arch=(i686 x86_64)
license=(GPL2)
url="https://github.com/piratheon/synps-mouse-led"
pkgdesc="Synaptics LED enabled psmouse kernel module with touchpad toggle daemon"
depends=('glibc')
optdepends=('linux>=6.19: standard kernel'
            'linux-cachyos>=6.19: CachyOS kernel'
            'linux-zen>=6.19: Zen kernel'
            'linux-lts>=6.19: LTS kernel'
            'linux-cachyos-lts>=6.19: CachyOS LTS kernel')
makedepends=('git')
install="$pkgname.install"

source=(
	SHA256SUMS
	"$pkgname.install"
	kernel.patch
	synps-led-daemon.c
	synps-led-daemon.service
	synps-led-daemon.openrc
	synps-led-daemon.runit
	synps-led-daemon.sysvinit
	install.sh
)

sha256sums=('SKIP'
            'SKIP'
            '08ed5a16acf218b4c2263b2db44053c8dcca9fca9777902c5f0ba75b9aa603e2'
            'SKIP'
            'SKIP'
            'SKIP'
            'SKIP'
            'SKIP'
            'SKIP')

build() {
	msg2 "Module will be installed to: $_EXTRAMODULES"

	msg2 "Getting source from $_gitroot"
	cd "${srcdir}"
	git archive --remote="$_gitroot" "$_gitcommit" drivers/input/mouse | tar -x

	msg2 "Patching source"
    cd "${srcdir}"
	for p in ../*.patch; do
      msg2 "Applying patch: $p"
      patch -p1 -i "$p"
    done

	msg2 "Building psmouse.ko"
	cd "drivers/input/mouse"
	make -C "/usr/lib/modules/$_cur_kernel/build" M="$PWD" CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy psmouse.ko

	msg2 "Compressing psmouse.ko.xz"
	xz -f psmouse.ko
}

package() {
	cd "${srcdir}/drivers/input/mouse"

	install -D -m 0644 psmouse.ko.xz "${pkgdir}/${_EXTRAMODULES}/psmouse.ko.xz"

	# Compile and install LED toggle daemon
	gcc -O2 -o synps-led-daemon "${srcdir}/synps-led-daemon.c"
	install -D -m 0755 synps-led-daemon "${pkgdir}/usr/bin/synps-led-daemon"

	# Install systemd service
	install -D -m 0644 "${srcdir}/synps-led-daemon.service" "${pkgdir}/usr/lib/systemd/system/synps-led-daemon.service"

	# Install OpenRC service
	install -D -m 0755 "${srcdir}/synps-led-daemon.openrc" "${pkgdir}/etc/init.d/synps-led-daemon"

	# Install runit service
	install -D -m 0755 "${srcdir}/synps-led-daemon.runit" "${pkgdir}/etc/runit/sv/synps-led-daemon/run"

	# Install sysvinit service
	install -D -m 0755 "${srcdir}/synps-led-daemon.sysvinit" "${pkgdir}/etc/init.d/synps-led-daemon-sysvinit"

	# Install standalone install script for non-Arch users
	install -D -m 0755 "${srcdir}/install.sh" "${pkgdir}/usr/share/synps-mouse-led/install.sh"

	# if you have not one kernel installed and _EXTRAMODULES not proper detected:
	# you should change install string for EXTRAMODULES manualy:
	# install -D -m 0644 psmouse.ko.xz "${pkgdir}/usr/lib/modules/{YOUR_EXTRAMODULES_DIR}/psmouse.ko.xz"
}
