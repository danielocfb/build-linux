#!/bin/bash

# Verify the artifacts that the action produced in its build directory.
#
# Inputs are provided via the environment, mirroring the action's inputs:
#   BUILD_DIR  the action's `build-dir` output
#   VMLINUX    whether the `vmlinux` input was set
#   MODULES    whether the `modules` input was set
#   PATCHES    whether the `patches` input was set

set -eu -o pipefail

: "${BUILD_DIR:?}"
: "${VMLINUX:=false}"
: "${MODULES:=false}"
: "${PATCHES:=false}"

fail() {
  echo "::error::${1}"
  exit 1
}

[ -d "${BUILD_DIR}" ] || fail "build directory '${BUILD_DIR}' does not exist"

# A kernel image is always expected, and it is never *that* small.
image="${BUILD_DIR}/bzImage"
[ -f "${image}" ] || fail "no bzImage in '${BUILD_DIR}'"
size=$(stat --format=%s "${image}")
[ "${size}" -gt $((256 * 1024)) ] || fail "bzImage is suspiciously small (${size} bytes)"

if [ "${VMLINUX}" = "true" ]; then
  # `make install` places these, `vmlinux` itself is copied alongside.
  vmlinuxes=("${BUILD_DIR}"/boot/vmlinux-*)
  [ ${#vmlinuxes[@]} -eq 1 ] || fail "expected exactly one boot/vmlinux-*, found ${#vmlinuxes[@]}"
  file --brief "${vmlinuxes[0]}" | grep --quiet '^ELF ' \
    || fail "'${vmlinuxes[0]}' is not an ELF image"

  release=$(basename "${vmlinuxes[0]}")
  release=${release#vmlinux-}
  for artifact in "System.map-${release}" "vmlinuz-${release}"; do
    [ -f "${BUILD_DIR}/boot/${artifact}" ] || fail "no boot/${artifact}"
  done
else
  [ ! -e "${BUILD_DIR}/boot" ] || fail "boot/ present despite vmlinux input being unset"
fi

if [ "${MODULES}" = "true" ]; then
  modules=("${BUILD_DIR}"/lib/modules/*)
  [ ${#modules[@]} -eq 1 ] || fail "expected exactly one lib/modules/*, found ${#modules[@]}"
  [ -f "${modules[0]}/kernel/drivers/net/dummy.ko" ] || fail "no dummy.ko installed"
  # These are symbolic links into the (transient) build directory and the
  # action is expected to remove them.
  for link in build source; do
    [ ! -e "${modules[0]}/${link}" ] || fail "dangling '${link}' link was not removed"
  done
else
  [ ! -e "${BUILD_DIR}/lib" ] || fail "lib/ present despite modules input being unset"
fi

# The kernel source tree is only around if the build was not served from
# the cache.
if [ "${PATCHES}" = "true" ] && [ -d linux ]; then
  [ -f linux/build-linux-marker ] || fail "patches were not applied to the source tree"
  subjects=$(git -C linux log --format=%s --max-count=2 | tac)
  expected=$'Add localversion marker\nAdd marker file'
  [ "${subjects}" = "${expected}" ] || fail "unexpected patch order:"$'\n'"${subjects}"
fi

echo "build directory contents:"
find "${BUILD_DIR}" -type f -printf '%10s %p\n' | sort --key=2
