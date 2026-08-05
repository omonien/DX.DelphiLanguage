# DX.DelphiLanguage

A **language model for Delphi written in Delphi**, targeting the language surface
of **Delphi 13.1 (Florence)**. It provides a full-fidelity **concrete syntax
tree (CST)**, a cleaner **abstract syntax tree (AST)**, and a lowering pass that
turns one into the other.

The project consists of a library (`src/`) plus two console applications:
`DLDemo` (lex → CST → AST dump) and `DX.Delphi.Tests` (DUnitX unit tests).

---

## What is in this repository

| Path | Purpose |
|---|---|
| `src/DX.Delphi.Core.pas` | Shared vocabulary: tokens, keywords, source spans, diagnostics, symbol table, dump helpers |
| `src/DX.Delphi.Lexer.pas` | Full tokenizer (Delphi 13.x surface, incl. multiline strings) |
| `src/DX.Delphi.CST.pas` | Concrete syntax tree node hierarchy |
| `src/DX.Delphi.Parser.pas` | Recursive-descent parser producing the CST |
| `src/DX.Delphi.AST.pas` | Abstract syntax tree node hierarchy |
| `src/DX.Delphi.AstBuilder.pas` | CST → AST lowering pass |
| `DLDemo.dpr` | Console demo: dumps tokens, CST, AST, symbols, diagnostics |
| `samples/Demo.pas` | Sample exercising the covered language surface |
| `tests/` | DUnitX test project (168 tests, incl. real-world fixtures) |
| `libs/DUnitX` | DUnitX test framework (Git submodule, test-only) |
| `libs/spring4d` | Spring4D sources — **test fixture only, NOT a dependency** |

All source files are UTF-8 with BOM and CRLF line endings.

---

## CST vs. AST — the two trees and when to use which

This is the central design decision of the library, so it deserves a detailed
explanation.

### Concrete Syntax Tree (CST) — *what the source looks like*

The CST is a **full-fidelity parse tree**: it mirrors the grammar of Delphi
almost one-to-one and preserves everything a tokenizer can see:

- **Exact source spans** on every node (`line:col` of first and last token).
- **Trivia** — whitespace, `//` and nested `{ }` / `(* *)` comments, and
  `{$...}` compiler directives — attached to the nodes that own them.
- **Token-level layout**: every identifier, literal and operator symbol is
  represented, including `&`-escaped identifiers and the original literal
  spelling (`$FF_00` stays `$FF_00`, `%1010` stays `%1010`).
- **Constructs that the grammar only distinguishes syntactically**: `begin`
  blocks, `case` selectors, method directives (`virtual`, `message N`,
  `external 'x' name 'y' index 3`, …), property clauses (`read`/`write`/
  `stored`/`default`/`implements`), record variant parts, visibility markers.

In short: **the CST is the source code, as data.** You can reconstruct the
original text (modulo normalised trivia) from it, and you can answer questions
like "which tokens belong to this expression?" or "what comments were above
this method?".

### Abstract Syntax Tree (AST) — *what the source means*

The AST is the **cleaned-up semantic tree**. The lowering pass (`AstBuilder`)
walks the CST and:

- **Drops trivia and tokens.** Positions are still carried as spans, but no
  comments, whitespace or literal spellings survive.
- **Turns identifiers into plain strings** — no `&` markers, no token records.
- **Folds grammar into meaning.** A `type` section becomes a flat list of type
  declarations; `begin … end` becomes a block of statements; the exact place
  of a `+` operator in the source no longer matters, only the resulting
  operator node.
- **Adds semantic structure**: `array of X` becomes a dynamic-array type,
  `class helper for T` becomes a class-type with a helper flag, anonymous
  methods and method declarations share a procedural shape.
- **Records symbols** in a flat symbol table (types, consts, vars, fields,
  methods, labels, …) — a starting point for name resolution and tooling.

In short: **the AST is the program, as data.** It is what a semantic analyser,
an IDE feature, a linter, a formatter's logic or a code generator wants to
consume.

### Differences at a glance

| Aspect | CST | AST |
|---|---|---|
| Trivia (comments, whitespace, directives) | kept | dropped |
| Token spellings / `&`-escapes | kept | normalised to names |
| Source spans | exact on every node | kept, but coarse |
| Grammar shape | mirrors the Delphi grammar | folds grammar into meaning |
| Symbol table | — | populated during lowering |
| Typical consumers | formatters, refactoring with exact edits, syntax highlighting, round-tripping | semantic analysis, linting, code gen, IDE navigation |
| Cost | larger, more nodes, more memory | smaller, cleaner to walk |

