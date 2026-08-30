#!/bin/sh
# hc2 test runner: [HC2_TARGET=linux/amd64|linux/arm64|macos/arm64] sh tests/run.sh
set -eu

TARGET=${HC2_TARGET:-linux/amd64}
case "$TARGET" in
  linux) TARGET=linux/amd64 ;;
  la64)  TARGET=linux/arm64 ;;
  macos) TARGET=macos/arm64 ;;
esac

ARMSKIP="032_asm 033_asm_syscall 034_asm_clobber 036_asm_mem 037_asm_frame 038_asm_width 039_asm_menu 040_asm_rbp 075_asm_menu 088_unsafe_forge 090_unsafe_frame"

if [ "$TARGET" = macos/arm64 ]; then
  if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
    echo "HC2_TARGET=macos/arm64 needs an Apple Silicon host"; exit 1
  fi
  cd "$(dirname "$0")/.."
elif [ "${HC2_IN_CONTAINER:-}" != "1" ]; then
  cd "$(dirname "$0")/.."
  case "$TARGET" in
    linux/amd64) def=hc2 ;;
    linux/arm64) def=hc2-a64 ;;
    *) echo "unknown HC2_TARGET $TARGET (linux/amd64, linux/arm64, macos/arm64)"; exit 1 ;;
  esac
  plat=$TARGET
  image=${HC2_IMAGE:-}
  if [ -z "$image" ]; then
    if docker image inspect "$def" >/dev/null 2>&1; then image=$def; else image=gcc:14; fi
  fi
  exec docker run --platform "$plat" --rm -e HC2_IN_CONTAINER=1 -e HC2_TARGET="$TARGET" \
    -v "$PWD":/src -w /src "$image" sh tests/run.sh
fi

mkdir -p src/build
SRC=src/hc2

HC=./src/build/hc2c
ASFLAGS=""
EXTLINK=1
ART=bootstrap/hc2c_linux_amd64.s
SKIP=""
case "$TARGET" in
  linux/amd64) ASFLAGS="--64" ;;
  linux/arm64) ART=bootstrap/hc2c_linux_arm64.s; SKIP=$ARMSKIP ;;
  macos/arm64) HC=./src/build/hc2c-mac; EXTLINK=0; ART=bootstrap/hc2c_macos_arm64.s; SKIP=$ARMSKIP ;;
esac

if [ "$TARGET" = macos/arm64 ]; then
  echo "== seed: cross-build a native compiler from x86 (container)"
  image=${HC2_IMAGE:-}
  if [ -z "$image" ]; then
    if docker image inspect hc2 >/dev/null 2>&1; then image=hc2; else image=gcc:14; fi
  fi
  if docker info >/dev/null 2>&1; then
    docker run --platform linux/amd64 --rm -v "$PWD":/src -w /src "$image" sh -c '
      sh bootstrap/build.sh src/build/hc2c-boot > /dev/null &&
      src/build/hc2c-boot -target macos/arm64 -S src/build/cross_mac.s src/hc2 &&
      src/build/hc2c-boot --link -target macos/arm64 src/build/hc2c-mac src/build/cross_mac.s > /dev/null'
    chmod +x src/build/hc2c-mac
  elif [ -x src/build/hc2c-mac ]; then
    echo "   (no docker; reseeding from $ART with the existing compiler)"
    ./src/build/hc2c-mac --link src/build/hc2c-mac "$ART" > /dev/null
    chmod +x src/build/hc2c-mac
    rm -f src/build/cross_mac.s
  else
    echo "need docker once to seed src/build/hc2c-mac"; exit 1
  fi
else
  echo "== bootstrap from assembly (no C)"
  sh bootstrap/build.sh "$HC" > /dev/null
fi

link() {
  out=$1; shift
  if [ "$EXTLINK" = 1 ]; then
    "$HC" -S "$out.s" "$@" && as $ASFLAGS -o "$out.o" "$out.s" && ld -static -o "$out" "$out.o"
  else
    "$HC" -S "$out.s" "$@" && "$HC" --link "$out" "$out.s" > /dev/null && chmod +x "$out"
  fi
}

pass=0 fail=0 skip=0
for t in tests/[0-9]*; do
  case "$t" in *.out|*.exit|*.err|*.cerr) continue ;; esac
  name=$(basename "$t" .hc2)
  case " $SKIP " in *" $name "*) skip=$((skip+1)); continue ;; esac

  if [ -f "tests/$name.cerr" ]; then
    if link "src/build/$name" "$t" > "src/build/$name.err" 2>&1; then
      echo "FAIL $name (expected a compile error)"
      fail=$((fail+1))
    elif grep -qF "$(cat "tests/$name.cerr")" "src/build/$name.err"; then
      echo "ok   $name"
      pass=$((pass+1))
    else
      echo "FAIL $name (wrong compile error)"
      sed 's/^/    /' "src/build/$name.err" | head -3
      fail=$((fail+1))
    fi
    continue
  fi

  want_exit=0
  [ -f "tests/$name.exit" ] && want_exit=$(cat "tests/$name.exit")

  ok=0; link "src/build/$name" "$t" > "src/build/$name.err" 2>&1 && ok=1
  if [ "$ok" -ne 1 ]; then
    echo "FAIL $name (compile)"
    sed 's/^/    /' "src/build/$name.err" | head -5
    fail=$((fail+1)); continue
  fi

  set +e
  got=$("./src/build/$name" 2>&1)
  got_exit=$?
  set -e
  if [ "$got" = "$(cat "tests/$name.out")" ] && [ "$got_exit" -eq "$want_exit" ]; then
    echo "ok   $name"
    pass=$((pass+1))
  else
    echo "FAIL $name"
    printf '    want exit %s, got %s\n    want: %s\n    got:  %s\n' \
      "$want_exit" "$got_exit" "$(cat "tests/$name.out")" "$got"
    fail=$((fail+1))
  fi
