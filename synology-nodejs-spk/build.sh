#!/bin/sh
# ---------------------------------------------------------------------------
# Build a Synology SPK package for Node.js targeting DSM 6.2 (x86_64).
#
# Why the "glibc-217" build?
#   Official Node.js binaries are linked against glibc >= 2.28, while DSM 6.2.3
#   ships glibc 2.20.  The unofficial-builds "glibc-217" flavour is compiled
#   against glibc 2.17 and therefore runs on DSM 6.2.x.  V8, libuv, npm, npx
#   and corepack are identical to an upstream release; only the glibc the
#   toolchain linked against differs.
#
# Usage:  sh build.sh
# Env:    NODE_VERSION  (default 24.21.0)
#         SPK_REV       (default 0001)
#         NODE_TARBALL  (optional) reuse an already downloaded .tar.gz instead of
#                       fetching it again -- handy for offline / repeat builds.
#                       Its SHA256 is still checked against the published list.
#         MAINTAINER / DISTRIBUTOR / ... to override the Package Center metadata
# Output: out/Node.js_v12_x64-dsm6_<NODE_VERSION>-<SPK_REV>.spk
#
# Package id note:
#   The package id is intentionally "Node.js_v12" -- the *exact* id used by the
#   official Synology "Node.js v12" package (verified against the archived
#   official INFO: package="Node.js_v12", arch="x86_64").  Reusing that id lets
#   this SPK overwrite / upgrade an already-installed official Node.js v12
#   package instead of installing side by side.  Because our version
#   (${NODE_VERSION}-...) sorts higher than 12.22.12-0024, Package Center treats
#   it as a normal upgrade.
# ---------------------------------------------------------------------------
set -eu

NODE_VERSION="${NODE_VERSION:-24.21.0}"
SPK_REV="${SPK_REV:-0001}"
PKG_NAME="Node.js_v12"
PKG_DISPLAY_NAME="Node.js"

# Architecture code, matching the official Node.js_v12 SPK byte-for-byte so the
# overwrite/upgrade path accepts it.  The Node.js runtime here is linux-x64.
ARCH_LIST="x86_64"
FIRMWARE="6.0-7321"
OS_MIN_VER="6.0-7321"
OS_MAX_VER="7.0-40000"

MAINTAINER="${MAINTAINER:-Node.js SPK Build}"
MAINTAINER_URL="${MAINTAINER_URL:-https://nodejs.org/}"
DISTRIBUTOR="${DISTRIBUTOR:-Node.js SPK Build}"
DISTRIBUTOR_URL="${DISTRIBUTOR_URL:-https://nodejs.org/}"

DIST_NAME="node-v${NODE_VERSION}-linux-x64-glibc-217"
BASE_URL="https://unofficial-builds.nodejs.org/download/release/v${NODE_VERSION}"

ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK="${ROOT}/.work"
OUT="${ROOT}/out"
STAGING="${WORK}/payload"
TARBALL="${WORK}/${DIST_NAME}.tar.gz"

rm -rf "${WORK}"
mkdir -p "${WORK}" "${OUT}" "${STAGING}"

echo "==> [1/6] Obtaining ${DIST_NAME}.tar.gz"
if [ -n "${NODE_TARBALL:-}" ]; then
    echo "    reusing ${NODE_TARBALL}"
    cp "${NODE_TARBALL}" "${TARBALL}"
else
    curl -fsSL -o "${TARBALL}" "${BASE_URL}/${DIST_NAME}.tar.gz"
fi
curl -fsSL -o "${WORK}/SHASUMS256.txt" "${BASE_URL}/SHASUMS256.txt"

echo "==> [2/6] Verifying SHA256"
( cd "${WORK}" && grep " ${DIST_NAME}.tar.gz\$" SHASUMS256.txt | sha256sum -c - )

echo "==> [3/6] Staging runtime in the official Synology layout"
DIST_DIR="${WORK}/dist"
mkdir -p "${DIST_DIR}"
tar -xzf "${TARBALL}" -C "${DIST_DIR}" --strip-components=1

# The upstream Node.js tarball puts the binary at bin/node.  The *official*
# Synology Node.js_v12 package instead ships it as
#     <target>/usr/local/bin/node
# and Synology's own packages hardcode that exact path -- e.g. the
# SynologyApplicationService upstart job for VapidSendServer runs
#     exec /var/packages/Node.js_v12/target/usr/local/bin/node .../VapidSendServer.js
# So we must reproduce the official layout, otherwise every dependent package
# fails to start ("Failed to start service [Vapid Send Server]").
mkdir -p "${STAGING}/usr/local/bin" "${STAGING}/usr/local/lib"
cp -a "${DIST_DIR}/bin/node" "${STAGING}/usr/local/bin/node"
cp -a "${DIST_DIR}/lib/node_modules" "${STAGING}/usr/local/lib/node_modules"
[ -d "${DIST_DIR}/include" ] && cp -a "${DIST_DIR}/include" "${STAGING}/usr/local/include"
[ -d "${DIST_DIR}/share" ] && cp -a "${DIST_DIR}/share" "${STAGING}/usr/local/share"
ln -sfn ../lib/node_modules/npm/bin/npm-cli.js        "${STAGING}/usr/local/bin/npm"
ln -sfn ../lib/node_modules/npm/bin/npx-cli.js        "${STAGING}/usr/local/bin/npx"
ln -sfn ../lib/node_modules/corepack/dist/corepack.js "${STAGING}/usr/local/bin/corepack"
cp -a "${DIST_DIR}/CHANGELOG.md" "${DIST_DIR}/LICENSE" "${DIST_DIR}/README.md" "${STAGING}/" 2>/dev/null || true