### When to use which

**Use the CST when the answer depends on how the code is written:**

- **Formatting / pretty-printing** — you need the trivia and token order to
  make minimal, faithful edits.
- **Refactoring with precise edits** — renaming a symbol, extracting a
  method, moving a block: you want exact spans and the original text.
- **Syntax highlighting / source navigation** — you need every token and its
  position.
- **Round-tripping** — parse → modify → regenerate source text.
- **"What's above/below/around this declaration?"** — comments and directives
  live only in the CST.

**Use the AST when the answer depends on what the code means:**

- **Semantic analysis** — types, scopes, symbol resolution, control-flow.
- **Linting / static analysis** — "is this call always inside a `try`?",
  "does this method override something?".
- **Code generation / transformation** — you want the clean tree, not the
  source text.
- **IDE features** — outline, go-to-definition, call hierarchy, hover
  information (usually paired with a symbol table).
- **Documentation generation** — you want the shape of declarations, not their
  exact spelling.

In practice most serious tooling builds **both**: the parser produces the CST,
then a lowering pass produces the AST, and each layer answers the questions it
is good at. That is exactly the pipeline this repository implements.

---

## Building

### Prerequisites

- Embarcadero Delphi 13.1 (Florence) — `dcc32` on the machine (`C:\Program
  Files (x86)\Embarcadero\Studio\37.0\bin`).
- Git (for the DUnitX submodule).

### One-time setup

```bash
git submodule update --init --recursive
```

### Demo (command line)

```bash
dcc32 -Q -CC -U"X:\DX.DelphiLanguage\src" \
      -N"X:\DX.DelphiLanguage\build\win32\Debug\dcu" \
      -E"X:\DX.DelphiLanguage\build\win32\Debug" \
      -DDEBUG X:\DX.DelphiLanguage\DLDemo.dpr

DLDemo.exe samples\Demo.pas
```

`DLDemo` prints the token stream, the CST dump, the AST dump, the recorded
symbols and any diagnostics. It exits `0` on a clean parse, `2` if diagnostics
contain errors.

### Tests (DUnitX)

```bash
dcc32 -Q -CC -U"X:\DX.DelphiLanguage\src" -U"X:\DX.DelphiLanguage\libs\DUnitX\Source" \
      -N"X:\DX.DelphiLanguage\build\win32\Debug\dcu" \
      -E"X:\DX.DelphiLanguage\tests" \
      -DDEBUG X:\DX.DelphiLanguage\tests\DX.Delphi.Tests.dpr

DX.Delphi.Tests.exe
```

### IDE / MSBuild

Open `DX.DelphiLanguage.groupproj` in the IDE (contains `DLDemo` and
`DX.Delphi.Tests`), or build from the command line:

```bash
msbuild DLDemo.dproj /p:Config=Debug /p:Platform=Win32 /t:Build
msbuild tests\DX.Delphi.Tests.dproj /p:Config=Debug /p:Platform=Win32 /t:Build
```

