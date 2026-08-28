#!/bin/sh

# Smoke test running *inside* a vmsh virtual machine, on the very kernel
# that the action just built. Being able to get here at all is most of
# the test: it means the image boots, brings up virtio-console, and mounts
# the host's file system via virtiofs.
#
#   $1  the action's `build-dir` output
#   $2  the kernel release that we expect to be running
#   $3  whether kernel modules were built

set -eu

build="${1}"
expected="${2}"
modules="${3}"

release=$(uname -r)
echo "running kernel ${release}"

if [ "${release}" != "${expected}" ]; then
  echo "expected to be running ${expected}, but found ${release}" >&2
  exit 1
fi

grep --quiet "${release}" /proc/version

if [ "${modules}" = "true" ]; then
  module="${build}/lib/modules/${release}/kernel/drivers/net/dummy.ko"
  # A module only loads if it was built against exactly this kernel, so
  # this checks that image and modules are in sync.
  insmod "${module}"
  grep --quiet '^dummy ' /proc/modules
  rmmod dummy
  echo "loaded and unloaded ${module}"
fi

echo "smoke test passed"
