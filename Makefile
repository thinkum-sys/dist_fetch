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
## If TARGET_ARCH is the same string as ARCH,
## then only ARCH will be used for fetch
ARCH?=		${:! uname -m !}
TARGET_ARCH?=	${:! uname -p !}

##
## destination directory for install
##
DESTDIR?=	/mnt

##
## base directory for any release-specific dist directories
##
.ifndef CACHEROOT
CACHEROOT:=	${.CURDIR}/distcache
.endif

.if "${ARCH}" == "${TARGET_ARCH}"
CACHE_PKGDIR=	${CACHEROOT}/${DISTRIBUTOR}_${FETCH_REL}_${ARCH}
.else
CACHE_PKGDIR=	${CACHEROOT}/${DISTRIBUTOR}_${FETCH_REL}_${ARCH}_${TARGET_ARCH}
.endif

## extract directory for src.txz, used with etcupdate during upgrade.
##
## this directory can be removed with the clean-src tgt
SRC_DESTDIR?=	${CACHE_PKGDIR}/source

## shell command for checkum format used for the release MANIFEST file
##
## See also: FreeBSD /usr/src/release/scripts/make-manifest.sh
DISTSUM?=	sha256

.if empty(DESTDIR) || ( empty(DESTDIR:T) && "${DESTDIR:H}" == "." )
DESTDIR_DIR=	/
.else
DESTDIR_DIR=	${DESTDIR:C@/+$@@}/
.endif

.if "${TARGET_ARCH}" != "${ARCH}"
FETCH_BASE?=	${MIRROR}/releases/${ARCH}/${TARGET_ARCH}/${FETCH_REL}
.else
FETCH_BASE?=	${MIRROR}/releases/${ARCH}/${FETCH_REL}
.endif

EUID=	${:! id -u !}
.if "${EUID}" == "0"
SU_RUN=		# Empty
.else
SU_RUN=		${SUDO:Usudo}
.endif

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
FETCH_PKG?=	base kernel lib32

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

FETCH_META?=	MANIFEST REVISION GITBRANCH BUILDDATE

all: .PHONY fetch

clean: clean-src
realclean: clean clean-cache

##
## fetch tooling
##

${CACHE_PKGDIR}:
	mkdir -p ${.TARGET}

.for F in ${FETCH_META}
ALL_FETCH_META+=		${CACHE_PKGDIR}/${F}
${CACHE_PKGDIR}/${F}: 		${CACHE_PKGDIR} .PRECIOUS
. ifndef NO_FETCH
	chmod +w ${.TARGET}
	wget -O ${.TARGET} -c ${FETCH_BASE}/${F}
	chmod -w ${.TARGET}
. endif
.endfor
ALL_FETCH+=			${ALL_FETCH_META}

.for P in ${FETCH_PKG}
ALL_FETCH+=			${CACHE_PKGDIR}/${P}.txz
${CACHE_PKGDIR}/${P}.txz: 	${ALL_FETCH_META} ${CACHE_PKGDIR} .PRECIOUS
. ifndef NO_FETCH
	chmod +w ${.TARGET}
	wget -O ${.TARGET} -c ${FETCH_BASE}/${P}.txz
	chmod -w ${.TARGET}
. endif
.endfor

fetch:		.PHONY ${ALL_FETCH}

check:		.PHONY ${ALL_FETCH}
.for P in ${FETCH_PKG}
	@( ORIGSUM=$$(awk -v "P=${F}" '$$1 == "${P}.txz" { print $$2 }' ${CACHE_PKGDIR}/MANIFEST); \
	HERESUM=$$(${DISTSUM} ${CACHE_PKGDIR}/${P}.txz | awk '{ print $$4 }'); \
		if [ "$${ORIGSUM}" = "$${HERESUM}" ]; then \
			echo "#-- File matched checksum: ${P}.txz"; else \
			echo "#-- File check failed: ${P}.txz (expected $${ORIGSUM} received $${HERESUM})" 1>&2; false; \
		fi )
.endfor

clean-cache: .PHONY clean-src
	if [ -e "${CACHE_PKGDIR}" ]; then \
		echo "#-- Removing distribution files in ${CACHE_PKGDIR}"; \
		rm -f ${FETCH_PKG:@P@${CACHE_PKGDIR}/${P}.txz@}; \
		rm -f ${FETCH_META:@F@${CACHE_PKGDIR}/${F}@}; \
	fi

##
## installation tooling
##

## The following tgts may require interactive input for etcupdate and SU_RUN

${SRC_DESTDIR}:
	mkdir -p ${.TARGET}

unpack-src:	.PHONY ${SRC_DESTDIR} ${CACHE_PKGDIR}/src.txz
	tar -C ${SRC_DESTDIR} -Jxf ${CACHE_PKGDIR}/src.txz