done
if [ "$skip" -gt 0 ]; then echo "     ($skip x86-asm tests not meaningful on $TARGET)"; fi

echo "== programs the checker must reject"
for e in tests/s1e_*.hc2; do
  ename=$(basename "$e" .hc2)
  set +e
  eout=$("$HC" -S src/build/e.s "$e" 2>&1)
  set -e
  if printf '%s' "$eout" | grep -qF "$(cat "tests/$ename.cerr")"; then
    echo "ok   $ename"
    pass=$((pass+1))
  else
    echo "FAIL $ename (should have been rejected)"
    printf '    %s\n' "$eout" | head -3
    fail=$((fail+1))
  fi
done

if [ "$EXTLINK" = 1 ]; then
  echo "== linker (no as, no ld)"
  lnk_pass=0
  for t in tests/[0-9]*.hc2; do
    name=$(basename "$t" .hc2)
    [ -f "tests/$name.cerr" ] && continue
    case " $SKIP " in *" $name "*) continue ;; esac
    want_exit=0
    [ -f "tests/$name.exit" ] && want_exit=$(cat "tests/$name.exit")
    "$HC" --link "src/build/$name.elf" "src/build/$name.s" > /dev/null
    chmod +x "src/build/$name.elf"
    set +e
    got=$("./src/build/$name.elf" 2>&1)
    got_exit=$?
    set -e
    if [ "$got" = "$(cat "tests/$name.out")" ] && [ "$got_exit" -eq "$want_exit" ]; then
      lnk_pass=$((lnk_pass+1))
    else
      echo "FAIL $name (self-linked)"
      fail=$((fail+1))
    fi
  done
  echo "ok   $lnk_pass programs run as self-linked executables"
  pass=$((pass+1))

  "$HC" --link src/build/hc2c.elf "$ART" > /dev/null
  chmod +x src/build/hc2c.elf
  if ./src/build/hc2c.elf -S src/build/selflink.s src/hc2 && cmp -s src/build/selflink.s "$ART"; then
    echo "ok   the self-linked compiler reproduces the artifact ($(wc -c < src/build/hc2c.elf) byte binary)"
    pass=$((pass+1))
  else
    echo "FAIL self-linked compiler"
    fail=$((fail+1))
  fi
fi

