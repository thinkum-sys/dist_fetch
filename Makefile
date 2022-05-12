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


ARCH?=		${:! uname -m !}

TARGET_ARCH?=	${:! uname -p !}

DESTDIR?=	# Empty


.ifndef CACHEROOT
CACHEROOT:=	${.CURDIR}/distcache
.endif


## source directory to use when managing etcupdate
## during an upgrade installation. This may be
## provided as a subdirectory of DESTDIR
SRC_DESTDIR?=	${CACHE_PKGDIR}/src

MIRROR?=	https://download.freebsd.org

FETCH_REL?=	13.1-RC6

## DISTSUM: checksum format/cmd used for the release MANIFEST file
##
## cf. /usr/src/release/scripts/make-manifest.sh
##
DISTSUM?=	sha256

.if empty(DESTDIR) || ( empty(DESTDIR:T) && "${DESTDIR:H}" == "." )
DESTDIR_DIR=	/
.else
DESTDIR_DIR=	${DESTDIR:C@/+$@@}/
.endif

.if "${TARGET_ARCH}" != "${ARCH}"
FETCH_BASE?=	${MIRROR}releases/${ARCH}/${TARGET_ARCH}/${FETCH_REL}
.else
FETCH_BASE?=	${MIRROR}/releases/${ARCH}/${FETCH_REL}
.endif

## NB if the base pkg is being installed, the src pkg must also be fetched
## in order to provide a basis for etcupdate during install
##
## this will in fact not install the src pkg, but will fetch it to CACHE_PKGDIR
FETCH_PKG?=	base kernel lib32 src

OSNAME=		FreeBSD

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

CACHE_PKGDIR=	${CACHEROOT}/${OSNAME}_${FETCH_REL}

${CACHE_PKGDIR}:
	mkdir -p ${.TARGET}

.for F in ${FETCH_META}
ALL_FETCH_META+=		${CACHE_PKGDIR}/${F}
${CACHE_PKGDIR}/${F}: 		${CACHE_PKGDIR} .PRECIOUS
. ifndef NO_FETCH
	wget -O ${.TARGET} -c ${FETCH_BASE}/${F}
	chmod -w ${.TARGET}
. endif
.endfor
ALL_FETCH+=			${ALL_FETCH_META}

.for P in ${FETCH_PKG}
ALL_FETCH+=			${CACHE_PKGDIR}/${P}.txz
${CACHE_PKGDIR}/${P}.txz: 	${ALL_FETCH_META} ${CACHE_PKGDIR} .PRECIOUS
. ifndef NO_FETCH
	wget -O ${.TARGET} -c ${FETCH_BASE}/${P}.txz
	chmod -w ${.TARGET}
. endif
.endfor

fetch: .PHONY ${ALL_FETCH}

check: .PHONY ${ALL_FETCH}
.for P in ${FETCH_PKG}
	@( ORIGSUM=$$(awk -v "P=${F}" '$$1 == "${P}.txz" { print $$2 }' ${CACHE_PKGDIR}/MANIFEST) ; \
	HERESUM=$$(${DISTSUM} ${CACHE_PKGDIR}/${P}.txz | awk '{ print $$4 }'); \
		if [ "$${ORIGSUM}" = "$${HERESUM}" ]; then \
			echo "File checked: ${P}.txz"; else \
			"File check failed: ${P}.txz (expected $${ORIGSUM} received $${HERESUM})" 1>&2; false; \
		fi )
.endfor



##
## installation tooling
##

${SRC_DESTDIR}:
	mkdir -p ${.TARGET}

## FIXME this has not provided any tgt for cleaning any unpacked srck
unpack-src:	.PHONY ${SRC_DESTDIR} ${CACHE_PKGDIR}/src.txz .USEBEFORE
	tar -C ${SRC_DESTDIR} -Jxf ${CACHE_PKGDIR}/src.txz


