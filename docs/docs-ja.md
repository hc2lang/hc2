# hc2 プログラミング言語

hc2 はメモリ安全なプログラミング言語です。すべてのポインタは実行時に
検査される capability です。ガベージコレクタも借用チェッカもありません。
違反はプログラムを壊す代わりに、その場で停止させます。

コンパイラは hc2 自身で書かれていて、自分自身をコンパイルします。依存は
ゼロです。アセンブラもリンカも内蔵しています — `as` も `ld` も libc も
不要です。`linux/amd64` と `linux/arm64` には静的リンクの ELF を、
`macos/arm64` には署名済みの Mach-O を生成します。

```hc2
import "heap";

I32 main() {
    U8* req = heap.alloc(64);
    req[0] = 'G'; req[1] = 'E'; req[2] = 'T';
    "%d-byte request, method %c%c%c\n", req.len, req[0], req[1], req[2];

    U8* view = req;      // ポインタのコピーを持つ — 誰も止めない
    heap.free(req);      // ヘッダへの 1 回の書き込みが全コピーを失効させる
    "%c\n", view[0];     // C なら解放済みメモリを読んで「動いてしまう」。ここでは止まる
    return 0;
}
```

```
64-byte request, method GET
main.hc2:10: trap: use after free
```

## 目次

