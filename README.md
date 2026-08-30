# The hc2 Programming Language

hc2 is a memory-safe systems language. Every pointer is a capability checked
at run time — no garbage collector, no borrow checker — and a violation stops
the program instead of corrupting it.

The compiler is written in hc2 and compiles itself. It has no dependencies —
its own assembler and linker are inside — and it emits static ELF for
`linux/amd64` and `linux/arm64`, and self-signed Mach-O for `macos/arm64`.

```hc2
import "sys";
import "heap";

I32 main() {
    U8* buf = heap.alloc(4096);
    defer heap.free(buf);              // runs at end of block

    I64 n = sys.read(0, buf);          // raw syscall — no libc anywhere
    U8* line = buf[0 : n];             // slice: same memory, narrower window
    "read %d bytes: %s", line.len, line;   // print is a statement; %s needs no NUL

    line[n] = 0;                       // one byte past the window
    return 0;
}
```

### Install

#### Linux (x86-64 / arm64)

The only external tools ever used are the system assembler and linker, once,
to hatch the checked-in bootstrap assembly. From then on the compiler builds
itself:

```sh
sh bootstrap/build.sh -v                # -> src/build/hc2c; -v verifies the fixpoint
./src/build/hc2c build -o hc2 src/hc2   # the compiler, built by itself
```

#### macOS (Apple Silicon)

```sh
sh bootstrap/build.sh -v                # -> src/build/hc2c; Docker only if no seed yet
./src/build/hc2c build -o hc2 src/hc2
```

#### Docker (any host, including Windows)

```sh
docker build --platform linux/amd64 -t hc2 .
docker run --rm -it --platform linux/amd64 -v "$PWD":/src hc2 bash
```

### Usage

```
hc2 build [-o out] [-target p] [dir]   compile a package tree, rebuilding what changed
hc2 clean [dir]                        drop that project's build cache
```

A program is a directory — all its `.hc2` files form one package. `import
"path"` names a directory relative to the project root (the nearest directory
at or above the built one holding an `hc2.root` file); what the project does
not have is taken from the language root beside the compiler binary.
Cross-compiling is one flag: `-target linux/arm64`. `hc2 help` prints the
rest.

### Documentation

**[docs/docs-ja.md](docs/docs-ja.md)** (Japanese)

### Contributing

hc2 is an experiment, not yet a project asking for patches. Bug reports and
questions are welcome as issues.
