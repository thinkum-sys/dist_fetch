## dist_fetch
#
# Copyright (c) 2022 Sean Champ. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#


## Remarks
##
## - This is not recommended for updating any installation on the
##   root filesystenm of a live system.
##
## - See also: bectl and ZFS, bsdinstall, removable media

##
## release name for fetch from distribution site
##
FETCH_REL?=	13.1-RC6

##
## distributor name, distribution site
##
DISTRIBUTOR?=	FreeBSD
MIRROR?=	https://download.freebsd.org

##
## arch and optional target arch for fetch
##
## If TARGET_ARCH is the same string as TARGET,
## then only TARGET will be used for fetch
TARGET?=	${:! uname -m !}
TARGET_ARCH?=	${:! uname -p !}

##
## destination directory for install
##
DESTDIR?=	/mnt

##
## base directory for any release-specific distfile directories
##
.ifndef CACHEROOT
CACHEROOT:=	${.CURDIR}/distcache
.endif

.ifndef CACHE_PKGDIR
. if "${TARGET}" == "${TARGET_ARCH}"
CACHE_PKGDIR=	${CACHEROOT}/${DISTRIBUTOR}_${FETCH_REL}_${TARGET}
. else
CACHE_PKGDIR=	${CACHEROOT}/${DISTRIBUTOR}_${FETCH_REL}_${TARGET}_${TARGET_ARCH}
. endif
.endif

## base directory for temporary src.txz extract,
## used with etcupdate during upgrade [FIXME if no etcupdate.tar.gz]
##
## this directory can be removed with the clean-src tgt
SRC_DESTDIR?=	${CACHE_PKGDIR}/source

## shell command for checkum format used for the release MANIFEST file
##
## See also: FreeBSD /usr/src/release/scripts/make-manifest.sh
DISTSUM?=	sha256

## DESTDIR => DESTDIR_DIR
.if empty(DESTDIR) || ( empty(DESTDIR:T) && "${DESTDIR:H}" == "." )
DESTDIR_DIR=	/
.else
DESTDIR_DIR=	${DESTDIR:C@/+$@@}/
.endif

## additional config for cache dir
.if "${TARGET_ARCH}" != "${TARGET}"
FETCH_BASE?=	${MIRROR}/releases/${TARGET}/${TARGET_ARCH}/${FETCH_REL}
.else
FETCH_BASE?=	${MIRROR}/releases/${TARGET}/${FETCH_REL}
.endif

## sudo wrapper, if make is not run as root
EUID=	${:! id -u !}
.if "${EUID}" == "0"
SU_RUN=		# Empty
.else
SU_RUN=		${SUDO:Usudo}
.endif

.if !defined(STAMPDIR)
STAMPDIR:=	${.CURDIR}
.endif

##
## using build-stamp file for ensuring that generally .EXEC tgts
## will not be run under every make, if completed successfully
## in some previous run.
##
## this is not supported for the instalt tgt
##
STAMP_TGTS=	fetch check unpack-src etcupdate-post
.for T in ${STAMP_TGTS}
STAMP.${T}:=	${STAMPDIR}/.mk-stamp.${T}
${T}: .PHONY ${STAMP.${T}}
STAMPS+=	${STAMP.${T}}
.endfor

##
## Configuration for install
##

## Directories that should exist with an 'schg' flag under DESTDIR.
##
## These would typically be listed as such under at least one file
## in the installation's etc/mtree/BSD.*.dist files. These will be
## listed manually here, to simplify the task of parsing those files.
##
## For directories with an schg flag, this may not typically be handled
## under etcupdate or generic tar cmds, and will be handled below
## in make(install). The flag will be cleared manually before installing
## base.txz. The schg flag should be set again during the mtree handling
## as according to the dist configuration
SCHG_DIRS?=	var/empty

ETCUPDATE?=	etcupdate

##
## Selection of distribution packages for fetch
##