clean-src:	.PHONY
	@echo "#-- Removing local source directory ${SRC_DESTDIR}"
	rm -rf ${SRC_DESTDIR}

.if exists(${DESTDIR_DIR}usr/lib/libc.so) || exists(${DESTDIR_DIR}usr/lib/libc.a)
## Assumption: This installation will update an existing installation
etcupdate-pre: .PHONY unpack-src .USEBEFORE
	${SU_RUN} etcupdate -p -I "${ETCUPDATE_IGNORE}" -D ${DESTDIR_DIR} -s ${SRC_DESTDIR}/usr/src || \
	${SU_RUN} etcupdate resolve -p -I "${ETCUPDATE_IGNORE}" -D ${DESTDIR_DIR} -s ${SRC_DESTDIR}/usr/src
etcupdate-post: .PHONY etcupdate-pre .USE
	${SU_RUN} etcupdate -I "${ETCUPDATE_IGNORE}" -D ${DESTDIR_DIR} -s ${SRC_DESTDIR}/usr/src || \
	${SU_RUN} etcupdate resolve -I "${ETCUPDATE_IGNORE}" -D ${DESTDIR_DIR} -s ${SRC_DESTDIR}/usr/src
.else
## new installation - ensure an etcupdate db is created for destdir
etcupdate-pre: .PHONY unpack-src .USEBEFORE
etcupdate-post: .PHONY unpack-src .USE
	${SU_RUN} etcupdate extract -D ${DESTDIR_DIR} -s ${SRC_DESTDIR}/usr/src
.endif

install: 	.PHONY check ${DESTDIR_DIR} etcupdate-pre etcupdate-post
## clear known fflags on dirs, if base.txz will be installed
.if !empty(FETCH_PKG:Mbase)
	if [ -e ${DESTDIR_DIR}var/empty ]; then ${SU_RUN} chflags noschg ${DESTDIR_DIR}var/empty; fi
.endif
.for P in ${FETCH_PKG:Nsrc}
	${SU_RUN} tar --clear-nochange-fflags --fflags -Jxf ${CACHE_PKGDIR}/${P}.txz -C ${DESTDIR_DIR}
.endfor
.if defined(INSTALL_SRC)
	${SU_RUN} tar --clear-nochange-fflags --fflags -Jxf ${CACHE_PKGDIR}/src.txz -C ${DESTDIR_DIR}
.endif
## applying mtree files with original metadata (noschg, other)
.if !empty(FETCH_PKG:Mbase)
	${SU_RUN} mtree -iUte -p ${DESTDIR_DIR} -f ${DESTDIR_DIR}var/db/mergemaster.mtree
	for DIRTREE in ${DESTDIR_DIR}etc/mtree/BSD.*.dist; do \
		NAME=$$(basename $${DIRTREE} | sed 's@.*\.\(.*\)\..*@\1@'); \
		case $${NAME} in (root|sendmail) REALDIR= ;; (lib32|include) REALDIR=usr ;; \
		(debug) if ! ${DEBUG:Dtrue:Ufalse}; then continue; else REALDIR=usr/lib; fi;; \
		(tests) REALDIR=usr/tests;; (*) REALDIR=$${NAME};; esac; \
		if [ -e ${DESTDIR_DIR}${REALDIR} ]; then echo "#-- $${REALDIR}"; \
		${SU_RUN} mtree -iUte -p ${DESTDIR_DIR}${REALDIR} -f $${DIRTREE}; fi; \
	done
	if [ -e ${DESTDIR_DIR}etc/master.passwd ]; then \
		${SU_RUN} pwd_mkdb -d ${DESTDIR_DIR}etc -p ${DESTDIR_DIR}etc/master.passwd; fi
.endif

## destroy-destdir: Destructive tgt, unset schg flags and remove files in DESTDIR_DIR
##
## This destructive tgt may be run in a separate make process for a specific
## DESTDIR, before any later make process that would install with the same DESTDIR.
##
## If this tgt would be run for an existing installation under DESTDIR, and run previous
## to make install in the same process,, then the installation tgts may handle the
## installationas an upgrade wile there may not not be a filesystem for upgrade onced
## the install tgt is reached.
##
## No Warranty.
##
destroy-destdir:
	if [ "${DESTDIR_DIR}" = "/" ]; then echo "#-- Aborting - Not destroying /"; false; else \
		echo "#-- Removing files and directories in ${DESTDIR_DIR}"; \
		${SU_RUN} find ${DESTDIR_DIR} -maxdepth 1 -mindepth 1 -exec chflags -R noschg {} +; \
		${SU_RUN} find ${DESTDIR_DIR} -maxdepth 1 -mindepth 1 -exec rm -rf {} +; \
	fi
