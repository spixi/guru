# Copyright 2024-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit xdg toolchain-funcs

SP_VER="2024-10-27"

DESCRIPTION="A turn-based survival game set in a post-apocalyptic world"
HOMEPAGE="https://cataclysmdda.org
	https://github.com/CleverRaven/Cataclysm-DDA"
if [[ ${PV} == 9999 ]]; then
	inherit git-r3
	EGIT_REPO_URI="https://github.com/CleverRaven/Cataclysm-DDA.git"
	SLOT="${PV}"
else
	v2="$(ver_cut 2)"
	MY_PV="$(ver_cut 1).${v2^^}"
	unset v2
	SRC_URI="
		https://github.com/CleverRaven/Cataclysm-DDA/archive/${MY_PV}-RELEASE.tar.gz -> ${P}.tar.gz
		soundpack? (
			https://github.com/Fris0uman/CDDA-Soundpacks/releases/download/${SP_VER}/CC-Sounds.zip -> ${P}-soundpack.zip
		)
	"
	SLOT="${MY_PV}"
	S="${WORKDIR}/Cataclysm-DDA-${MY_PV}-RELEASE"
	KEYWORDS="~amd64"
fi

LICENSE="CC-BY-SA-3.0 Apache-2.0 BSD soundpack? ( CC-BY-SA-4.0 ) MIT OFL-1.1 Unicode-3.0"
IUSE="debug doc ncurses nls +sound +soundpack test +tiles"
REQUIRED_USE="soundpack? ( sound ) sound? ( tiles ) \
	|| ( tiles ncurses )"
RESTRICT="!test? ( test )"

RDEPEND="
	sys-libs/zlib
	ncurses? ( sys-libs/ncurses )
	tiles? (
		media-libs/libsdl2[video]
		media-libs/sdl2-image[png]
		media-libs/sdl2-ttf[harfbuzz]
		sound? (
			   media-libs/libsdl2[sound]
			   media-libs/sdl2-mixer[vorbis]
		)
	)"
DEPEND="${RDEPEND}"
BDEPEND="
	doc? ( app-text/doxygen[dot] )
	nls? ( sys-devel/gettext )
	"

[[ ${PV} != 9999 ]] && BDEPEND+=" soundpack? ( app-arch/unzip )"

src_unpack() {
	if [[ ${PV} == 9999 ]]; then
		git-r3_src_unpack

		if use soundpack; then
			git-r3_fetch https://github.com/Fris0uman/CDDA-Soundpacks
			git-r3_checkout https://github.com/Fris0uman/CDDA-Soundpacks "${WORKDIR}/CDDA-Soundpacks"

			mv "${WORKDIR}/CDDA-Soundpacks/sound/CC-Sounds" "${WORKDIR}/CC-Sounds" || die
		fi
	else
		default
	fi
}

src_prepare() {
	eapply "${FILESDIR}/${PN}-respect-flags.patch"

	sed -i \
		-e "s/-Werror //" \
		-e "s/TARGET_NAME = cataclysm/TARGET_NAME = cataclysm-${SLOT}/" \
		-e "s/\$(TARGET_NAME)-tiles/cataclysm-tiles-${SLOT}/" \
		-e "s/CataclysmDDA/CataclysmDDA-${SLOT}/" \
		-e "s/${PN}/${PN}-${SLOT}/" \
		"Makefile" || die

	find "${S}" -name "Makefile" -print | \
		xargs sed -i \
		-e "s/cataclysm.a/cataclysm-${SLOT}.a/g" \
		-e "s/\$(BUILD_PREFIX)//g" || die # BUILD_PREFIX is also used by portage

	sed -i -e "s/${PN}/${PN}-${SLOT}/" \
		"lang/Makefile" \
		"src/path_info.cpp" \
		"src/translation_manager_impl.cpp" \
		"tests/translation_system_test.cpp" || die

	sed -i "s#data#${EPREFIX}/usr/share/${PN}-${SLOT}#" \
		"data/fontdata.json" || die

	sed -i "s/cataclysm-tiles/cataclysm-tiles-${SLOT}/g" \
		"data/xdg/org.cataclysmdda.CataclysmDDA.desktop" || die

	local f="org.cataclysmdda.CataclysmDDA"

	mv "data/xdg/${f}.desktop" "data/xdg/${f}-${SLOT}.desktop" || die
	mv "data/xdg/${f}.svg" "data/xdg/${f}-${SLOT}.svg" || die
	mv "data/xdg/${f}.appdata.xml" "data/xdg/${f}-${SLOT}.appdata.xml" || die

	eapply_user
}

src_compile() {
	myemakeargs=(
		BACKTRACE=$(usex debug 1 0)
		CXX="$(tc-getCXX)"
		LINTJSON=0
		PCH=0
		PREFIX="${EPREFIX}/usr"
		USE_XDG_DIR=1
	)

	use nls && export LANGUAGES="all"

	if use doc; then
		doxygen doxygen_doc/doxygen_conf.txt || die "Failed to generate docs"
	fi

	if use ncurses; then
		# don't build tests twice
		if ! use tiles; then
			emake "${myemakeargs[@]}" "RUNTESTS=$(usex test 1 0)" "TESTS=$(usex test 1 0)"
		else
			emake "${myemakeargs[@]}" "TESTS=0" "RUNTESTS=0"
		fi
		# move it when building both variants
		use tiles && { mv "cataclysm-${SLOT}" "${WORKDIR}"/cataclysm-${SLOT} || die ;}
	fi

	if use tiles; then
		emake clean
		emake "${myemakeargs[@]}" \
			"RUNTESTS=$(usex test 1 0)" \
			"SOUND=$(usex sound 1 0)" \
			"TESTS=$(usex test 1 0)" \
			"TILES=$(usex tiles 1 0)"
	fi
}

src_install() {
	emake \
		"TILES=$(usex tiles 1 0)" \
		"SOUND=$(usex sound 1 0)" \
		"${myemakeargs[@]}" \
		DESTDIR="${D}" \
		install

	[[ -e "${WORKDIR}/cataclysm-${SLOT}" ]] && dobin "${WORKDIR}/cataclysm-${SLOT}"

	use doc && dodoc -r doxygen_doc/html

	use tiles && newman "doc/cataclysm-tiles.6" "cataclysm-tiles-${SLOT}.6"
	use ncurses && newman "doc/cataclysm.6" "cataclysm-${SLOT}.6"

	if use soundpack; then
		insinto "/usr/share/${PN}-${SLOT}/sound"
		doins -r "${WORKDIR}/CC-Sounds"
	fi
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "cataclysm is a slotted install that supports having"
	elog "multiple versions installed.  The binary has the"
	elog "slot appended, e.g. 'cataclysm-"${SLOT}"'."

	if use tiles && use ncurses; then
		elog
		elog "Since you have enabled both tiles and ncurses frontends"
		elog "the ncurses binary is called 'cataclysm-${SLOT}' and the"
		elog "tiles binary is called 'cataclysm-tiles-${SLOT}'."
	fi
}