echo "== incremental build"
rm -rf src/build/cache && mkdir -p src/build/cache
cold=$("$HC" --build src/build/cache src/build/inc1 src/hc2)
warm=$("$HC" --build src/build/cache src/build/inc2 src/hc2)
chmod +x src/build/inc1
N=${cold#built }; N=${N%% *}
if [ "$cold" = "built $N packages, reused 0" ] && \
   [ "$warm" = "built 0 packages, reused $N" ] && \
   ./src/build/inc1 -S src/build/inc.s src/hc2 && \
   { [ -z "$ART" ] || cmp -s src/build/inc.s "$ART"; }; then
  echo "ok   $cold, then $warm; the result reproduces the artifact"
  pass=$((pass+1))
else
  echo "FAIL incremental build ($cold / $warm)"
  fail=$((fail+1))
fi

cp src/hc2/gen/gen.hc2 src/build/gen.bak
printf '\nU0 _cachetest() {\n  I64 x = 1;\n}\n' >> src/hc2/gen/gen.hc2
body=$("$HC" --build src/build/cache src/build/inc3 src/hc2)
cp src/build/gen.bak src/hc2/gen/gen.hc2
if [ "$body" = "built 1 packages, reused $((N-1))" ]; then
  echo "ok   a body edit rebuilds one package"
  pass=$((pass+1))
else
  echo "FAIL body edit rebuilt too much ($body)"
  fail=$((fail+1))
fi

echo "== the command line"
rm -rf src/.hc2cache
b1=$("$HC" build -o src/build/cmd.elf src/hc2)
b2=$("$HC" build -o src/build/cmd.elf src/hc2)
if [ "$b1" = "built $N packages, reused 0" ] && [ "$b2" = "built 0 packages, reused $N" ] &&
   ./src/build/cmd.elf help | grep -q "hc2 build"; then
  echo "ok   hc2 build is incremental and produces a runnable program"
  pass=$((pass+1))
else
  echo "FAIL hc2 build ($b1 / $b2)"
  fail=$((fail+1))
fi
if "$HC" build -target nosuch -o src/build/x.elf tests/055_globals 2>&1 |
   grep -q "unknown target nosuch"; then
  echo "ok   a target this compiler does not know is refused by name"
  pass=$((pass+1))
else
  echo "FAIL -target fell back to another platform"
  fail=$((fail+1))
fi
if "$HC" build -target macos/amd64 -o src/build/x.elf tests/055_globals 2>&1 |
   grep -q "unsupported target macos/amd64"; then
  echo "ok   a pair nothing emits code for is refused"
  pass=$((pass+1))
else
  echo "FAIL macos/amd64 was not refused"
  fail=$((fail+1))
fi
if "$HC" clean src/hc2 | grep -q "removed $N"; then
  echo "ok   hc2 clean"
  pass=$((pass+1))
else
  echo "FAIL hc2 clean"
  fail=$((fail+1))
fi

# roots: skipped on macos — no self_path there, argv[0] does not see through symlinks
if [ "$TARGET" != macos/arm64 ]; then
echo "== roots"
R="$PWD"
rm -rf src/.hc2cache

rm -rf /tmp/proj && mkdir -p /tmp/proj/app /tmp/proj/str
cat > /tmp/proj/str/str.hc2 <<'EOF'
U8* who() {
    return "the project str";
}
EOF
cat > /tmp/proj/app/main.hc2 <<'EOF'
import "heap";
import "str";

I32 main() {
    U8* b = heap.alloc(2);
    b[0] = 'h';
    "%s / %c\n", str.who(), b[0];
    return 0;
}
EOF
touch /tmp/proj/hc2.root
ln -s "$R/$(echo "$HC" | sed 's|^\./||')" /tmp/proj/hc2
got=$( (cd /tmp/proj && ./hc2 build -o app.exe ./app > /dev/null && chmod +x app.exe && ./app.exe) 2>&1 )
if [ "$got" = "the project str / h" ]; then
  echo "ok   a symlinked compiler carries its language root; the project str wins"
  pass=$((pass+1))
else
  echo "FAIL symlinked compiler / std override ($got)"
  fail=$((fail+1))
fi

rm -rf /tmp/scratch && mkdir /tmp/scratch
cat > /tmp/scratch/main.hc2 <<'EOF'
import "heap";

I32 main() {
    U8* b = heap.alloc(1);
    b[0] = '!';
    "%c\n", b[0];
    return 0;
}
EOF
got=$( (cd /tmp/scratch && "$R/src/build/$(basename "$HC")" build -o s.exe . > /dev/null && chmod +x s.exe && ./s.exe) 2>&1 )
if [ "$got" = "!" ]; then
  echo "ok   a bare directory with no marker builds as its own root"
  pass=$((pass+1))
else
  echo "FAIL scratch build ($got)"
  fail=$((fail+1))
fi
fi

echo "== self-host"
if [ "$EXTLINK" = 1 ]; then
  if "$HC" -S src/build/self.s $SRC 2> src/build/self.err &&
     as $ASFLAGS -o src/build/self.o src/build/self.s 2>> src/build/self.err &&
     ld -static -o src/build/hc2c-self src/build/self.o 2>> src/build/self.err &&
     ./src/build/hc2c-self -S src/build/self2.s $SRC 2>> src/build/self.err; then
    if cmp -s src/build/self.s "$ART" && cmp -s src/build/self.s src/build/self2.s; then
      echo "ok   fixpoint (source -> assembly == $ART, and stable, $(wc -c < src/build/self.s) bytes)"
      pass=$((pass+1))
    else
      echo "FAIL fixpoint"
      cmp src/build/self.s "$ART" | head -2 | sed 's/^/    /'
      fail=$((fail+1))
    fi
  else
    echo "FAIL self-host"
    sed 's/^/    /' src/build/self.err | head -5
    fail=$((fail+1))
  fi
else
  if "$HC" -S src/build/self.s $SRC 2> src/build/self.err &&
     "$HC" --link src/build/hc2c-self src/build/self.s > /dev/null &&
     chmod +x src/build/hc2c-self &&
     ./src/build/hc2c-self -S src/build/self2.s $SRC 2>> src/build/self.err; then
    ok=1
    cmp -s src/build/self.s "$ART" || ok=0
    cmp -s src/build/self.s src/build/self2.s || ok=0
    if [ -f src/build/cross_mac.s ]; then
      cmp -s src/build/self.s src/build/cross_mac.s || ok=0
      cmp -s src/build/hc2c-self "$HC" || ok=0
      note=", == the x86 cross build (assembly and binary)"
    else
      note=""
    fi
    if [ "$ok" = 1 ]; then
      echo "ok   fixpoint (source -> assembly == $ART, and stable$note, $(wc -c < src/build/self.s) bytes)"
      pass=$((pass+1))
    else
      echo "FAIL fixpoint"
      cmp src/build/self.s "$ART" | head -2 | sed 's/^/    /'
      fail=$((fail+1))
    fi
  else
    echo "FAIL self-host"
    sed 's/^/    /' src/build/self.err | head -5
    fail=$((fail+1))
  fi
fi

echo "== $pass passed, $fail failed ($TARGET)"
[ "$fail" -eq 0 ]
