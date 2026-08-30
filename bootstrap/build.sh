#!/bin/sh
# Build the hc2 compiler from the checked-in assembly.
#
#   sh bootstrap/build.sh [output]        default: src/build/hc2c
#   sh bootstrap/build.sh -v [output]     also verify the artifact
#
set -eu

cd "$(dirname "$0")/.."
verify=""
if [ "${1:-}" = "-v" ]; then verify=1; shift; fi
out=${1:-src/build/hc2c}
mkdir -p src/build
# the compiler is a package tree: imports drive the build order
SRC=src/hc2

if [ "$(uname -s)" = Darwin ]; then
  if [ "$(uname -m)" != arm64 ]; then
    echo "macos/amd64 is not a target; macOS means Apple Silicon here" >&2
    exit 1
  fi
  ART=bootstrap/hc2c_macos_arm64.s
  seed=""
  for c in "$out" src/build/hc2c-mac; do
    if [ -x "$c" ] && "$c" help >/dev/null 2>&1; then seed=$c; break; fi
  done
  if [ -n "$seed" ]; then
    "$seed" --link -target macos/arm64 "$out" "$ART" > /dev/null
  else
    if ! docker info >/dev/null 2>&1; then
      echo "hatching $ART needs an hc2 --link: no working compiler in src/build," >&2
      echo "and docker (for a throwaway Linux one) is not running" >&2
      exit 1
    fi
    image=gcc:14
    docker image inspect hc2 >/dev/null 2>&1 && image=hc2
    docker run --platform linux/amd64 --rm -e OUT="$out" -v "$PWD":/src -w /src "$image" sh -c '
      sh bootstrap/build.sh src/build/hc2c-boot > /dev/null &&
      src/build/hc2c-boot --link -target macos/arm64 "$OUT" bootstrap/hc2c_macos_arm64.s > /dev/null'
  fi
  chmod +x "$out"
else
  AS=${AS:-as}
  LD=${LD:-ld}
  # one artifact per os/arch pair; the machine picks its own
  case "$(uname -m)" in
    aarch64|arm64) ART=bootstrap/hc2c_linux_arm64.s; ASFLAGS="" ;;
    *)             ART=bootstrap/hc2c_linux_amd64.s; ASFLAGS="--64" ;;
  esac
  $AS $ASFLAGS -o src/build/boot.o "$ART"
  $LD -static -o "$out" src/build/boot.o
fi
echo "built $out from $ART"

if [ -n "$verify" ]; then
  "$out" -S src/build/verify.s $SRC
  if cmp -s src/build/verify.s "$ART"; then
    echo "verified: it regenerates the artifact exactly"
  else
    echo "MISMATCH: $ART is not what src/hc2/ produces" >&2
    exit 1
  fi
fi
