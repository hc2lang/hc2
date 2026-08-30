#!/bin/sh
# Regenerate bootstrap/hc2c_<os>_<arch>.s for all targets from src/hc2.
# Three generations: codegen changes make gen1 differ from gen2, so the
# fixpoint gate is cmp(gen2, gen3).
set -eu

cd "$(dirname "$0")/.."
mkdir -p src/build
rm -f src/build/rb*.s src/build/rb0 src/build/rb1 src/build/rb2
S=src/hc2

sh bootstrap/build.sh src/build/rb0 > /dev/null
src/build/rb0 -S src/build/rb1.s $S
src/build/rb0 --link src/build/rb1 src/build/rb1.s > /dev/null
chmod +x src/build/rb1
src/build/rb1 -S src/build/rb2.s $S
src/build/rb1 --link src/build/rb2 src/build/rb2.s > /dev/null
chmod +x src/build/rb2
src/build/rb2 -S src/build/rb3.s $S

if ! cmp -s src/build/rb2.s src/build/rb3.s; then
  echo "refusing to update: gen2 and gen3 disagree, the compiler is not a fixpoint" >&2
  exit 1
fi

case "$(uname -s)/$(uname -m)" in
  Darwin/arm64)  native=macos/arm64 ;;
  Linux/aarch64) native=linux/arm64 ;;
  *)             native=linux/amd64 ;;
esac
for t in linux/amd64 linux/arm64 macos/arm64; do
  art=bootstrap/hc2c_$(echo "$t" | tr / _).s
  if [ "$t" = "$native" ]; then
    cp -f src/build/rb3.s "$art"
  else
    src/build/rb2 -target "$t" -S "$art" $S
  fi
done

sh bootstrap/build.sh -v > /dev/null
echo "artifacts updated for all targets (gen2 == gen3, native re-verified)"