echo "==> [4/6] Building package.tgz"
( cd "${STAGING}" && find . -mindepth 1 -maxdepth 1 | tar cf - --files-from=- | gzip -n > "${WORK}/package.tgz" )

echo "==> [5/6] Generating INFO"
MD5="$(md5sum "${WORK}/package.tgz" | cut -d' ' -f1)"
cat > "${WORK}/INFO" <<EOF
package="${PKG_NAME}"
version="${NODE_VERSION}-${SPK_REV}"
displayname="${PKG_DISPLAY_NAME}"
description="Node.js is an open-source, cross-platform JavaScript runtime environment. This package provides the Node.js ${NODE_VERSION} LTS runtime together with npm, npx and corepack. It is built against glibc 2.17 so it runs on DSM 6.2.x, where the system glibc (2.20) is too old for the official binaries (which require glibc 2.28)."
description_chs="Node.js 是一个开源、跨平台的 JavaScript 运行时环境。本套件提供 Node.js ${NODE_VERSION} LTS 运行时，并包含 npm、npx 与 corepack；针对 glibc 2.17 构建，可在系统 glibc 仅为 2.20 的 DSM 6.2.x 上直接运行（官方二进制要求 glibc 2.28，无法在此系统运行）。"
description_cht="Node.js 是一個開放原始碼、跨平台的 JavaScript 執行環境。本套件提供 Node.js ${NODE_VERSION} LTS 執行環境，並內含 npm、npx 與 corepack；針對 glibc 2.17 建置，可在系統 glibc 僅為 2.20 的 DSM 6.2.x 上直接執行（官方二進位檔要求 glibc 2.28，無法在此系統執行）。"
arch="${ARCH_LIST}"
firmware="${FIRMWARE}"
maintainer="${MAINTAINER}"
maintainer_url="${MAINTAINER_URL}"
distributor="${DISTRIBUTOR}"
distributor_url="${DISTRIBUTOR_URL}"
os_min_ver="${OS_MIN_VER}"
os_max_ver="${OS_MAX_VER}"
thirdparty="yes"
startable="no"
silent_install="yes"
silent_upgrade="yes"
silent_uninstall="yes"
support_center="yes"
helpurl="https://nodejs.org/"
support_url="https://github.com/nodejs/node/issues"
changelog="Node.js ${NODE_VERSION} LTS (glibc-217 build) packaged for DSM 6.2 x86_64."
ctl_stop="no"
dsmappname="org.nodejs.spk.nodejs"
support_conf_folder="yes"
checksum="${MD5}"
EOF

echo "==> [6/6] Generating icons and assembling SPK"
python3 "${ROOT}/mk-icon.py" "${WORK}/PACKAGE_ICON.PNG" 72
python3 "${ROOT}/mk-icon.py" "${WORK}/PACKAGE_ICON_256.PNG" 256

SPK_STAGE="${WORK}/spk"
mkdir -p "${SPK_STAGE}"
cp "${WORK}/INFO" "${SPK_STAGE}/INFO"
cp "${WORK}/package.tgz" "${SPK_STAGE}/package.tgz"
cp "${WORK}/PACKAGE_ICON.PNG" "${SPK_STAGE}/PACKAGE_ICON.PNG"
cp "${WORK}/PACKAGE_ICON_256.PNG" "${SPK_STAGE}/PACKAGE_ICON_256.PNG"
cp -R "${ROOT}/spk/scripts" "${SPK_STAGE}/scripts"
cp -R "${ROOT}/spk/conf" "${SPK_STAGE}/conf"
# Inject the concrete version into the shared script helpers.
sed -i "s/@@NODE_VERSION@@/${NODE_VERSION}/g" "${SPK_STAGE}/scripts/common"
chmod 755 "${SPK_STAGE}"/scripts/*
chmod 644 "${SPK_STAGE}/INFO" "${SPK_STAGE}/conf/privilege"

SPK_FILE="${OUT}/${PKG_NAME}_x64-dsm6_${NODE_VERSION}-${SPK_REV}.spk"
rm -f "${SPK_FILE}"
( cd "${SPK_STAGE}" && tar cpf "${SPK_FILE}" package.tgz INFO scripts conf PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG )

echo
echo "Built: ${SPK_FILE}"
ls -lh "${SPK_FILE}"