## If the base pkg is being installed, the src pkg will also be fetched,
## as in order to provide a basis for etcupdate during install.
##
## This will not install the src pkg under DESTDIR, unless SRC or
## INSTALL_SRC has been defined in the makefile environment or if src
## was initially specified in FETCH_PKG.
##
## Variables used here:
##
## * FETCH_PKG : List of distribution packages to install, without *.txz suffix
##   Default value does not include src, ports, or tests
##
## * SRC: If defined, then fetch and install the source pkg
##
## * INSTALL_SRC : If defined, then install the source pkg.
##   Should be used with SRC defined or src in FETCH_PKG
##
## * PORTS : If defined, then fetch and install the ports tree from ports.txz
##
## * TESTS : If defined, then fetch and install tests.txz from the dist site
##
## * DEBUG : If defined, then fetch and install debug packages for any base,
##   kernel, or lib32 in FETCH_PKG
##
## * NO_FETCH : If defined, wget will not be run to fetch any FETCH_PKG or dist metadata
FETCH_PKG?=	base kernel

.ifndef NO_MULTILIB
FETCH_PKG+=	lib32
.endif

.if defined(SRC) || !empty(FETCH_PKG:Mbase)
. if !empty(FETCH_PKG:Msrc) && defined(SRC)
INSTALL_SRC=	Defined
. endif
FETCH_PKG+=	src
.endif

.ifdef PORTS
FETCH_PKG+=	ports
.endif

.ifdef TESTS
FETCH_PKG+=	tests
.endif

.ifdef DEBUG
FETCH_PKG:=	${FETCH_PKG} ${FETCH_PKG:Nsrc:Nports:Ntests:@.P.@${.P.}-dbg@}
.endif

.for P in ${FETCH_PKG}
ARCHIVE_PATH.${P}?=	${CACHE_PKGDIR}/${P}.txz
FETCH_ORIGIN.${P}?=	${FETCH_BASE}/${P}.txz
.endfor

FETCH_META?=	MANIFEST REVISION GITBRANCH BUILDDATE

.for F in ${FETCH_META}
ARCHIVE_PATH.${F}?=	${CACHE_PKGDIR}/${F}
FETCH_ORIGIN.${F}?=	${FETCH_BASE}/${F}
.endfor


all: .PHONY ${STAMP.fetch}

clean: clean-src
	rm -f ${STAMPS}

realclean: clean clean-cache

##
## fetch tooling
##

${CACHE_PKGDIR}:
	mkdir -p ${.TARGET}

.for P in ${FETCH_PKG}
ALL_FETCH+=		${ARCHIVE_PATH.${P}}
${ARCHIVE_PATH.${P}}: 	${ALL_FETCH_META} ${CACHE_PKGDIR} .PRECIOUS
. ifndef NO_FETCH
	if [ -e $@ ]; then chmod +w $@; fi
	wget -O $@ -c ${FETCH_ORIGIN.${P}}
	chmod -w $@
. endif
.endfor

.for F in ${FETCH_META}
all_FETCH_META+=	${ARCHIVE_PATH.${F}}
${ARCHIVE_PATH.${F}}: 	${CACHE_PKGDIR} .PRECIOUS
. ifndef NO_FETCH
	if [ -e $@ ]; then chmod +w $@; fi
	wget -O $@ -c ${FETCH_ORIGIN.${F}}
	chmod -w $@
. endif
.endfor
ALL_FETCH+=		${ALL_FETCH_META}

${STAMP.fetch}:		${ALL_FETCH}
	@touch $@

${STAMP.check}: 	${ALL_FETCH}
.for P in ${FETCH_PKG}
	@(if ! [ -e "${ARCHIVE_PATH.${P}}" ]; then echo "File not found (make fetch?): ${ARCHIVE_PATH.${P}}"; false; fi)
	@echo "#-- Checking ${P}.txz checksum" 1>&2
	@(set -e; ORIGSUM=$$(awk 'BEGIN {EX = 1} \
		$$1 == "${P}.txz" { print $$2; EX=0} \
		END { if (EX != 0) { print "${P}.txz not found in manifest ${CACHE_PKGDIR}/MANIFEST"; exit 1; }}' ${CACHE_PKGDIR}/MANIFEST); \
		${DISTSUM} -c "$${ORIGSUM}" ${ARCHIVE_PATH.${P}} >/dev/null )
.endfor
	@touch $@

clean-cache: 		.PHONY clean-src
	if [ -e "${CACHE_PKGDIR}" ]; then \
	  echo "#-- Removing distribution files in ${CACHE_PKGDIR}" 1>&2; \
	  rm -f ${FETCH_PKG:@P@${CACHE_PKGDIR}/${P}.txz@}; \
	  rm -f ${FETCH_META:@F@${CACHE_PKGDIR}/${F}@}; \
	fi

##
## installation tooling
##