Output goes to `build\$(Platform)\$(Config)\` (EXE) and
`build\$(Platform)\$(Config)\dcu\` (DCUs), per the project rules.

---

## Language surface covered

**Modules:** `program`, `unit`, `library`, `package` (with `requires`/
`contains`), interface + implementation sections, `uses` clauses with dotted
names and `in 'file'`, `initialization`/`finalization`, `exports`.

**Declarations:** `const` (typed and untyped), `resourcestring`, `var`,
`threadvar`, `label`, `type`; attributes `[...]`; `absolute`.

**Types:** named types and generic instantiations (`TList<Integer>`), `string`
and `string[n]`, static and dynamic arrays (`array[1..3, 1..3] of X`,
`array of array of X`), sets, enums, subranges, pointers, `file`, records
(incl. variant `case` parts and custom-managed-record operators), classes
(`sealed`/`abstract`, helpers, class references `class of`, nested `type`
sections), interfaces/dispinterfaces with GUIDs, old-style `object`,
procedural types (`of object`, `reference to`), generic type declarations with
type parameters.

**Members:** fields, `class var`, methods (procedure/function/constructor/
destructor/`class`/`class operator`), method directives (`virtual`, `dynamic`,
`override`, `abstract`, `reintroduce`, `overload`, `message N`, `static`,
`final`, `sealed`, `inline`, `assembler`, `forward`, `external`, calling
conventions, `deprecated`, …), properties (`read`/`write`/`stored`/`default`/
`nodefault`/`index`/`implements`, indexed properties), visibility markers
(`strict private` … `published`).

**Statements:** compound, assignment, `if`, `case` (with ranges and `else`),
`for` (`to`/`downto`/`in`, inline loop variables), `while`, `repeat`, `with`,
`try`/`except` (with `on`-handlers and `else`)/`finally`, `raise` (incl.
`at`), `goto`, labels, `asm`, `exit [expr]`, `break`, `continue`, inline
`var` declarations, empty statements.

**Expressions:** full Delphi precedence, unary `+ - not @`, postfix `^`,
`inherited`, set and array constructors, string/char-code sequences, member
access, indexing, calls, generic instantiation (`TList<Integer>.Create`),
anonymous method expressions (`procedure`/`function`/`reference to`).

**Lexer:** case-insensitive keywords, `&`-escaped identifiers, Unicode
identifiers, multiline strings `'''…'''` (with the empirically verified
quote-run rules), `#` char codes (decimal/hex/binary), integers
(dec/`$`hex/`%`binary) with `_` separators, floats, nested block comments,
`//` comments, `{$...}` directives.

---

## Design decisions & limitations

- **Compiler directives are trivia, not evaluated.** Conditional compilation
  (`{$IFDEF}` etc.) is not performed; all branches are parsed and kept as
  trivia attached to CST nodes.
- **`T(x)` casts parse as ordinary calls** (they are syntactically identical);
  `Default(T)`, `SizeOf` etc. also parse as ordinary calls.
- **Tolerant parsing**: unknown or malformed constructs produce diagnostics
  and parsing continues at a safe resynchronisation point instead of aborting.
- **Generic instantiation vs. `<` comparison** is disambiguated by speculative
  parsing (position save/restore) with the lookahead rule: `Name<Type…>` is a
  generic instantiation only when followed by `( ) ; : , = . [ ]`.
- The symbol table is deliberately **flat and scope-less** (later
  declarations with the same name are ignored) — a starting point, not full
  name resolution.
- Method local `var`/`label`/`const`/`type` sections are lowered into the
  method's `LocalDeclarations` (both `TDLMethod` and `TDLProcDecl`).
- Generic type **declaration** parameters (`TList<T>`) are carried into the
  CST (`TDLTypeDecl.TypeParams`) and wrapped as `TDLGenericTypeDef` in the
  AST; generic type **instantiations** are fully represented.
- AST scalar values (const values, variable initializers, property defaults,
  parameter defaults) are full expression trees, not rendered strings.
- `break`/`continue`/`name`/`on`/`at`/`ref`/`helper`/`operator` are treated
  as keywords by the lexer; the parser accepts them as identifiers where
  Delphi treats them contextually.

---

## License

MIT — see the unit headers. Copyright © 2026 Olaf Monien.

---

## Real-world parse fixtures (Spring4D + Delphi RTL)

Two DUnitX fixtures (`Tests.DX.Delphi.RealWorld`) parse large real-world
codebases through the lexer/parser as a robustness and regression net:

- **Spring4D** (`libs/spring4d`, a Git submodule of the Spring4D source
  mirror). It is used **only** as practical test input — it is **not** a
  dependency of the DX.Delphi implementation. The library itself links
  against nothing but the RTL.
- **Delphi 13.1 RTL** (`C:\Program Files (x86)\Embarcadero\Studio\37.0\source\rtl`),
  if the compiler is installed on the machine; the fixture skips gracefully
  otherwise.

Current status (tracked by the fixtures):

| Corpus | Files | Result |
|---|---|---|
| Spring4D | 180 | parse without crashes; 1 070 diagnostics to reduce |
| Delphi 13.1 RTL | 584 | 3-6 known crash files; 2 841 diagnostics to reduce |

The fixtures assert that **no file crashes or hangs the parser** (a handful
of files with known deep-desync recursion issues are explicitly listed as
known crashes and excluded from that assertion — removing them from the list
is the progress metric). The remaining diagnostics are the measured distance
to the goal of parsing Spring4D and the Delphi RTL **100 % error-free**. That
claim will be made in this README only once the diagnostic count reaches
zero; it is currently work in progress.
