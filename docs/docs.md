# The hc2 Programming Language

> This document is an automatic translation of the Japanese original, [docs-ja.md](docs-ja.md). Where the two disagree, the Japanese version takes precedence.

hc2 is a programming language that aims to be as small and fast as C while being memory safe.

Pointers in hc2 are not raw addresses. They carry bounds, permissions, and a generation.
Out-of-bounds access and use of freed memory are caught by runtime checks, not by a compiler analysis and not by a garbage collector.
There are no ownership annotations and no lifetimes to write.

Linux and macOS are supported. For Linux (amd64 / arm64) the compiler produces a single statically linked executable;
for macOS (arm64) it produces a signed binary that runs as is.

```hc2
import "heap";

I32 main() {
    U8* req = heap.alloc(64);
    req[0] = 'G'; req[1] = 'E'; req[2] = 'T';
    "%d-byte request, method %c%c%c\n", req.len, req[0], req[1], req[2];

    U8* view = req;      // copy the pointer
    heap.free(req);      // one write to the header revokes every copy
    "%c\n", view[0];     // in C this reads freed memory and "works"; in hc2 it is a runtime error
    return 0;
}
```

```
64-byte request, method GET
main.hc2:10: trap: use after free
```

## Contents

- [Hello, world](#hello-world)
- [Compiling and running](#compiling-and-running)
- [Comments](#comments)
- [Functions](#functions)
- [Symbol visibility](#symbol-visibility)
- [Variables](#variables)
- [Types](#types)
    - [Primitive types](#primitive-types)
    - [Numbers](#numbers)
    - [Floating point](#floating-point)
    - [Booleans](#booleans)
    - [Strings](#strings)
    - [Casts and untyped constants](#casts-and-untyped-constants)
- [Pointers](#pointers)
    - [Slices](#slices)
    - [Pointer arithmetic](#pointer-arithmetic)
    - [null](#null)
- [Arrays](#arrays)
    - [Multidimensional arrays](#multidimensional-arrays)
- [Structs](#structs)
    - [Struct literals](#struct-literals)
    - [Private fields](#private-fields)
- [Unions](#unions)
- [Variadic functions](#variadic-functions)
- [Function pointers](#function-pointers)
- [Importing packages](#importing-packages)
- [Statements and expressions](#statements-and-expressions)
    - [The print statement](#the-print-statement)
    - [if](#if)
    - [for loops](#for-loops)
    - [switch](#switch)
    - [defer](#defer)
    - [unsafe blocks](#unsafe-blocks)
- [Memory management](#memory-management)
    - [The heap package](#the-heap-package)
    - [free and revocation](#free-and-revocation)
    - [Arenas with mark and release](#arenas-with-mark-and-release)
    - [Minting capabilities with sys.from_raw](#minting-capabilities-with-sysfrom_raw)
- [Runtime errors (traps)](#runtime-errors-traps)
- [Runtime](#runtime)
    - [Command-line arguments](#command-line-arguments)
- [Inline assembly](#inline-assembly)
- [Packages and targets](#packages-and-targets)
- [Appendix](#appendix)
    - [Limits](#limits)

## Hello, world

```hc2
I32 main() {
    "Hello, world!\n";
    return 0;
}
```

Two things are already unusual here. There is no print function:
a string literal is itself the print statement, and it takes `printf`-style arguments after a comma (see [The print statement](#the-print-statement)).
And `main` returns an `I32`.

Save this as `main.hc2` in a directory of its own and build it:

```sh
mkdir hello && cd hello
# ... write main.hc2 ...
hc2 build -o hello .
./hello
```

## Compiling and running

In hc2 a program is a directory, not a file. The compiler takes a directory,
compiles every `.hc2` file in it as one package, follows the imports,
and links one executable:

```
hc2 build [-o out] [-target p] [dir]
                            compile a package tree, rebuilding what changed
hc2 clean [dir]             drop that project's build cache
```

- Without `-o` the output is named after the directory (`hc2 build hello` writes `./hello`; `.` becomes `./a.out`).
- The output is one statically linked executable.
- Compiled packages are cached per package in `.hc2cache` at the project root.
- `-target` cross-compiles. See [Packages and targets](#packages-and-targets).

## Comments

```hc2
// a comment runs to the end of the line
I64 x = 1;   // and can follow code
```

`//` is the only kind of comment. There is no `/* */` block comment.

## Functions

```hc2
I32 main() {
    "fib(10) = %d\n", fib(10);
    return 0;
}

I32 fib(I32 n) {
    if n < 2 {
        return n;
    }
    return fib(n - 1) + fib(n - 2);
}
```

A function is `return-type name(type param, ...) { body }`.
There are no forward declarations and no prototypes. A top-level name in a package is visible from every file of that package, regardless of order.

- The number of arguments and every type are checked strictly.
- There is no overloading and there are no default arguments.
- Structs cannot be passed by value. Pass a pointer.
- A function can return a struct, but the call must directly initialize a declaration.

## Symbol visibility

A top-level name that starts with an underscore is private to its package. Every other name is exported.

```hc2
I64 counter = 0;      // exported: other packages can read and write pkg.counter
I64 _step = 1;        // private: visible only inside this package

U0 tick() {           // exported
    counter = counter + _step;
}

U0 _reset() {         // private
    counter = 0;
}
```

The rule applies to functions, constants, mutable globals, types, and struct fields.

```hc2
struct Pt {
    I64 x;
    I64 y;
    I64 _tag;     // visible only from files of this package
}
```

## Variables

```hc2
I64 total = 0;
U8 c = 'x';
Bool ok = total == 0;
I64 arr[2] = {10, 20};
```

A variable is declared as `type name = initial value;`.
The initial value cannot be omitted. Locals, globals, and constants are all
initialized at their declaration, so hc2 has no uninitialized variables.

## Types

### Primitive types

| Type  | Size (bytes) | Meaning |
|-------|------|-------------|
| `U0`  | 0 | no value, zero size |
| `Bool`| 1 | `true` or `false` |
| `I8` `I16` `I32` `I64` | 1 2 4 8 | signed integers |
| `U8` `U16` `U32` `U64` | 1 2 4 8 | unsigned integers |
| `F64` | 8 | IEEE 754 double precision, see [Floating point](#floating-point) |
| `T*`  | 32 | a capability to a value of type `T`, see [Pointers](#pointers) |

That is all of them. There is no `enum` (use `const I64 NAME = n;`),
no type alias, and no separate string type (a string is a `U8*`).
There is exactly one floating-point type, `F64`.

### Numbers

```hc2
I64 a = 42;             // decimal
I64 b = 0xbeef;         // hexadecimal
U8 g = 'G';             // a character literal is an integer constant
I64 neg = -5;
```

There are no binary (`0b`) or octal literals (a leading `0` is just decimal).
There are no digit separators and no literal suffixes.

Arithmetic wraps at the width of the type:

```hc2
U8 x = 200;
x = x + 100;         // 300 wraps to 44 in a U8
"x = %d\n", x;       // x = 44
```

Integer division truncates toward zero. `%` is the remainder:

```hc2
"div: %d rem: %d\n", 17 / 5, 17 % 5;    // div: 3 rem: 2
```

Dividing by a literal zero is a compile error; dividing by a variable that holds zero is a runtime error.

Shifts follow the sign of the left operand: arithmetic for signed types, logical for unsigned.

```hc2
I64 m = -8;
"sar %d\n", m >> 1;      // sar -4
U64 u = 16;
"shr %d\n", u >> 2;      // shr 4
```

### Floating point

`F64` is IEEE 754 double precision. There is no other width.

```hc2
F64 x = 1.5;
F64 k = 1.0e-3;              // exponents work; 1e9 is a float too
"%f\n", x * 2.0 + 0.25;      // 3.250000
```

- A literal needs digits on both sides of the point (`1.` and `.5` do not parse). The exponent is `e` followed by a sign and digits.
- The only operations are `+ - * /` and comparisons.

### Booleans

`Bool` is a type of its own, distinct from the integers, with exactly two values, `true` and `false`.
Comparisons produce a `Bool`, and the condition of an `if` or `for` must be a `Bool`. An integer cannot be used as a condition.

```hc2
Bool ok = 3 > 2;
if ok {
    "ok\n";
}
```

`&&` and `||` combine `Bool`s and do not evaluate the right side once the left side decides the result.
There is no `!` operator; write a negation as a comparison, `ok == false`.
`Bool` does not cast to any other type.

### Strings

A string is a `U8*`.

```hc2
U8* s = "hello";
"%s has %d bytes\n", s, s.len;      // hello has 5 bytes
"first: %c\n", s[0];                // first: h
U8* head = s[0 : 2];                // a slice is a narrower U8*
"%s\n", head;                       // he
```

Strings are not NUL-terminated; the pointer carries the length. `.len` is the length in bytes.
String literals are read-only: writing to one or freeing one is a runtime error.
The escapes are `\n` `\t` `\r` `\0` `\\` `\"` `\'`, and no others.

There is no string type and no concatenation operator. To build a string, write bytes into a buffer from `heap.alloc`.
Where a NUL terminator is required (a path argument to a system call, for example), use `str.cstr`.

### Casts and untyped constants

There are no implicit conversions.

```hc2
U8 a = 1;
I32 b = 2;
I32 c = a + b;    // error: mixed-type arithmetic (no implicit conversions; write the `as`)
```

```hc2
"300 as U8 = %d\n", 300 as U8;        // 44
I64 v = -5;
"v as U32 = %d\n", v as U32;          // 4294967291
"wrap %d\n", big as U8 as I64;        // truncate, then widen again
I32* xs = heap.alloc(64) as I32*;     // pointer to a pointer of another type
```

Three kinds of cast exist.

- Scalar to scalar. `Bool` and `U0` do not cast, and there is no conversion between `U64` and `F64`.
- Pointer to a pointer of another type. This is how the `U8*` from `heap.alloc` becomes a struct pointer.
- Pointer and integer do not convert in either direction. The only way to make a pointer from an address is `sys.from_raw`.

A pointer cast to a struct that holds capabilities (`mem as Pt*`) has conditions.
It must be a heap block, writable, at the block's start or at a multiple of `sizeof(Pt)`,
and the block must not yet hold a type, or must already hold the same one. At the moment of the cast
the block becomes typed for `Pt`, and its capability fields are zeroed (null). From then on,
writing byte by byte into that block's capability region — with `U8*`, for instance — is a runtime error.
The scalar fields' region can still be written.

Conversely, only a heap block can view a struct that holds capabilities as `U8*`;
viewing a stack struct as bytes, as in `&s as U8*`, is a runtime error.

Numeric literals and constants such as `sizeof(...)` are untyped constants: they have no type of their own.
They take the type of the assignment target or the other operand, and a value that does not fit that type is a compile error.

## Pointers

A pointer in hc2 is not a raw address. It is a 32-byte capability that carries,
along with the address, the bounds, permission, and generation that the runtime checks.

| Word | Attribute | Meaning |
|------|-----------|---------|
| 0 | `.addr` | the raw address |
| 1 | `.hdr` | the address of the allocation's header; the lowest bit is the write permission |
| 2 | `.lo`, `.len` | the offset from the start of the allocation to the start of the window, and the window's length in bytes |
| 3 | `.gen` | the generation this capability expects |

Every allocation has a 16-byte header `{length, generation}` immediately before its data.
Every access through a pointer is checked at runtime against both the capability and the header.
Dereferencing null, indexing outside the bounds, or touching freed memory ends the program with a runtime error.

The five attributes (`.addr`, `.hdr`, `.lo`, `.len`, `.gen`) can be read from any pointer and yield plain `I64` values:

```hc2
U8* p = heap.alloc(64);
"%d %d %d\n", p.len, p.lo, p.gen;     // 64 0 1
```

### Slices

`p[lo : hi]` makes a new pointer of the same type that refers to just that range.

```hc2
U8* buf = heap.alloc(64);
I64 n = sys.read(fd, buf);
"read %d: %s", n, buf[0 : n];      // print only what was read
```

A slice cannot widen the window. The new range is checked against the original pointer's window,
so a slice cannot reach memory the original could not. A slice still refers to the original allocation,
so freeing that allocation makes access through the slice a runtime error too.

### Pointer arithmetic

```hc2
Pt* ps = heap.alloc(4 * sizeof(Pt)) as Pt*;
Pt* q = ps + 2;       // in elements: advances 2 * sizeof(Pt) bytes
```

Pointer arithmetic is limited to `+` and `-`, with the pointer on the left and an integer on the right.
The result keeps the bounds of the original pointer, so making a pointer that points outside the window is not an error;
using it is. Pointers cannot be subtracted from each other or compared for order.

### null

`null` is the empty pointer value. It fits any pointer or function-pointer type,
can only be compared with `==` and `!=`, and cannot be cast:

```hc2
U0(I64)* g = null;
if g == null { "not set\n"; }
```

## Arrays

Arrays have a fixed length and are declared C-style, with the brackets after the name.

```hc2
I32 d[4] = {1, 2, 3, 4};
U8* names[3] = {"alpha", "beta", "gamma"};
I64 zeros[8] = {};                       // {} zero-fills
I64 arr[lib.WIDTH] = {};                 // the length may be an imported constant
```

- The length must be a compile-time constant.
- The number of initializers must match exactly. The empty initializer `{}` is the exception.
- Arrays are not values. They cannot be assigned, passed, or returned as a whole.

```hc2
I64 arr[3] = {1, 2, 3};
I64* p = &arr;               // the whole array, bounds included
"%d bytes\n", p.len;         // 24 bytes
```

Indexes are bounds-checked at runtime.

### Multidimensional arrays

```hc2
I32 m[2][3] = {{1, 2, 3}, {4, 5, 6}};
m[1][0] = 40;
I64 cube[2][2][2] = {{{1, 2}, {3, 4}}, {{5, 6}, {7, 8}}};
"%d\n", cube[1][0][1];       // 6
```

In an initializer, every dimension has its own braces (a flat C-style list is not accepted).

## Structs

```hc2
struct Node {
    I64 kind;
    U8* text;
    Node* next;
}
```

Structs are declared at the top level, with no semicolon after the closing brace.
Fields are laid out in declaration order, each aligned, and the size of the struct is rounded up to a multiple of 8.

### Struct literals

Initialization is positional: either fill every field or zero-fill:

```hc2
struct Arena {
    U8* buf;
    I64 used;
}

Arena a = {heap.alloc(4096), 0};    // every field, in order
Arena b = {};                        // all zero
```

### Private fields

A field whose name starts with `_` is private to the package that defines the struct. See [Symbol visibility](#symbol-visibility).

## Unions

A union overlays its members at offset 0. Its size is the largest member rounded up to a multiple of 8:

```hc2
struct TimeDate {
    U32 time;
    I32 date;
}

union Date {
    I64 i64;
    TimeDate td;
}

I32 main() {
    Date d = {};                     // a union has no literal form; only {}
    d.i64 = 0x11223344AABBCCDD;
    "time %x date %x\n", d.td.time as I64, d.td.date as I64;
    // time aabbccdd date 11223344   (little-endian)
    return 0;
}
```

A union exists to reinterpret the same bits as another numeric type.
Its members may only be scalars, or structs whose fields are all scalars.
Capabilities and function pointers cannot be members, because a union would otherwise turn any number into a capability.

An `unsafe union` lifts exactly that restriction. In exchange, every read of a capability member must happen inside an `unsafe { }` block.

## Variadic functions

The last parameter of a function can collect any number of scalar arguments.

```hc2
I64 sum(I64... xs) {
    I64 total = 0;
    for I64 i = 0; i < xs.len / 8; i++ {    // .len is in bytes
        total = total + xs[i];
    }
    return total;
}

I32 main() {
    "sum %d\n", sum(1, 2, 3, 4, 5);   // sum 15
    "sum %d\n", sum();                // sum 0
    return 0;
}
```

Inside the function the variadic parameter is an ordinary pointer (`I64*` in this example).
Indexing, slicing, and reading `.len` all work as usual.
Reading past the arguments that were actually passed is an `out of bounds` runtime error, like with any other pointer.
Over-reading the variadic arguments cannot expose other data on the stack.

## Function pointers

The type of a function is its signature followed by `*`:

```hc2
I32 add(I32 a, I32 b) { return a + b; }
I32 mul(I32 a, I32 b) { return a * b; }

struct OpEnt {
    U8* name;
    I32(I32, I32)* f;
}

const OpEnt OPS[2] = {
    {"add", &add},
    {"mul", &mul},
};

I32 main() {
    I32(I32, I32)* f = &add;      // & makes the value
    "direct %d\n", f(2, 3);       // call it like a function
    f = &mul;
    for I64 i = 0; i < 2; i++ {
        "%s %d\n", OPS[i].name, OPS[i].f(4, 5);
    }
    return 0;
}
```

## Importing packages

A package is a directory of `.hc2` files. All files in the directory share one scope.
A subdirectory is a separate package.

Consider a project laid out like this:

```
myapp/
├── main.hc2
└── geom/            # package "geom"
    ├── point.hc2    # Pt, make
    └── vec.hc2      # dot
```

From `main.hc2`, import the directory name in quotes and use it as a qualifier.

```hc2
import "geom";

I32 main() {
    geom.Pt a = geom.make(3, 4);
    "dot = %d\n", geom.dot(&a, &a);
    return 0;
}
```

## Statements and expressions

### The print statement

A statement that starts with a string literal is a print.

```hc2
"plain text\n";
"%s has %d bytes\n", name, name.len;
"hex: %x  char: %c  100%%\n", 48879, 104;
```

| Format | Argument | Output |
|------|----------|--------|
| `%d` | any integer | signed decimal after widening to `I64` (unsigned values zero-extend: `-5 as U32` prints `4294967291`) |
| `%x` | any integer | lowercase hexadecimal, no `0x`, no padding |
| `%c` | any integer | the low byte as one character |
| `%s` | `U8*` | all `.len` bytes |
| `%f` | `F64` | sign, integer part, six decimals. Special values print as `inf`, `-inf`, `nan` (the sign of a NaN is not printed). Magnitudes of 2^63 and above print in approximate exponent form `d.dddddde+NN` |

All print output goes to stdout.

### if

```hc2
if mask > 100 {
    "big %x\n", mask;
} else if mask == 3 {
    "three\n";
} else {
    "small %d\n", mask;
}
```

No parentheses around the condition. Braces are required. The condition must be a `Bool`.

### for loops

`for` is the only loop, and it has three forms.

```hc2
for I64 i = 0; i < 10; i++ {       // counted
    "%d", i;
}

for n > 1 {                        // condition only
    n = n / 2;
}

for true {                         // forever
    if done() { break; }
}
```

```hc2
for I32 i = 0; i < 10; i++ {
    if i == 3 { continue; }
    if i == 6 { break; }
    "%d", i;
}
// prints 01245
```

### switch

`switch` always compiles to a jump table.

```hc2
U8* classify(I64 c) {
    switch c {
        case '0' ... '9':
            return "digit";
        case 'a' ... 'z', 'A' ... 'Z':     // ranges and comma lists combine
            return "letter";
        case ' ', '\t', '\n':
            return "space";
        default:
            return "other";
    }
    return "unreachable";
}
```

- The subject must be an integer, and each case value is a constant of that type.
- A range is written with three dots, low to high. Duplicate or overlapping cases are a compile error.
- There is at most one `default`, and it must be the last clause.

There is no implicit fallthrough.

```hc2
switch x {
    case 1:
        n = n + 1;
        fallthrough;
    case 2:
        n = n + 10;
    case 3:
        n = n + 100;         // reached only when x == 3
}
```

```hc2
for I64 i = 0; i < 10; i++ {
    switch i {
        case 3:
            continue;            // continues the loop
        case 7:
            break;               // breaks the loop
        case 0 ... 2, 4 ... 6:
            sum = sum + i;
    }
    sum = sum + 100;
}
```

### defer

`defer` postpones a call to the end of the block and runs the postponed calls in reverse order.

```hc2
U0 note(I32 n) { "note %d\n", n; }

I32 main() {
    defer note(1);
    defer note(2);
    "body\n";
    return 0;
}
```

```
body
note 2
note 1
```

```hc2
U8* buf = heap.alloc(4096);
defer heap.free(buf);
```

### unsafe blocks

Two operations are allowed only inside `unsafe`.
- Reading or writing memory directly from an `asm` block.
- Taking raw words out as a capability through an `unsafe union`.

```hc2
unsafe {
    asm {
        MOV RAX, h
        MOV [RAX], RCX       // write memory directly
    }
    return c.p;              // take raw words out as a capability
}
```

## Memory management

hc2 has no garbage collector and no borrow checker. Memory is allocated and freed explicitly through the `heap` package.
Every use of a pointer after its memory is freed is caught as a runtime error, so a use-after-free or a double free never passes silently.

### The heap package

```hc2
import "heap";
```

| Function | Effect |
|----------|----------|
| `U8* alloc(I64 n)` | allocate `n` bytes, writable, 16-byte aligned |
| `U0 free(U8* p)` | free the allocation; any later access is a runtime error |
| `I64 mark()` | record the current allocation position |
| `U0 release(I64 m)` | free everything allocated since `mark` at once |

Memory from `alloc` is always zero-filled. Running out of memory is a runtime error.

### free and revocation

Before `heap.free` hands memory back for reuse, it revokes the allocation.
Every allocation has a generation in its header, and every pointer carries the generation it expects.
`free` advances the header's generation, so every pointer into that memory, copies included, stops matching and fails at its next use.

```hc2
U8* a = heap.alloc(16);
U8* b = a;               // pointers may be copied freely
heap.free(a);
U8 x = b[0];             // runtime error: use after free
```

`free` accepts only the exact pointer that `heap.alloc` returned.
The following are runtime errors.

| Mistake | Error |
|---------|------|
| freeing a literal, `&local`, or a global table | `heap: trap: free of immortal` |
| freeing a slice (`p[8:16]`) or an interior pointer (`p + 1`) | `heap: trap: free: not the allocation base` |
| freeing twice | `heap: trap: double free` |

### Arenas with mark and release

To throw away a batch of temporary allocations at once, use `mark` and `release`.
`mark` records a position; `release` rewinds to it, freeing everything allocated in between.

```hc2
I64 m = heap.mark();
for I64 i = 0; i < 4000; i++ {
    U8* p = heap.alloc(1 << 16);
    // ... use p ...
    heap.release(m);         // free everything allocated since the mark
}
```

A slice cut from an arena can become a struct pointer only if that struct holds no capabilities.
A struct with a `U8*` field, or a field that points to another struct, must be allocated one at a time
with `heap.alloc`, or allocated as an array of that same type.

### Minting capabilities with sys.from_raw

`sys.from_raw(I64 addr, I64 len)` makes a checked pointer from a raw address.
It writes a header just before `addr` and returns a writable capability for `[addr, addr + len)`.

```hc2
import "sys";

I64 base = sys.mmap(65536);              // raw memory: just an I64
U8* p = sys.from_raw(base + 32, n);      // now a checked pointer
```

`from_raw` is not a compiler builtin. It is an ordinary function written in hc2 in the `sys` package,
built from an `asm` store and an `unsafe union` inside an `unsafe` block (see [unsafe blocks](#unsafe-blocks)).

With `sys.mmap` and `from_raw` you can write your own allocator.
Pointers from it are bounds-checked like the ones from `heap.alloc`, carry `.len`, and can be revoked with `heap.free`.

## Runtime errors (traps)

An operation that fails a capability check at runtime is detected as an error.
The program prints a message to stderr and exits immediately with code 134.
There is no handler and no unwinding, nothing like an exception to recover from.
Stopping on the spot is the design; continuing in a corrupted state is not.

| Error | When it happens |
|------|-------------|
| `out of bounds` | an index, slice, or access outside the pointer's window |
| `use after free` | access to freed memory |
| `write to read-only` | a write through a read-only pointer (a string literal, for example) |
| `division by zero` | `/` or `%` by zero |
| `out of memory` | the heap is exhausted |
| `free: not the allocation base` | `free` of anything but the pointer `alloc` returned, or an invalid `release` |
| `double free` | `free` of memory that is already freed |
| `free of immortal` | `free` of a pointer to a literal, the stack, or a global |
| `call through null` | calling a null function pointer |
| `not a function of this type` | the function pointer's type does not match the call |
| `print of null` | printing a null pointer with `%s` |
| `store into a capability` | a byte-by-byte write into a typed block's capability region, including writes made by a system call |
| `cast to a type with capabilities needs a writable heap block` | casting a literal, the stack, or a read-only block to a struct that holds capabilities |
| `block already holds another type` | a block already cast to a different struct that holds capabilities |
| `cast not at an element boundary` | casting a slice at a position that is not a multiple of `sizeof` to a struct that holds capabilities |
| `a stack struct with capabilities cannot be viewed as bytes` | casting a stack struct that holds capabilities to `U8*` or similar |

## Runtime

### Command-line arguments

```hc2
import "rt";

I32 main() {
    "program: %s, %d args\n", rt.arg(0), rt.argc();
    for I64 i = 1; i < rt.argc(); i++ {
        "  %s\n", rt.arg(i);
    }
    return 0;
}
```

`rt.argc()` is the count including the program name, and `rt.arg(i)` returns argument `i` as a `U8*`
(the length does not include the terminating NUL). An index out of range traps with `rt: trap: out of bounds`.

## Inline assembly

An `asm` block holds machine instructions, one per line. hc2 locals can be used as operands by name.

```hc2
I32 main() {
    I32 a = 10;
    asm {
        MOV EAX, a       // read an hc2 variable
        ADD EAX, 5
        MOV a, EAX       // write it back
    }
    "a: %d\n", a;        // a: 15
    return 0;
}
```

Instructions that read or write memory directly can only appear inside an [unsafe block](#unsafe-blocks).
The stack frame belongs to the compiler and cannot be touched from `asm`.

The instructions and registers available are a small menu per target, and anything not on the menu is a compile error.
x86-64 has basic arithmetic, branches, and the system call instruction; arm64 has the minimum needed to write `sys`.

## Packages and targets

A target is an os/arch pair:
- `linux/amd64`
- `linux/arm64`
- `macos/arm64`

The file name decides which targets a file is compiled for. The trailing `_` segments are read from the right:

| File name | Compiled for |
|-----------|--------------|
| `rt.hc2` | every target |
| `rt_linux.hc2` | both linux pairs |
| `rt_arm64.hc2` | both arm64 pairs |
| `rt_linux_arm64.hc2` | that pair only |

The rule applies to every package. There is no conditional compilation inside a file.

Cross-compiling is one flag:

```sh
hc2 build -o server -target linux/arm64 .
```

## Appendix

### Limits

These limits exist to keep the compiler simple.

| Limit | Value |
|-------|-------|
| locals per function | 1024 |
| array dimensions | 8 |
| packages per program | 64 |
| imports per package | 24 |
| files per package | 256 |
| switch table width | 4096 |