## The following tgts may require interactive input for etcupdate and SU_RUN

${SRC_DESTDIR}:
	mkdir -p ${.TARGET}

${STAMP.unpack-src}:	${STAMP.check} ${SRC_DESTDIR} ${CACHE_PKGDIR}/src.txz
	tar -C ${SRC_DESTDIR} -Jxf ${CACHE_PKGDIR}/src.txz
	@touch $@

clean-src:		.PHONY
	@echo "#-- Removing local source directory ${SRC_DESTDIR}" 1>&2
	rm -rf ${SRC_DESTDIR}

## NB this is somewhat redundant as it requires that etcupdate is run
## to build etcupdate.tar.gz while it will be run for install
## on the actual unpacked src.txz
## - FIXME src.txz no longer required here, if etcupdate.tar.gz and old.inc are available
${CACHE_PKGDIR}/etcupdate.tar.gz: ${STAMP.unpack-src}
	WRK=$$(mktemp -d ${TMPDIR:U/tmp}/etcupdate_wrk.${.MAKE.PID}XXXXXX.d); \
	${SU_RUN} ${ETCUPDATE} build -d $${WRK} -s ${SRC_DESTDIR}/usr/src $@; \
	rm -f $${WRK}/log; rmdir $${WRK}

## Produce a list of files to exclude when extracting base.txz,
## thus preventing overwrite of ${DESTDIR}/etc/master.passwd if the file exists.
## This is used together with etcupdate after install
${CACHE_PKGDIR}/etcupdate.files: ${CACHE_PKGDIR}/etcupdate.tar.gz
	tar -tf ${CACHE_PKGDIR}/etcupdate.tar.gz | grep -v '/$$' > $@

## OLD_(DIRS, LIBS, FILES)
##
## This will extract variables in a syntax compatible with sh(1),
## for sh(1) source (.) during make install
##
## The mk-source variables would be bound for some specific make tgts
## in SRCTOP/Makefile.inc1
${CACHE_PKGDIR}/old.inc: ${STAMP.unpack-src}
	${MAKE} -C ${SRC_DESTDIR}/usr/src -f ${SRC_DESTDIR}/usr/src/Makefile.inc1 \
		-V 'OLD_DIRS=$${OLD_DIRS:Q}' -V 'OLD_FILES=$${OLD_FILES:Q}' \
		-V 'OLD_LIBS=$${OLD_LIBS:Q}' \
		TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} check-old  > $@

##
## conditional etcupdate tooling for a base system update
## or new base system installation
##
.if !empty(FETCH_PKG:Mbase)
. if exists(${DESTDIR_DIR}usr/lib/libc.so) || exists(${DESTDIR_DIR}usr/lib/libc.a)
INSTALL_UPDATE=	Defined
## updating an existing installation with a new base.txz (post-install only)
##
## this will be run at the end of make install
${STAMP.etcupdate-post}: ${STAMP.unpack-src} .USE
## run twice if it fails initially, in post-update.
## terminate with || true on the first call.
	${SU_RUN} ${ETCUPDATE} ${ETCUPDATE_IGNORE:D-I ${ETCUPDATE_IGNORE:Q}} -D ${DESTDIR_DIR} -s ${SRC_DESTDIR}/usr/src || \
	${SU_RUN} ${ETCUPDATE} resolve ${ETCUPDATE_IGNORE:D-I ${ETCUPDATE_IGNORE:Q}} -D ${DESTDIR_DIR} -s ${SRC_DESTDIR}/usr/src || true
	${SU_RUN} ${ETCUPDATE} resolve ${ETCUPDATE_IGNORE:D-I ${ETCUPDATE_IGNORE:Q}} -D ${DESTDIR_DIR} -s ${SRC_DESTDIR}/usr/src
. else
## assumption: This is a new installation, with no libc under destdir.
## no config check; etcupdte extract in post
${STAMP.etcupdate-post}: ${STAMP.unpack-src} .USE
	${SU_RUN} etcupdate extract -D ${DESTDIR_DIR} -s ${SRC_DESTDIR}/usr/src
. endif
.endif


install: .PHONY check ${DESTDIR_DIR} ${STAMP.etcupdate-post} ${CACHE_PKGDIR}/old.inc ${CACHE_PKGDIR}/etcupdate.files
## clear known fflags on dirs, if base.txz will be installed
.if !empty(FETCH_PKG:Mbase) && defined(INSTALL_UPDATE)
. for D in ${SCHG_DIRS}
	if [ -e ${DESTDIR_DIR}${D} ]; then ${SU_RUN} chflags noschg ${DESTDIR_DIR}${D}; fi
