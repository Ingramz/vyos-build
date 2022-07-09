#!/bin/bash

# This script builds the kernel modules for RTSP connection tracking.
#
# Debian includes this module as a DKMS module package under nat-rtsp-dkms,
# but it seems nontrivial to make a mkbmdeb package without having target
# kernel already installed.
#
# Since the kernel here is already built from source and the kernel module
# has no additional dependencies, we can use the upstream sources and
# make our own package.

CWD=$(pwd)

# Source directory
RTSP_LINUX_SRC="${CWD}/rtsp-linux"
KERNEL_VAR_FILE=${CWD}/kernel-vars

if [ ! -d ${RTSP_LINUX_SRC} ]; then
    echo "rtsp-linux repository missing"
    exit 1
fi

if [ ! -f ${KERNEL_VAR_FILE} ]; then
    echo "Kernel variable file '${KERNEL_VAR_FILE}' does not exist, run ./build_kernel.sh first"
    exit 1
fi

. ${KERNEL_VAR_FILE}

# Debian package will use the descriptive Git commit as version
GIT_COMMIT=$(cd ${RTSP_LINUX_SRC}; git describe --always)

# Build up Debian related variables required for packaging
DEBIAN_NAME="rtsp-linux"
DEBIAN_ARCH=$(dpkg --print-architecture)
DEBIAN_DIR="${CWD}/${DEBIAN_NAME}_${GIT_COMMIT}_${DEBIAN_ARCH}"
DEBIAN_CONTROL="${DEBIAN_DIR}/DEBIAN/control"
DEBIAN_POSTINST="${CWD}/${DEBIAN_NAME}.postinst"
DEBIAN_MODULE_DIR=${DEBIAN_DIR}/lib/modules/${KERNEL_VERSION}${KERNEL_SUFFIX}/updates/net/netfilter

echo "I: Compile Kernel module for ${DEBIAN_NAME}"
make -C ${RTSP_LINUX_SRC} -j $(getconf _NPROCESSORS_ONLN) KERNELDIR=${KERNEL_DIR}

if [ "x$?" != "x0" ]; then
  exit 1
fi

# build Debian package
echo "I: Building Debian package ${DEBIAN_NAME}"

# remove Debian package folder and deb file from previous runs
rm -rf ${DEBIAN_DIR}*

mkdir -p ${DEBIAN_MODULE_DIR}

cp "${RTSP_LINUX_SRC}/nf_conntrack_rtsp.ko" "${RTSP_LINUX_SRC}/nf_nat_rtsp.ko" ${DEBIAN_MODULE_DIR}

# delete non required files which are also present in the kernel package
# and thus lead to duplicated files
find ${DEBIAN_DIR} -name "modules.*" | xargs rm -f

echo "#!/bin/sh" > ${DEBIAN_POSTINST}
echo "/sbin/depmod -a ${KERNEL_VERSION}${KERNEL_SUFFIX}" >> ${DEBIAN_POSTINST}

fpm --input-type dir --output-type deb --name ${DEBIAN_NAME} \
    --version ${GIT_COMMIT} --deb-compression gz \
    --maintainer "VyOS Package Maintainers <maintainers@vyos.net>" \
    --description "Connection tracking and NAT support for RTSP" \
    --depends linux-image-${KERNEL_VERSION}${KERNEL_SUFFIX} \
    --license "GPL2" -C ${DEBIAN_DIR} --after-install ${DEBIAN_POSTINST}

echo "I: Cleanup ${DEBIAN_NAME} package source"
if [ -d ${DEBIAN_DIR} ]; then
    rm -rf ${DEBIAN_DIR}
fi
