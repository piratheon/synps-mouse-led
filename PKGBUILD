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
)

sha256sums=('5c240c5a291f96d35dd1f43e46acb80591f7eda70733958000faccf1434b2791'
            'c635cc3b1d13695a0d650e3da0c0794efd97cd3402120425c4a18aaeabff7ae5'
            'f83d59206344448e5fe3ce57e72660eb8daef26ca7a64b392c7f810faf0c55e4'
            '65a414290d3168ea489775391d6492b67963d2cb41eea18dc57966a4254e360e'
            'cd3bb83bb87a775d9faf21be065d9f8ebf389a7c11b8c8d2f0b4360f0c6b505f')

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

	# if you have not one kernel installed and _EXTRAMODULES not proper detected:
	# you should change install string for EXTRAMODULES manualy:
	# install -D -m 0644 psmouse.ko.xz "${pkgdir}/usr/lib/modules/{YOUR_EXTRAMODULES_DIR}/psmouse.ko.xz"
}