.if exists(${DESTDIR_DIR}usr/lib/libc.so) || exists(${DESTDIR_DIR}usr/lib/libc.a)
##
## assumption: This will be an update installation
##
##
## the following tgts will sometimes require interactive input
##

etcupdate-pre: .PHONY unpack-src .USEBEFORE
	etcupdate -p -I "${ETCUPDATE_IGNORE}" -D ${DESTDIR_DIR} -s ${SRC_DESTDIR}/usr/src || \
	etcupdate resolve -p -I "${ETCUPDATE_IGNORE}" -D ${DESTDIR_DIR} -s ${SRC_DESTDIR}/usr/src

etcupdate-post: .PHONY etcupdate-pre .USE
	etcupdate -I "${ETCUPDATE_IGNORE}" -D ${DESTDIR_DIR} -s ${SRC_DESTDIR}/usr/src || \
	etcupdate resolve -I "${ETCUPDATE_IGNORE}" -D ${DESTDIR_DIR} -s ${SRC_DESTDIR}/usr/src

.else
## new installation - ensure an etcupdate db is created for destdir
etcupdate-pre: .PHONY unpack-src
etcupdate-post: .PHONY unpack-src .USE
	etcupdate extract -D ${DESTDIR_DIR} -s ${SRC_DESTDIR}/usr/src
.endif


install: .PHONY check ${DESTDIR_DIR} etcupdate-pre etcupdate-post
## try to clear any fflags on dirs first
## after extracting only the dirtree files
## if base.txz is a pkg being installed.
##
## this assumes that no schg flags are set under DESTDIR
## that would interfere with the mtree file extraction
##
.if !empty(FETCH_PKG:Mbase)
## the fflags handling in tar may apply only to files, not dirs.
## /var/empty might be the only dir at present, which has the flag set
## in dist install
	[ -e ${DESTDIR_DIR}var/empty ] && chflags noschg ${DESTDIR_DIR}var/empty
.endif
.for P in ${FETCH_PKG:Nsrc}
	tar --clear-nochange-fflags --fflags -xJf ${CACHE_PKGDIR}/${P}.txz -C ${DESTDIR_DIR}
.endfor
## applying all mtree files here, with no further hacking on the metadata
	mtree -iUte -p ${DESTDIR_DIR} -f ${DESTDIR_DIR}var/db/mergemaster.mtree
.if !empty(FETCH_PKG:Mbase)
	for DIRTREE in ${DESTDIR_DIR}etc/mtree/BSD.*.dist; do \
		NAME=$$(basename $${DIRTREE} | sed 's@.*\.\(.*\)\..*@\1@'); \
		case $${NAME} in (root|sendmail) REALDIR= ;; (lib32|include) REALDIR=usr ;; \
		(debug) if ! ${DEBUG:Dtrue:Ufalse}; then continue; else REALDIR=usr/lib; fi;; \
		(tests) REALDIR=usr/tests;; (*) REALDIR=$${NAME};; esac; \
		if [ -e ${DESTDIR_DIR}${REALDIR} ]; then echo "#-- $${REALDIR}"; \
		mtree -iUte -p ${DESTDIR_DIR}${REALDIR} -f $${DIRTREE}; fi; \
	done
.endif


## NB this destructive tgt would typically need to be run in a separate
## make process with the specific DESTDIR, before any later install,
## or the installation tgts may handle it as an upgrade instead
#
## typically this could be accomplished with a shell cmd like follows,
## i.e setting a common DESTDIR in a subshell [No Warranty]
##
## $ sudo bash -c 'export DESTDIR=/mnt; make destroy-destdir; make install ...'
##
destroy-destdir:
	if [ "${DESTDIR_DIR}" = "/" }; then echo "Aborting - Not destroying /"; false; else \
		find ${DESTDIR_DIR} -maxdepth 1 -mindepth 1 -exec chflags -R noschg {} +; \
		find ${DESTDIR_DIR} -maxdepth 1 -mindepth 1 -exec rm -rf {} +; \
	fi