. endfor
## extract base.txz
	@echo "#-- installing base system" 1>&2
	${SU_RUN} tar -C ${DESTDIR_DIR}  --clear-nochange-fflags --fflags \
		 -Jxf ${ARCHIVE_PATH.base} -X ${CACHE_PKGDIR}/etcupdate.files
.endif
## extract *.txz other than base, src (i.e kernel, lib32, ports, test)
.for P in ${FETCH_PKG:Nsrc:Nbase}
	@echo "#-- installing ${P}" 1>&2
	${SU_RUN} tar -C ${DESTDIR_DIR} --clear-nochange-fflags --fflags \
		 -Jxf ${ARCHIVE_PATH.${P}}
.endfor
## install src
.if defined(INSTALL_SRC)
	@echo "#-- installing src" 1>&2
	${SU_RUN} tar -C ${DESTDIR_DIR} --clear-nochange-fflags --fflags \
		 -Jxf ${ARCHIVE_PATH.src}
.endif
## update file metadata and system config (new installation and/or update)
##
## etcupdate will be run after make install complete
.if !empty(FETCH_PKG:Mbase)
## set all fflags, file permissions, times per mtree metadata as installed
	echo "#-- mtree : var/db/mergemaster.mtree" 1>&2
	${SU_RUN} mtree -iUte -p ${DESTDIR_DIR} -f ${DESTDIR_DIR}var/db/mergemaster.mtree
	for DIRTREE in ${DESTDIR_DIR}etc/mtree/BSD.*.dist; do \
		NAME=$$(basename $${DIRTREE} | sed 's@.*\.\(.*\)\..*@\1@'); \
		case $${NAME} in (root|sendmail) REALDIR= ;; (lib32|include) REALDIR=usr;; \
		(debug) if ! ${DEBUG:Dtrue:Ufalse}; then continue; else REALDIR=usr/lib; fi;; \
		(tests) REALDIR=usr/tests;; (*) REALDIR=$${NAME};; esac; \
		if [ -e ${DESTDIR_DIR}${REALDIR} ]; then echo "#-- mtree : $${NAME} @ $${REALDIR}"; \
		${SU_RUN} mtree -iUte -p ${DESTDIR_DIR}${REALDIR} -f $${DIRTREE}; fi; \
	done
. if defined(INSTALL_UPDATE)
## clean old files/libs and old dirs, using metadata from the corresponding source tree
	echo "#-- cleaning old files/libs in ${DESTDIR_DIR}" 1>&2
	. ${CACHE_PKGDIR}/old.inc; \
	for F in $${OLD_FILES} $${OLD_LIBS}; do \
	if test -e ${DESTDIR_DIR}$${F}; then \
	  ${SU_RUN} chflags noschg ${DESTDIR_DIR}$${F} || echo "#-- (chflags exited $$?) unable to modify file flags: ${DESTDIR_DIR}$${F}" 1>&2; \
	  ${SU_RUN} rm -fv ${DESTDIR_DIR}$${F} || echo "#-- (rm exited $$?) unable to remove file: ${DESTDIR_DIR}$${F}" 1>&2; \
	fi; done
	echo "#-- cleaning old dirs in ${DESTDIR_DIR}" 1>&2; \
	. ${CACHE_PKGDIR}/old.inc; \
	for D in $${OLD_DIRS}; do \
	if [ -d ${DESTDIR_DIR}$${D} ]; then \
	  if [ $$(stat -f '%l' ${DESTDIR_DIR}$${D}) -le 2 ]; then \
		  ${SU_RUN} chflags noschg ${DESTDIR_DIR}$${D} || echo "#-- (chflags exited $$?) unable to modify dir flags: ${DESTDIR_DIR}$${D}" 1>&2; \
		  ${SU_RUN} rmdir -v ${DESTDIR_DIR}$${D} || echo "#-- (rmdir exited $$?) rmdir failed: ${DESTDIR_DIR}$${D}" 1>&2; \
	  else echo "#--- directory not empty, not removing: ${DESTDIR_DIR}$${D}" 1>&2; \
	fi; fi; done
. endif
.endif
