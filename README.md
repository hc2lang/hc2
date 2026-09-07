# The hc2 Programming Language

hc2 is a small systems language that looks and feels like C, except that pointers are checked at runtime.
Going out of bounds or touching freed memory stops the program with an error instead of corrupting it.
The cost is a few extra instructions per access.

A pointer knows its bounds, whether it's writable, and which allocation it belongs to. 
There's no GC, no borrow checker, and nothing to annotate.

Targets linux/amd64, linux/arm64, and macos/arm64.

```hc2
import "heap";

I32 main() {
    U8* buf = heap.alloc(16);
    buf[0] = 'h'; buf[1] = 'i';
    "%s in a %d-byte buffer\n", buf[0 : 2], buf.len;

    U8* alias = buf;
    heap.free(buf);
    "%c\n", alias[0]; // runtime error
    return 0;
}
```

```
hi in a 16-byte buffer
main.hc2:10: trap: use after free
```

### Documentation

- **[docs/docs.md](docs/docs.md)** — English (automatic translation)
- **[docs/docs-ja.md](docs/docs-ja.md)** — 日本語 (original)

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

A program is a directory, all its `.hc2` files form one package. `import
"path"` names a directory relative to the project root (the nearest directory
at or above the built one holding an `hc2.root` file); what the project does
not have is taken from the language root beside the compiler binary.

### Contributing

hc2 is an experiment, not yet a project asking for patches. Bug reports and
questions are welcome as issues.