- [ハローワールド](#ハローワールド)
- [コンパイルと実行](#コンパイルと実行)
- [コメント](#コメント)
- [関数](#関数)
- [シンボルの可視性](#シンボルの可視性)
- [変数](#変数)
- [型](#型)
    - [プリミティブ型](#プリミティブ型)
    - [数値](#数値)
    - [浮動小数点](#浮動小数点)
    - [真偽値](#真偽値)
    - [文字列](#文字列)
    - [キャストと型なし定数](#キャストと型なし定数)
- [ポインタはcapabilityである](#ポインタはcapabilityである)
    - [スライス](#スライス)
    - [ポインタ演算](#ポインタ演算)
    - [null](#null)
- [配列](#配列)
    - [多次元配列](#多次元配列)
- [構造体](#構造体)
    - [構造体リテラル](#構造体リテラル)
    - [フィールドアクセス](#フィールドアクセス)
    - [構造体とポインタ](#構造体とポインタ)
    - [プライベートフィールド](#プライベートフィールド)
- [共用体](#共用体)
- [可変長引数関数](#可変長引数関数)
- [関数ポインタ](#関数ポインタ)
- [パッケージのimport](#パッケージのimport)
- [文と式](#文と式)
    - [print文](#print文)
    - [if](#if)
    - [forループ](#forループ)
    - [switch](#switch)
    - [defer](#defer)
    - [unsafeブロック](#unsafeブロック)
    - [演算子と優先順位](#演算子と優先順位)
- [定数とグローバル](#定数とグローバル)
    - [定数](#定数)
    - [定数テーブル](#定数テーブル)
    - [可変グローバル](#可変グローバル)
    - [可変テーブル](#可変テーブル)
- [メモリ管理](#メモリ管理)
    - [heapパッケージ](#heapパッケージ)
    - [freeと失効](#freeと失効)
    - [markとreleaseによるアリーナ](#markとreleaseによるアリーナ)
    - [sys.from_rawによるcapabilityの鋳造](#sysfrom_rawによるcapabilityの鋳造)
- [トラップ](#トラップ)
- [ランタイム](#ランタイム)
    - [プログラムの開始と終了](#プログラムの開始と終了)
    - [コマンドライン引数](#コマンドライン引数)
- [インラインアセンブリ](#インラインアセンブリ)
- [パッケージとターゲット](#パッケージとターゲット)
- [コンパイラ](#コンパイラ)
    - [hc2 build](#hc2-build)
    - [hc2 clean](#hc2-clean)
    - [ビルドキャッシュ](#ビルドキャッシュ)
    - [配管コマンド](#配管コマンド)
    - [ブートストラップ](#ブートストラップ)
    - [セルフホストとテスト](#セルフホストとテスト)
    - [インストール](#インストール)
- [エディタ対応](#エディタ対応)
- [付録](#付録)
    - [キーワード](#キーワード)
    - [演算子優先順位表](#演算子優先順位表)
    - [トラップ一覧](#トラップ一覧)
    - [上限値](#上限値)
    - [hc2にないもの](#hc2にないもの)

## ハローワールド

```hc2
I32 main() {
    "Hello, world!\n";
    return 0;
}
```

この時点ですでに 2 つ、見慣れないものがあります。print 関数は存在しません。
文の位置に置かれた文字列リテラルが **print 文そのもの**で、カンマの後に
`printf` 風の引数を取ります([print文](#print文)参照)。そして `main` は
`I32` を返します — その値がプロセスの終了コードになります。

これを単独のディレクトリに `main.hc2` として保存し、ビルドします:

```sh
mkdir hello && cd hello
# ... main.hc2 を書く ...
hc2 build -o hello .
./hello
```

## コンパイルと実行

プログラムはファイルではなく**ディレクトリ**です。コンパイラはディレクトリを
受け取り、その中のすべての `.hc2` ファイルを 1 つのパッケージとして
コンパイルし、import を辿り、1 つの実行ファイルをリンクします:

```
hc2 build [-o out] [-target p] [dir]
                            パッケージツリーをコンパイルし、変更分だけ再ビルドする
hc2 clean [dir]             そのプロジェクトのビルドキャッシュを消す
```

- `dir` のデフォルトは `.` です。
- `-o` を省くと出力名はディレクトリ名になります(`hc2 build hello` は
  `./hello` を書き出し、`.` をビルドすると `./a.out` になります)。
- 出力は静的リンクされた実行ファイル 1 つで、`chmod 0755` 済み、
  そのまま実行できます。
- ビルドが成功すると何をしたかを表示します: `built 12 packages, reused 3`。
  オブジェクトはプロジェクトルートの `.hc2cache` にパッケージ単位で
  キャッシュされます。[ビルドキャッシュ](#ビルドキャッシュ)を参照。
- `-target` でクロスコンパイルします。
  [パッケージとターゲット](#パッケージとターゲット)を参照。

run コマンドもインタプリタもありません — ビルドして、バイナリを実行します。

そもそものコンパイラの入手は[ブートストラップ](#ブートストラップ)と
[インストール](#インストール)を参照してください。

## コメント

```hc2
// 行末までがコメント
I64 x = 1;   // コードの後ろにも書ける
```

コメントは `//` の 1 種類だけです。`/* */` のブロックコメントはありません。

## 関数

```hc2
// main が先、fib が後 — 定義の順序は関係ない
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

関数は `戻り値型 名前(型 引数, ...) { 本体 }` です。前方宣言も
プロトタイプもありません。パッケージ内のトップレベル名は、順序に関係なく、
そのパッケージの全ファイルからどこでも見えます。

- `U0` は「値なし」型です — `U0` 関数は何も返しません。
- 戻り値はちょうど 1 つ。タプルも多値返却もありません。
- 引数の個数とすべての型は厳密に検査されます: `too few arguments`、
  `argument type mismatch`。オーバーロードもデフォルト引数もありません。
- 構造体は値渡しできません: `struct parameters are not in the subset`。
  ポインタ(`Foo*`)を渡します。
- 構造体を値で**返す**ことはできますが、その呼び出しは宣言を直接初期化する
  形でなければなりません: `Pt p = make(3, 4);` — それ以外は
  `a struct-returning call must directly initialize a declaration` です。
- 関数の末尾に到達するのは合法です。`U0` でない関数でも合法で、結果は 0 に
  なります。

## シンボルの可視性

`pub` キーワードはありません。アンダースコアで始まるトップレベル名は
**パッケージ内プライベート**、それ以外の名前はすべてエクスポートされます:

```hc2
I64 counter = 0;      // エクスポート: 他のパッケージが pkg.counter を読み書きできる
I64 _step = 1;        // プライベート: このパッケージだけが見える

U0 tick() {           // エクスポート
    counter = counter + _step;
}

U0 _reset() {         // プライベート
    counter = 0;
}
```

このルールは一様です。関数、定数、可変グローバル、テーブル、型 — そして
**構造体のフィールド**にも適用されます:

```hc2
struct Pt {
    I64 x;
    I64 y;
    I64 _tag;     // このパッケージのファイルからだけ見える
}
```

パッケージ修飾子越しにプライベート名へ触れるとコンパイルエラーです:
`that name is private to its package`、`that field is private to its
package`、`that type is private to its package`。

プライバシーはビルドシステムにも効いています。プライベート名はパッケージの
インターフェイスハッシュから除外されるので、それらを編集しても import 側の
パッケージは再ビルドされません([ビルドキャッシュ](#ビルドキャッシュ)参照)。

## 変数

```hc2
I64 total = 0;
U8 c = 'x';
Bool ok = total == 0;
I64 arr[2] = {10, 20};
```

宣言は `型 名前 = 初期化子;` — **初期化子は必須**です(`initializer
required`)。この言語のどこにも未初期化の変数は存在しません。ローカルも
グローバルも定数もテーブルも、必ず初期化子を取ります。

- ローカルは常に可変です。`let`/`var` の区別も `const` ローカルも
  ありません。
- 代入は式ではなく**文**です。`a = b = c` や `if x = f()` は書けません。
  存在するのは素の `=` だけです — `+=` や `-=` などの複合代入はありません。
- `i++` と `i--` も文であり、素のローカル整数変数にしか使えません
  (`++ and -- need a local variable`)。`p.x++` や `a[i]++` はパースされない
  ので、`p.x = p.x + 1;` と書きます。
- 文として使える式は呼び出しだけです(`expression statements must be
  calls`)。
- 外側のスコープの名前をシャドウするのは可。**同じ**スコープでの再宣言は
  `name already declared in this scope` です。

## 型

### プリミティブ型

| 型  | サイズ(バイト) | 説明 |
|-------|------|-------------|
| `U0`  | 0 | 値なし。何も返さない関数の戻り値型 |
| `Bool`| 1 | `true` または `false` |
| `I8` `I16` `I32` `I64` | 1 2 4 8 | 符号付き整数 |
| `U8` `U16` `U32` `U64` | 1 2 4 8 | 符号なし整数 |
| `F64` | 8 | IEEE 754 倍精度 — [浮動小数点](#浮動小数点)参照 |
| `T*`  | 32 | 型 `T` の値への capability — [ポインタはcapabilityである](#ポインタはcapabilityである)参照 |

これで全部です。`enum` はなく(`const I64 NAME = n;` を使います)、
型エイリアスもなく、独立した文字列型もありません(文字列は `U8*`
です)。浮動小数点は F64 の 1 種類だけです。

### 数値

```hc2
I64 a = 42;             // 10進
I64 b = 0xbeef;         // 16進 — x は小文字。0X は認識されない
U8 g = 'G';             // 文字リテラルは整数定数
I64 neg = -5;
```

2進(`0b`)や 8進リテラルはありません(先頭の `0` はただの 10進です)。
桁区切りもリテラル接尾辞もありません。

算術は型の幅でラップします:

```hc2
U8 x = 200;
x = x + 100;         // 300 は U8 では 44 にラップする
"x = %d\n", x;       // x = 44
```

整数除算はゼロ方向に切り捨てます。`%` は剰余です:

```hc2
"div: %d rem: %d\n", 17 / 5, 17 % 5;    // div: 3 rem: 2
```

リテラルのゼロで割るとコンパイルエラー、値がゼロの変数で割ると実行時に
トラップします(`division by zero`)。

シフトは左オペランドの符号に従います — 符号付きなら算術シフト、符号なしなら
論理シフトです:

```hc2
I64 m = -8;
"sar %d\n", m >> 1;      // sar -4
U64 u = 16;
"shr %d\n", u >> 2;      // shr 4
```

### 浮動小数点

`F64` は IEEE 754 の倍精度です。他の幅はありません — HolyC と同じく、
浮動小数点は 8 バイト 1 種類です:

```hc2
F64 x = 1.5;
F64 k = 1.0e-3;              // 指数も書ける。1e9 も浮動小数
"%f\n", x * 2.0 + 0.25;      // 3.250000
"%f\n", 1.0 / 0.0;           // inf — 0.0 除算はトラップしない
```

- リテラルは `数字.数字` です。小数点の両側に数字が要ります(`1.` や
  `.5` はパースされません)。指数部は `e` に符号と数字を続けます。
- 浮動小数リテラルは最初から `F64` 型です。型なし定数ではないので
  `F64 x = 1;` は通りません — `1.0` と書きます。
- 使える演算は `+ - * /` と比較だけです(`F64 supports + - * / and
  comparisons`)。`%` もシフトもビット演算もありません。
- 0.0 除算は[トラップ](#トラップ)しません。IEEE のとおり `inf` / `nan`
  になり、NaN はどの比較でも false(`!=` だけ true)です。
- 定数式は畳まれません。`const F64` に置けるのはリテラルだけです —
  コンパイラ自身は浮動小数演算を 1 つも実行しない、という決定です。
- `as` で整数と往復できます。切り捨てはゼロ方向(`2.9 as I64` は 2、
  `-2.9 as I64` は -2)。`U64` とは往復できず(`U64 does not cast to
  F64`)、`Bool` とも不可です。

### 真偽値

`Bool` は整数ではなく独立した型です。リテラルは `true` と `false` だけです。
比較演算が `Bool` を生成し、条件式は厳密に `Bool` を要求します:

```hc2
Bool ok = 3 > 2;
if ok {
    "ok\n";
}
```

- `if 1 { ... }` はコンパイルエラーです: `condition must be Bool`。
  truthiness はありません。
- `&&` と `||` は `Bool` オペランドを要求し、短絡評価します:
  `a() && b()` で `a()` が false なら `b()` は実行されません。
- `==` と `!=` は整数と `Bool` に使えます。
- `!` 演算子はありません。否定は比較で書きます:
  `if ok == false { ... }`。
- `Bool` はキャストできません: `Bool does not cast`。

### 文字列

文字列は `U8*` です — バイト列を覆い、長さを運ぶ
[capability](#ポインタはcapabilityである) です。文字列リテラルは
読み取り専用です:

```hc2
U8* s = "hello";
"%s has %d bytes\n", s, s.len;      // hello has 5 bytes
"first: %c\n", s[0];                // first: h
U8* head = s[0 : 2];                // スライスはより狭い U8*
"%s\n", head;                       // he
```

- `.len` はバイト単位の長さです。(属性が付くのは変数であってリテラルでは
  ありません — `"hi".len` はパースされないので、まず `U8*` に束縛します。)
- エスケープは文字列・文字リテラル共通で `\n` `\t` `\r` `\0` `\\` `\"`
  `\'`。それ以外はありません(`unknown escape`)— `\xNN` もありません。
- リテラルは改行をまたげません。
- 文字列は言語レベルでは **NUL 終端されません**。長さは capability が
  知っています。(ただしコンパイラは各リテラルのデータの直後に NUL を
  1 バイト置くので、リテラルはそのままカーネルのパス引数に渡せます。ヒープで
  組み立てた文字列には `str.cstr` を使います。)
- リテラル越しの書き込みはトラップします: `trap: write to read-only`。
  解放もトラップします: `heap: trap: free of immortal`。
- 連結演算子も伸びる文字列型もありません。`heap.alloc` した `U8*`
  バッファにバイトを組み立てます。

### キャストと型なし定数

**暗黙の型変換はありません**。型の違う 2 つのオペランドは出会えません:

```hc2
U8 a = 1;
I32 b = 2;
I32 c = a + b;    // エラー: mixed-type arithmetic (no implicit conversions; write the `as`)
```

キャスト演算子は後置の `as` で、連鎖できます:

```hc2
"300 as U8 = %d\n", 300 as U8;        // 44
I64 v = -5;
"v as U32 = %d\n", v as U32;          // 4294967291
"wrap %d\n", big as U8 as I64;        // 切り詰めてから再び拡げる
I32* xs = heap.alloc(64) as I32*;     // ポインタから別の型のポインタへ
```

ルール:

- スカラー → スカラー: 可。ただし `Bool does not cast`、
  `U0 does not cast`、そして `U64` と `F64` は互いに不可です
  ([浮動小数点](#浮動小数点)参照)。
- ポインタ → ポインタ: 常に可(`heap.alloc` の返す `U8*` を `Foo*` に
  する方法がこれです)。
- **ポインタ ↔ 整数: 決して不可。** `as casts scalars to scalars or
  pointers to pointers (never pointer<->integer)`。アドレスからポインタへの
  唯一の道は `sys.from_raw` です
  ([sys.from_rawによるcapabilityの鋳造](#sysfrom_rawによるcapabilityの鋳造)参照)。

リテラル(数値、文字リテラル、`sizeof(...)`、それらから畳み込まれた
定数式)は**型なし定数**です。出会った型に適応し(`U8 x = 5;` はそのまま
通る)、あふれる場合は拒否され(`U8 x = 300;` は `constant does not
fit`)、キャスト先は整数型に限られます(`untyped constant casts only to
integer` — つまり `0 as U8*` は拒否されます)。

## ポインタはcapabilityである

hc2 のポインタはアドレスではありません。32 バイトの **capability** です。
アドレスに加えて、あらゆる使用を検査するための境界・権限・世代を運びます。
`sizeof(U8*)` は 32 です。

| ワード | 属性 | 意味 |
|------|-----------|---------|
| 0 | `.addr` | 生のアドレス |
| 1 | `.hdr` | 割り当てのヘッダのアドレス。最下位ビットは書き込み権限 |
| 2 | `.lo`, `.len` | 割り当て内の窓のオフセットと、その**バイト**長 |
| 3 | `.gen` | この capability が期待する世代 |

すべての割り当てはデータの直下に 16 バイトのヘッダを持ちます:
`{長さ, 世代}`。ポインタ越しのあらゆるアクセス — `p[i]`、`p.field`、
スライス、`%s` の print — は、実行時に capability とヘッダの両方と
照合されます: 境界内か、世代は一致するか、(ストアなら)書き込みビットは
立っているか。検査に失敗すれば未定義動作ではなく[トラップ](#トラップ)です。

5 つの属性はどのポインタからも読め、ただの `I64` の数値を返します:

```hc2
U8* p = heap.alloc(64);
"%d %d %d\n", p.len, p.lo, p.gen;     // 64 0 1
```

数値は出て行きますが、権限は戻ってきません — これらの数値を再び capability
に変える操作は存在しません(唯一の例外が `sys.from_raw` で、意図的に
「grep できる普通のライブラリ関数」になっています)。

capability の出どころ:

- 文字列リテラル — 読み取り専用、不滅(世代 0)
- ローカルの構造体・共用体・配列への `&` — 書き込み可、世代 0
- 可変グローバルテーブルへの `&` — 書き込み可、世代 0
- `heap.alloc` — 書き込み可、世代 1、失効可能
- `sys.from_raw` — 生のアドレスから手で鋳造

制約:

- 1 段だけです: `U8**` は `pointer to pointer is not in the subset`。
- 参照剥がし演算子はありません。`*p` は存在せず、`p[0]` か `p.field` で
  読みます。
- `&` が使えるのはローカル、配列、関数、可変グローバル配列です。ポインタ
  変数(`& of a pointer variable is not in the subset`)、定数テーブル、
  構造体テーブルには使えません。

### スライス

`p[lo : hi]` は、その窓だけを覆う同じ型の新しいポインタを作ります:

```hc2
U8* buf = heap.alloc(64);
I64 n = sys.read(fd, buf);
"read %d: %s", n, buf[0 : n];      // 読んだ分だけを表示する
```

スライスは狭めることしかできません — 新しい窓は古い窓と照合されるので、
届く範囲を捏造することはできません。スライスは割り当ての同一性を保ちます。
割り当てを解放すればスライスもトラップします。

### ポインタ演算

```hc2
Pt* ps = heap.alloc(4 * sizeof(Pt)) as Pt*;
Pt* q = ps + 2;       // 要素単位: 2 * sizeof(Pt) バイト進む
```

`+` と `-` のみ、ポインタは左側のみ、右側は整数のみです(`pointers
support only + and -`、`the pointer must be on the left of + and -`)。
結果は元の境界を保つので、範囲外の結果は計算した時ではなく使った時に
トラップします。ポインタ同士の減算も大小比較もできません。

### null

`null` は空のポインタ値です。任意のポインタ型・関数ポインタ型に適応し、
比較は `==` と `!=` だけで、キャストはできません:

```hc2
U0(I64)* g = null;
if g == null { "not set\n"; }
```

null 越しの呼び出しはトラップします(`call through null`)。null の `U8*`
を `%s` で印字してもトラップします(`print of null`)。

## 配列

配列は固定長で、C 風に名前の後ろへブラケットを付けて宣言し、常に
初期化します:

```hc2
I32 d[4] = {1, 2, 3, 4};
U8* names[3] = {"alpha", "beta", "gamma"};
I64 zeros[8] = {};                       // {} はゼロ埋め
I64 arr[lib.WIDTH] = {};                 // 長さには import した定数も使える
```

- 各長さは正のコンパイル時定数でなければなりません(`an array length
  must be a positive constant`)。
- 初期化子の個数は正確に一致しなければなりません(`initializer count
  must match the array length`)。空の `{}` は例外です。
- 配列は値ではありません。丸ごとの代入・引数渡し・返却はできません
  (`an array is not a value; index it or take &`)。添字を使うか、`&` を
  取ります:

```hc2
I64 arr[3] = {1, 2, 3};
I64* p = &arr;               // 配列全体。境界も込み
"%d bytes\n", p.len;         // 24 bytes
```

- 添字は実行時に境界検査されます。範囲外の定数添字は、実行時ではなく
  コンパイル時に拒否されます(`constant index out of bounds`)。

### 多次元配列

```hc2
I32 m[2][3] = {{1, 2, 3}, {4, 5, 6}};
m[1][0] = 40;
I64 cube[2][2][2] = {{{1, 2}, {3, 4}}, {{5, 6}, {7, 8}}};
"%d\n", cube[1][0][1];       // 6
```

- 初期化子では各次元が自分の波括弧を持ちます(`this dimension needs
  braces` — C 風のフラットな並びは不可)。
- アクセスでは全次元に添字が必要です(`one subscript per dimension` —
  部分的な `m[1]` は不可)。
- 各次元は独立に検査されます。`I32 m[2][3]` に対する `m[0][7]` は
  トラップであり、隣の行への散歩にはなりません — 行またぎは存在しません。
- 最大 8 次元です。

## 構造体

```hc2
struct Node {
    I64 kind;
    U8* text;
    Node* next;      // ポインタ経由の自己参照は問題ない
}
```

構造体はトップレベルで宣言します。閉じ波括弧の後にセミコロンは
付けません。フィールドはスカラー、ポインタ、関数ポインタです —
構造体の直接入れ子は不可
(`struct-in-struct fields are not in the subset`。ポインタを使います)、
`U0` も不可です。フィールドは宣言順に配置され、それぞれ
`min(サイズ, 8)` にアラインされ、構造体サイズは 8 の倍数に切り上げられます。
`sizeof(Node)` で取得できます。

### 構造体リテラル

初期化は位置指定で、全フィールドを埋めるか、ゼロ埋めします:

```hc2
struct Arena {
    U8* buf;
    I64 used;
}

Arena a = {heap.alloc(4096), 0};    // 全フィールドを順に
Arena b = {};                        // すべてゼロ
Arena c = make_arena(4096);          // あるいは呼び出しから直接
```

`struct literal must initialize every field`、`too many fields in struct
literal` — 指示付き初期化子はありません。

### フィールドアクセス

`.` は値にもポインタにも使えます。`->` はありません:

```hc2
U0 arena_free(Arena* a) {
    heap.free(a.buf);        // a はポインタ。. が自動で剥がす
}
```

チェーンはデータの深さまで届きます: `d.td.time`、`n.text.len`
(フィールド、その先の capability 属性)。

`len`(や `addr`、`gen` など)という名前の実フィールドは、同名の
capability 属性をシャドウします。

### 構造体とポインタ

```hc2
Pt* ps = heap.alloc(4 * sizeof(Pt)) as Pt*;
for I64 i = 0; i < 4; i++ {
    Pt* p = ps + i;          // 要素単位のポインタ演算
    p.x = i * 10;
    p.y = i;
}
```

構造体はポインタ(`&値`)で渡します。値で返すのは、呼び出しで新しい宣言を
直接初期化するときだけです。構造体のコピーは**フィールドごとに**書きます —
既存の変数同士の丸ごと代入はサブセットに含まれません。

### プライベートフィールド

`_` で始まる名前のフィールドは定義パッケージ内プライベートです —
[シンボルの可視性](#シンボルの可視性)を参照。

## 共用体

共用体はメンバをオフセット 0 に重ねます。サイズは最大メンバを 8 の倍数に
切り上げたものです:

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
    Date d = {};                     // 共用体にリテラル形式はない。{} のみ
    d.i64 = 0x11223344AABBCCDD;
    "time %x date %x\n", d.td.time as I64, d.td.date as I64;
    // time aabbccdd date 11223344   (リトルエンディアン)
    return 0;
}
```

素の共用体は、**数値**を読み替えるためのものです。メンバに置けるのは
スカラーか、全フィールドがスカラーの構造体です。capability や関数ポインタの
メンバは拒否されます(`a union member cannot hold a capability`、`a union
member cannot hold a function`)— さもなければ共用体は capability の
自由な鋳造所になってしまうからです。

`unsafe union` はまさにその制限だけを外します。代わりに、capability メンバの
読み取りはすべて `unsafe { }` ブロックの中に置く必要があります
(`a union's capability member needs an unsafe block`)。これが生のワードから
capability を鋳造できる唯一の扉です —
[sys.from_rawによるcapabilityの鋳造](#sysfrom_rawによるcapabilityの鋳造)を参照。

## 可変長引数関数

関数の最後の引数は、可変個のスカラー引数を集められます:

```hc2
I64 sum(I64... xs) {
    I64 total = 0;
    for I64 i = 0; i < xs.len / 8; i++ {    // .len はバイト。/8 で個数になる
        total = total + xs[i];
    }
    return total;
}

I32 main() {
    "sum %d\n", sum(1, 2, 3, 4, 5);   // sum 15
    "sum %d\n", sum();                // sum 0 — 引数ゼロも可
    return 0;
}
```

関数の中では、末尾引数は普通のポインタです(ここでは `I64*`)。添字で
読め、スライスでき、`.len` も読めます。実際に渡された引数を越えて読むと、
他のポインタと同じく `out of bounds` でトラップします — 可変長引数の
読み過ぎはスタックを歩く手段にはなりません。

- 可変長にできるのは最後の引数だけで(`only the last parameter may be
  variadic`)、要素型はスカラーでなければなりません(`a variadic tail must
  be a scalar type`)。
- 各引数は要素型と照合されます(`variadic argument type mismatch`)。
- 可変長引数関数は関数ポインタにできません。

## 関数ポインタ

関数の型はシグネチャに `*` を付けたものです:

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
    I32(I32, I32)* f = &add;      // & が値を鋳造する
    "direct %d\n", f(2, 3);       // 関数のように呼ぶ — 剥がす操作は不要
    f = &mul;
    for I64 i = 0; i < 2; i++ {
        "%s %d\n", OPS[i].name, OPS[i].f(4, 5);
    }
    return 0;
}
```

- 星は必須です: `a function type is always a pointer: add the '*'`。
- 代入時にシグネチャは厳密一致でなければなりません(`initializer type
  mismatch`)。
- 関数値の属性は `.addr` のただ 1 つです(`a function value has only
  .addr`)。
- `null` は正当な値で、呼ぶと `call through null` でトラップします。
  すべての間接呼び出しは、呼び先が本当に期待した型の関数であることも
  実行時に検証します — 偽造・破損したターゲットは
  `not a function of this type` でトラップします。
- テーブルのスロットに置けるのは `&fn` か `null` だけです。

## パッケージのimport

パッケージは `.hc2` ファイルの入ったディレクトリです。ディレクトリ内の
全ファイルは 1 つのスコープを共有します。サブディレクトリは別の
パッケージです。

```hc2
import "geom";

I32 main() {
    geom.Pt a = geom.make(3, 4);
    "dot = %d\n", geom.dot(&a, &a);
    return 0;
}
```

`import` は引用符付きの**ディレクトリパス**を取り、2 つのルートに対して
順に解決されます:

1. **プロジェクトルート** — ビルド対象ディレクトリと同じかその上位で、
   `hc2.root` マーカーファイル(空ファイル。中身は読まれません)を持つ
   最も近いディレクトリ。マーカーがなければビルド対象ディレクトリ自身が
   ルートになるので、`/tmp` の使い捨てプログラムに準備は要りません。
2. **言語ルート** — コンパイラ実行ファイルの隣から同じ方法で見つかる
   ディレクトリ。`str`、`fmt`、`hash`、`sys`、`rt`、`heap` は
   ここにあります。同名の
   プロジェクトディレクトリは言語側をシャドウします。

解決にカレントディレクトリは関与しないので、同じ import 文字列はどこから
でも同じパッケージを意味します。

ルール:

- 修飾子は最後のパスセグメントです: `import "hc2/ast"` なら `ast.…` に
  なります。最後のセグメントが同じ 2 つの import は `import name
  collision (rename a directory)` です。
- import はパッケージ単位です。import せずに `geom.` を使うのは `package
  not imported` — `sys` のような組み込みパッケージでも同じです。
- import の循環は拒否されます: `import cycle through …`。自分自身の
  import もできません。
- エクスポートされたグローバルはパッケージ越しに読み**書き**できます
  (`counter.n = 0;`)。`_` を付ければ何でもプライベートになります
  ([シンボルの可視性](#シンボルの可視性))。
- `rt` は常にリンクされます(print 文とトラップが住んでいます)が、
  `rt.argc()` を呼ぶにはやはり `import "rt";` が必要です。

## 文と式

文として使える式は呼び出しだけです(`expression statements must be
calls`)。代入も `i++` も文です — 式の中には置けません([変数](#変数)参照)。

### print文

文字列リテラルで始まる文は print です:

```hc2
"plain text\n";
"%s has %d bytes\n", name, name.len;
"hex: %x  char: %c  100%%\n", 48879, 104;
```

フォーマットはリテラルでなければなりません(`U8*` 変数は不可)。動詞は
ちょうど 5 つ(`print formats: %d %x %c %s %f`)。これに、リテラルの `%`
を出す `%%` が加わります:

| 動詞 | 引数 | 出力 |
|------|----------|--------|
| `%d` | 任意の整数 | `I64` に拡げた後の符号付き 10進(符号なしはゼロ拡張: `-5 as U32` は `4294967291` と印字) |
| `%x` | 任意の整数 | 小文字 16進。`0x` なし、パディングなし |
| `%c` | 任意の整数 | 下位バイトを 1 文字として |
| `%s` | `U8*` | `.len` バイト全部 |
| `%f` | `F64` | 符号 + 整数部 + 小数 6 桁。特別値は `inf` `-inf` `nan`(NaN の符号は印字しない)。絶対値が 2^63 以上は `d.dddddde+NN` の近似指数表記 |
| `%%` | — | リテラルの `%` |

引数の個数は両方向に検査され(`missing argument for format specifier`、
`more arguments than format specifiers`)、末尾の `%` は `format string
ends in '%'`、`%s` は厳密に `U8*` を取ります(`%s takes a U8*`)。null の
`U8*` を印字すると `print of null` でトラップします。

print の出力はすべて stdout に行きます。幅・精度指定はなく、実行時の
フォーマットパーサもありません — コンパイラがリテラルを動詞ごとに分割し、
直接の write を生成します。これが言語唯一の組み込み出力で、それ以上の
ことは `sys.write` で書きます。

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

条件に丸括弧は付けません。波括弧は必須です。条件は厳密に `Bool` です。

### forループ

ループは `for` だけです。3 つの形があります:

```hc2
for I64 i = 0; i < 10; i++ {       // カウント形
    "%d", i;
}

for n > 1 {                        // 条件のみ — これが while ループ
    n = n / 2;
}

for true {                         // 無限ループ
    if done() { break; }
}
```

- カウント形の最初の節は整数カウンタ(組み込みスカラー型)を 1 つ宣言
  しなければなりません。ステップは任意の単純文です — `i++`、`i = i + 4`、
  呼び出しでも構いません。
- `break` と `continue` は期待どおりに働きます。ループの外では
  `break/continue outside a loop` です。
- `while`、`do`、`goto` はありません。

```hc2
for I32 i = 0; i < 10; i++ {
    if i == 3 { continue; }
    if i == 6 { break; }
    "%d", i;
}
// 01245 と印字される
```

### switch

`switch` は常にジャンプテーブルにコンパイルされます:

```hc2
U8* classify(I64 c) {
    switch c {
        case '0' ... '9':
            return "digit";
        case 'a' ... 'z', 'A' ... 'Z':     // 範囲とカンマ列は組み合わせられる
            return "letter";
        case ' ', '\t', '\n':
            return "space";
        default:
            return "other";
    }
    return "unreachable";
}
```

- 対象は整数でなければならず、各 case 値はその型の定数です(名前付き
  定数も可: `case ND_ADD, ND_SUB:`)。
- 範囲は 3 つのドットで、小さい方から大きい方へ書きます(`a case range
  runs low to high`)。重複・重なりはコンパイルエラーです(`duplicate
  case value`)。
- `default` は最大 1 つで、最後の節でなければなりません(`default must
  be the last clause`)。
- テーブルは本物なので、case はそれなりに密でなければなりません。幅が
  4096 を超えると `this switch is too sparse for a table; write if` です。

**暗黙のフォールスルーはありません。**最後の文が `fallthrough;` で
なければ、各 case はそこで終わります:

```hc2
switch x {
    case 1:
        n = n + 1;
        fallthrough;         // その case の最後の文でなければならない
    case 2:
        n = n + 10;
    case 3:
        n = n + 100;         // x == 3 のときだけ到達する
}
```

- `fallthrough must be the last statement in its case`。
  `the last case cannot fall through`。
- `default` なしで外れた場合は、単に switch から抜けます。
- 各 case 本体は独立したスコープです — 同じローカル名を各 case で宣言
  できます。
- switch に `break` は不要なので、**switch の中の `break` と `continue`
  は、switch ではなく外側のループのもの**です:

```hc2
for I64 i = 0; i < 10; i++ {
    switch i {
        case 3:
            continue;            // ループの continue
        case 7:
            break;               // ループの break
        case 0 ... 2, 4 ... 6:
            sum = sum + i;
    }
    sum = sum + 100;
}
```

### defer

`defer` は 1 つの単純文(呼び出し、代入、`i++`/`i--`)を、囲んでいる
**ブロック**の終わりまで先送りし、溜まったものを逆順に実行します:

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

- スコープは関数ではなくブロックです。switch の case の中の `defer` は、
  その case 本体が終わるとき — `fallthrough` で先へ進む前 — に実行され
  ます。
- `return` は囲んでいる全ブロックの保留中の defer を実行します。
- **`break` と `continue` は defer を実行しません。**ループ本体の中で保留中の
  `defer` は、`break` でループを抜けるとスキップされます — 後始末は
  ループの後に置くか、ループ本体の外で defer してください。

このイディオムのために `defer` は存在します:

```hc2
U8* buf = heap.alloc(4096);
defer heap.free(buf);
```

### unsafeブロック

hc2 ではほとんどすべてが検査されます。検査されない操作は 2 つだけで、
`unsafe { ... }` の内側に置く必要があります:

1. `unsafe union` の capability メンバの読み取り
   (`a union's capability member needs an unsafe block`)
2. `asm` ブロック内のメモリオペランド(`memory operand: a load or store
   here would be the one the compiler did not check`)

```hc2
unsafe {
    asm {
        MOV RAX, h
        MOV [RAX], RCX       // 生のストア — ここでだけ合法
    }
    return c.p;              // unsafe union の capability メンバ
}
```

`unsafe` ブロックはネストでき、言語の残りを**止めません**。境界検査は
走り続けますし、`unsafe` の中でさえフレームレジスタは触れません
(`RSP and RBP belong to the compiler`)。

門を狭くしている目的は監査可能性です。コードベースを `grep unsafe` すれば、
権限を鋳造しうる行がすべて見つかります。同梱ライブラリ全体では 4 行 —
ターゲットごとの `sys.from_raw` の `unsafe` ブロックが 3 つと、それらが
共有する `unsafe union` 宣言が 1 つです。

### 演算子と優先順位

弱い方から強い方へ — **これは C の表ではありません**:

| レベル | 演算子 | 備考 |
|-------|-----------|-------|
| 1 | `\|\|` | 短絡評価 |
| 2 | `&&` | 短絡評価 |
| 3 | `==` `!=` | |
| 4 | `<` `<=` `>` `>=` | |
| 5 | `+` `-` `\|` `^` | |
| 6 | `*` `/` `%` `<<` `>>` `&` | |
| 7 | `as T` | キャスト |
| 8 | 単項 `-`、単項 `&` | |
| 9 | `f(...)` `a[i]` `p[lo : hi]` `.field` | 後置 |

同一レベルの二項演算子はすべて左結合です。C との違いは意図的です —
シフトとマスクの演算子が算術や比較より**強く**結合するので、古典的な
括弧の罠が消えます:

```hc2
"prec %d\n", 1 + 2 << 3;      // prec 17     — 1 + (2 << 3) であり、C の (1+2) << 3 ではない
Bool b = x & 7 == 1;          // (x & 7) == 1 — C プログラマがいつも意図していた方
```

`as` はすべての二項演算子より強く、単項より弱く結合します:
`-x as U8` は `(-x) as U8`、`a * b as I64` は `a * (b as I64)` です。

単項演算子はちょうど 2 つ、`-`(符号反転)と `&`(アドレス取得/関数参照)
です。C プログラマが探して見つからないもの:

| C | hc2 |
|---|-----|
| `!x` | `x == false` |
| `~x` | `x ^ -1` |
| `*p` | `p[0]` または `p.field` |
| `p->f` | `p.f` |
| `c ? a : b` | `if` 文 |
| `x += 1` | `x = x + 1;` |

`sizeof(T)` は**型**を取り(式は決して取りません)、コンパイル時に
型なし定数へ畳み込まれます。

## 定数とグローバル

### 定数

```hc2
const I64 WIDTH = 28;
const I64 AREA = WIDTH * 3 + 1;          // 定数式は畳み込まれる
const U8* GREETING = "from a constant";
const Bool DEBUG = false;
```

トップレベルの `const 型 NAME = 式;` はコンパイル時定数を定義し、使用の
たびに畳み込まれます。畳み込めなければならず(`a constant needs a
literal or a constant expression`)、自分自身では定義できず(`this
constant is defined in terms of itself`)、代入もできません(`a constant
cannot be assigned to`)。定数は配列長や `case` ラベルに使えます。

`enum` はありません。イディオムは定数の族です:

```hc2
const I64 ND_ADD = 4;
const I64 ND_SUB = 5;
```

### 定数テーブル

```hc2
const I64 PRIMES[5] = {2, 3, 5, 7, 11};

const Insn TABLE[4] = {
    {"mov", 0x89, -1},
    {"add", 0x01, -1},
    {"sub", 0x29, -1},
    {"cmp", 0x39, -1},       // 末尾カンマは可
};
```

定数テーブルは読み取り専用メモリに置かれます。スカラー、文字列、構造体を
置けます(`U8*` や関数ポインタのフィールドも可 — `&fn` か `null`)。
書き込みは `a const table cannot be assigned to`、`&` は `& of a const
table is not in the subset` です。変数での添字アクセスは実行時に境界検査
されます。

### 可変グローバル

```hc2
I64 n = 0;           // エクスポートされるパッケージ状態
I64 _step = 1;       // プライベートなパッケージ状態
```

トップレベルの素の宣言は可変グローバルです。**スカラー**でなければならず
(`a mutable global must be a scalar` — グローバルなポインタは不可)、
初期化子は定数です。エクスポートされたものは `pkg.name` としてパッケージ
越しに読み書きされます。

### 可変テーブル

```hc2
I64 buf[4] = {10, 20, 30, 40};
I64 grid[2][3] = {{1, 2, 3}, {4, 5, 6}};
Pt pts[3] = {{1, 100}, {2, 200}, {3, 300}};
```

グローバル配列は、スカラーの配列か、全フィールドがスカラーの構造体の
配列として許されます(`a mutable table's struct fields must be scalars`
— 書き込み可能な静的メモリに座る capability は、はぐれたストア 1 つで
偽造できてしまうため禁止です)。

- 要素への書き込みは普通にできます: `grid[1][2] = 9;`。
- 構造体要素はフィールドごとに書きます(`a struct element is written
  field by field`)。
- 関数ポインタのテーブルは `const` でなければなりません(`a mutable
  table takes scalar or struct elements`)。
- スカラーテーブルへの `&buf` は使え、テーブル全体を境界込みで覆います。

## メモリ管理

ガベージコレクタも借用チェッカもありません。メモリは明示的です — そして
メモリに関するすべての誤りは、破壊ではなくトラップになります。

### heapパッケージ

```hc2
import "heap";
```

| 関数 | 動作 |
|----------|----------|
| `U8* alloc(I64 n)` | `n` バイトを割り当てる: 16 バイトアライン、世代 1、書き込み可 |
| `U0 free(U8* p)` | 割り当てを失効させる — ポインタの全コピーが道連れになる |
| `I64 mark()` | 現在の割り当て位置を記録する |
| `U0 release(I64 m)` | マークまで巻き戻し、それ以降の割り当てをすべて捨てる |

`heap` は 256 MiB の匿名マッピング 1 つの上のバンプアロケータです。
新しいメモリはゼロ埋めされていて(初回タッチのページ)、`alloc(0)` は
合法、領域が尽きると `heap: trap: out of memory` でトラップします。

### freeと失効

`heap.free` はメモリを再利用しません。**失効**させます。各割り当ての
ヘッダは正式な世代を持ち、各ポインタは自分が期待する世代を運びます。free
はストア 1 回(ヘッダの世代が進むだけ)ですが、その瞬間から、プログラム
のどこにあるどのコピーもヘッダと食い違い、次に使われたときにトラップ
します:

```hc2
U8* a = heap.alloc(16);
U8* b = a;               // 自由に別名を作ってよい。誰も追跡しない
heap.free(a);
U8 x = b[0];             // trap: use after free
```

`free` 自身も渡されたものを順に検査します:

| 誤り | トラップ |
|---------|------|
| リテラル・`&ローカル`・グローバルテーブルの解放 | `heap: trap: free of immortal` |
| スライス(`p[8:16]`)や内部ポインタ(`p + 1`)の解放 | `heap: trap: free: not the allocation base` |
| 二重解放 | `heap: trap: double free` |

### markとreleaseによるアリーナ

フェーズ型の処理には、`mark`/`release` が領域全体を O(1) で解放します:

```hc2
I64 m = heap.mark();
for I64 i = 0; i < 4000; i++ {
    U8* p = heap.alloc(1 << 16);
    // ... p を使う ...
    heap.release(m);         // 巻き戻す。領域は再び配られる
}
```

`release` は世代を進め**ません**。自分の領域の `release` を生き延びた
ポインタは、次にそこへ割り当てられたものの別名になります。マークより上を
すべて自分が所有していること — `heap` があなたを信頼するのは、その一点
だけです。(不正なマークは `heap: trap: free: not the allocation base`
でトラップします。)

スライスベースのアリーナにはライブラリの支援すら不要です — 1 つの
割り当ての窓を配れば、割り当ての解放がすべての窓を失効させます:

```hc2
struct Arena {
    U8* buf;
    I64 used;
}

U8* arena_alloc(Arena* a, I64 n) {
    U8* p = a.buf[a.used : a.used + n];
    a.used = a.used + n;
    return p;
}

U0 arena_free(Arena* a) {
    heap.free(a.buf);        // 配った全スライスが道連れになる
}
```

### sys.from_rawによるcapabilityの鋳造

`sys.from_raw(I64 addr, I64 len)` は `addr - 16` に新品のヘッダを書き、
`[addr, addr+len)` を覆う書き込み可・世代 1 の capability を返します。
アドレスをポインタに変える**唯一の**方法です:

```hc2
import "sys";

I64 base = sys.mmap(65536);              // 生のメモリ: ただの I64
U8* p = sys.from_raw(base + 32, n);      // これで検査付きポインタになった
```

`from_raw` はコンパイラ組み込みではありません。`sys` パッケージにある
20 行の普通の hc2 で、言語が提供する 2 つの `unsafe` の道具 — ヘッダを
書くための `asm` ストアと、4 ワードを組み立てる `unsafe union` — で
書かれています:

```hc2
unsafe union _Cap {
    _CapWords w;     // 4 つの I64: addr, hdr, offlen, gen
    U8* p;
}
```

`mmap` + `from_raw` の上に作った自前アロケータは一級市民です。その
ブロックは境界検査され、印字でき、`.len` を報告し、`heap.free` で失効
させることさえできます。使うのに必要なのは `import "sys";` だけ —
それが監査の跡になります。

## トラップ

トラップは、検査が破られたときの実行時の答えです: メッセージ、そして
終了コード **134**。回復もハンドラも巻き戻しもありません — 設計として
フェイルストップです。メッセージは stderr に出ます。コンパイラが
インライン展開した検査はソース位置を、ライブラリが上げたトラップは
パッケージ名を名乗ります:

```
tests/005_trap_bounds.hc2:5: trap: out of bounds
heap: trap: double free
rt: trap: out of bounds
```

全種類:

| トラップ | 発生する状況 |
|------|-------------|
| `out of bounds` | capability の窓の外への添字・スライス・アクセス |
| `use after free` | ポインタの世代がヘッダと一致しなくなった |
| `write to read-only` | 読み取り専用 capability(文字列リテラル)へのストア |
| `division by zero` | ゼロの変数による `/` か `%` |
| `out of memory` | ヒープ領域が尽きた |
| `free: not the allocation base` | スライスや内部ポインタの free、不正な `release` のマーク |
| `double free` | 解放済みの割り当てをもう一度 free |
| `free of immortal` | リテラル・スタック・グローバルの capability を free |
| `call through null` | null 関数ポインタ経由の間接呼び出し |
| `not a function of this type` | 間接呼び出し先がシグネチャ検査に落ちた |
| `print of null` | null の `U8*` への `%s` |

## ランタイム

### プログラムの開始と終了

実行はルートパッケージ(コマンドラインで指名したディレクトリ)の `main`
から始まります。コンパイラは存在だけを検査し(`no main function in the
root package`)、慣習的なシグネチャは `I32 main()` です。戻り値の下位
32 ビットがプロセスの終了コードになります。末尾に到達すれば 0 で終了
します。`sys.exit(code)` でしか終わらないプログラムなら `U0 main()` でも
構いません。

### コマンドライン引数

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

`rt.argc()` はプログラム名を含めた個数、`rt.arg(i)` は `i` 番目の引数を
`U8*` として返します(長さに終端 NUL は含みません)。範囲外の添字は
`rt: trap: out of bounds` でトラップします。

## インラインアセンブリ

`asm` ブロックは 1 行 1 命令のリストで、ニーモニックとレジスタは
**大文字**です。オペランドは即値、レジスタ、ラベル、そして hc2 の
ローカル変数です。ローカル変数は名前のまま書けます:

```hc2
I32 main() {
    I32 a = 10;
    asm {
        MOV EAX, a       // hc2 の変数を読む
        ADD EAX, 5
        MOV a, EAX       // 書き戻す
    }
    "a: %d\n", a;        // a: 15
    return 0;
}
```

ラベルとジャンプはブロック内に閉じます。生のシステムコールに libc は
不要です:

```hc2
U0 raw_write(I64 fd, I64 addr, I64 len) {
    asm {
        MOV RAX, 1       // SYS_write
        MOV RDI, fd
        MOV RSI, addr
        MOV RDX, len
        SYSCALL
    }
}

// ...
U8* msg = "syscall from hc2\n";
raw_write(1, msg.addr, msg.len);
```

制約文字列も、オペランド節も、クロバーリストも — GCC のミニ言語は何も
ありません。コンパイラが命令列を読み、クロバーを自分で処理します
(書き込んだ callee-saved レジスタはブロックの前後で保存・復元されます)。

ルールは、それぞれ専用のコンパイルエラー付きです:

- オペランドの変数は**スカラーのローカル**でなければなりません(`an asm
  operand must be a scalar variable (use p.addr for a pointer)`)。
- レジスタ幅は変数の型と一致しなければなりません(`register width does
  not match`): `I32 a` に組むのは `EAX` で、`RAX` ではありません。
- メモリオペランド `[...]` は「コンパイラが検査しなかった唯一のロード/
  ストア」なので、`unsafe` ブロックが必要です(`memory operand: a load
  or store here would be the one the compiler did not check`)。
- x86 にメモリ間 move はなく、hc2 の変数はメモリ**そのもの**です:
  `a variable lives in memory: x86 has no mem,mem`。
- フレームはコンパイラの所有物で、`unsafe` でも譲りません。`RET` と
  `LEAVE` は不可(`the compiler owns the frame: no RET or LEAVE in an
  asm block`)、そして `RSP and RBP belong to the compiler`
  (arm64 では `SP`/`X29`)。
- 載っている命令だけがアセンブルされます: `not in the instruction menu
  (mnemonics are uppercase)`。

x86-64 のメニュー: `MOV ADD SUB AND OR XOR CMP TEST IMUL SHL SHR SAR XCHG
IN OUT`(2 オペランド)· `NEG NOT INC DEC MUL DIV IDIV PUSH POP CALL`
(1 オペランド)· `SYSCALL NOP CQO CPUID RDTSC HLT CLI STI IRETQ RET
LEAVE`(0 オペランド — 最後の 2 つはブロック内では拒否)· `JMP JE JNE JZ
JNZ JL JLE JG JGE JB JBE JA JAE JS JNS`(ラベル)。レジスタは `RAX` から
8 ビット形まで、`R8`–`R15` も含みます。

arm64 のメニューは最小限 — `sys` を書くのに足りる分です: `LDR STR MOVZ
EOR ADC`(2 オペランド)、`SVC`(1 オペランド)。レジスタは `X0`–`X30`。

## パッケージとターゲット

ターゲットは os/arch のペアです: `linux/amd64`、`linux/arm64`、
`macos/arm64`。(`macos/amd64` は認識された上で拒否されます:
`unsupported target macos/amd64`。)

どのファイルがどのターゲットでコンパイルされるかは、**ファイル名**が
決めます。末尾の `_` セグメントを右から読みます:

| ファイル名 | コンパイルされるターゲット |
|-----------|--------------|
| `rt.hc2` | すべて |
| `rt_linux.hc2` | linux の両ペア |
| `rt_arm64.hc2` | arm64 の両ペア |
| `rt_linux_arm64.hc2` | そのペアのみ |
| `sha256.hc2` | すべて(`sha256` は os でも arch でもない) |

このルールはすべてのパッケージに適用されますが、使っているのは 3 つだけ
です。`sys`、`rt`、`heap` が「機械が提供しなければならないもの」です。
どの機械でも同じやり方のものは無印のファイルに、その機械だけのやり方の
ものは接尾辞付きのファイルに置かれます。言語のそれ以外の部分は自分が
どの機械にいるかを知りません — ファイル内の条件付きコンパイルは
存在しません。

クロスコンパイルはフラグ 1 つです:

```sh
hc2 build -o server -target linux/arm64 .
```

ペアの半分だけ与えると(`-target arm64`)、残り半分はこの機械から
取られます。何も与えなければ、コンパイラ自身がビルドされたペアが対象に
なります。出力形式は os に従います: Linux は静的 ELF、macOS は PIE の
Mach-O — しかも署名はコンパイラ自身が行います(`hash.sha256` で計算する
アドホック署名。arm64 macOS は未署名のものを実行しません)。

macOS の注意点:

- そこでは `sys.self_path` が `-1` を返すため、「コンパイラへの symlink
  を張れば言語ルートも付いてくる」仕掛けは Linux 専用です。macOS では
  実パスでバイナリを起動してください。
- 実行中の実行ファイルをその場で上書きしてはいけません — macOS は
  書き換えられた inode を次の exec で kill します。新しいファイルに書くか、
  先に `unlink` します(コンパイラ自身もそうしています)。

## コンパイラ

### hc2 build

```
hc2 build [-o out] [-target p] [-noopt] [dir]
```

フラグの順序は自由で、残った引数がディレクトリです(デフォルト `.`)。
`-noopt` はオプティマイザを切ります — オプティマイザが何を稼いでいるかを
測るために存在します。診断は `hc2c1:` 接頭辞付きで exit 1 です。

### hc2 clean

```
hc2 clean [dir]
```

プロジェクトの `.hc2cache` ディレクトリを削除します: `removed 14 cached
objects`(または `nothing to clean`)。

### ビルドキャッシュ

コンパイラは**パッケージごとに 1 つのオブジェクト**を生成し、プロジェクト
ルートの `.hc2cache/` にキャッシュします(`.gitignore` に足して
ください)。パッケージのキャッシュキーが覆うのは: コンパイラのバイナリ
自身、ターゲット、`-noopt`、各ファイルのパスと内容 — そしてすべての
import 先の**インターフェイスハッシュ**です。

インターフェイスハッシュは import 側から見えるものだけを覆います:
エクスポートされた関数シグネチャと構造体レイアウトで、`_` プライベート名は
除外されます。帰結はこの 3 つに尽きます:

- 関数本体の編集は、そのパッケージ 1 つだけを再ビルドする。
- エクスポートされたシグネチャや構造体レイアウトの変更は、依存側を
  再ビルドする。
- プライベートな `_name` に触っても、決して伝播しない。

古いオブジェクトは `hc2 clean` まで溜まり続けます。どのビルドも全
パッケージのパースとレイアウトは行います(インターフェイスは生きた
ソースからハッシュされます)。キャッシュが節約するのは検査・コード生成・
アセンブルです。

### 配管コマンド

内部を覗くために:

```
hc2 build -noopt ...                 オプティマイザなし
hc2 [-c] [-target p] -S out.s <dir | file...>
                                     アセンブリで止める
hc2 --link [-target p] out a.s ...   与えたアセンブリをアセンブルしてリンクする
```

`-S` はバイナリの代わりに生成されたアセンブリのテキストを書き出します。
`-c` はライブラリモードで、`main` の必須要件を外します。`--link` は
内蔵アセンブラとリンカだけをアセンブリファイルに対して走らせます。

### ブートストラップ

`bootstrap/` には C コードもサードパーティのコードもありません —
入っているのはコンパイラ自身のアセンブリ出力、ターゲットごとに 1 つの
成果物です:

```
bootstrap/hc2c_linux_amd64.s
bootstrap/hc2c_linux_arm64.s
bootstrap/hc2c_macos_arm64.s
```

どの OS でも同じワンコマンドです。Linux では、システムのアセンブラが
成果物を最初のコンパイラに変え、そのコンパイラがソースから自分自身を
再ビルドします:

```sh
sh bootstrap/build.sh                       # -> src/build/hc2c
./src/build/hc2c build -o hc2 src/hc2       # 自分で自分をビルドしたコンパイラ
```

`sh bootstrap/build.sh -v` はさらに不動点を検証します: ビルドされた
コンパイラは成果物をバイト単位で再生成できなければなりません。

macOS には成果物の文法を話す外部アセンブラがないので、同じコマンドが
hc2 の `--link` で成果物を孵化させます。種は `src/build/` に残っている
動くコンパイラ(オフライン・数秒)、それがなければ Docker の中に
使い捨ての Linux コンパイラを組み立てて一度だけ使います。手動で
種をまくなら:

```sh
hc2 --link -target macos/arm64 out bootstrap/hc2c_macos_arm64.s
```

### セルフホストとテスト

```sh
sh tests/run.sh                          # linux/amd64。コンテナ内で
HC2_TARGET=linux/arm64 sh tests/run.sh
HC2_TARGET=macos/arm64 sh tests/run.sh   # Apple Silicon ではネイティブ
```

スイートはすべての `tests/NNN_name.hc2`(またはパッケージディレクトリ
`tests/NNN_name/`)をコンパイル・実行し、出力(stdout+stderr)を
`NNN_name.out` と、終了コードを `NNN_name.exit`(デフォルト 0。トラップは
134)と比較します。`NNN_name.cerr` があれば、代わりにコンパイルがその
テキストで**失敗する**ことを要求します。締めくくりにセルフホストを証明
します: `as` も `ld` も使わず自己リンクしたコンパイラが、チェックイン
済みの自分の成果物を、世代をまたいでバイト単位で再現しなければ
なりません。

### インストール

インストールされた hc2 はソースツリーと同じ形のディレクトリです。
バイナリが、自分のリンクするパッケージの隣に、1 つの `hc2.root`
マーカーの下に置かれます —

```
/usr/local/lib/hc2/
    hc2.root
    bin/hc2
    str/  fmt/  hash/  sys/  rt/  heap/
/usr/local/bin/hc2 -> /usr/local/lib/hc2/bin/hc2
```

Linux では symlink だけで十分です。コンパイラが自分の実パスを見つけるので、
言語ルート — `str`、`fmt`、`hash`、`sys`、`rt`、`heap` — も付いてきます。

リポジトリの `Dockerfile` はちょうどこのレイアウトを組み立てます。README
のコンテナ手順(`docker build --platform linux/amd64 -t hc2 .`)が
Linux 以外のホストでの推奨ルートです。

## エディタ対応

リポジトリの `zed/` は `.hc2` ファイルのシンタックスハイライトを提供する
Zed 拡張です(言語サーバはまだありません)。Zed の
`zed: install dev extension` で `zed/` ディレクトリを指定して
インストールします。

## 付録

### キーワード

```
as       asm      break    case     const    continue default
defer    else     fallthrough       for      if       import
null     return   sizeof   struct   switch   true     false
union    unsafe
```

加えて型名: `U0 Bool I8 I16 I32 I64 U8 U16 U32 U64 F64`。

(厳密にはキーワードは文脈依存です。字句解析器は識別子・数値・文字列・
記号しか知りません。それでも、予約語として扱うのが唯一まともなスタイルです。)

### 演算子優先順位表

```
1  (最弱)      ||
2              &&
3              == !=
4              <  <=  >  >=
5              +  -  |  ^
6              *  /  %  <<  >>  &
7              as T
8              単項 -   単項 &
9  (最強)      f(...)  a[i]  p[lo : hi]  .field
```

### トラップ一覧

すべてのトラップは stderr に印字して **134** で終了します。コンパイラが
インライン展開した検査は `file:line: trap: <理由>` を、ライブラリの検査は
`heap: trap: …` や `rt: trap: …` を印字します。

```
out of bounds                    use after free
write to read-only               division by zero
out of memory                    free: not the allocation base
double free                      free of immortal
call through null                not a function of this type
print of null
```

### 上限値

| 上限 | 値 |
|-------|-------|
| 関数あたりのローカル数 | 1024 |
| 配列の次元数 | 8 |
| プログラムあたりのパッケージ数 | 64 |
| パッケージあたりの import 数 | 24 |
| パッケージあたりのファイル数 | 256 |
| switch のテーブル幅 | 4096 |
