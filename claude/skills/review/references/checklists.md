# Language-Specific Review Checklists

Reference file for the review skill. Load only when needed for detailed checks.

---

## Python

### Automated Tools
```bash
uvx ruff check .          # linting
uvx ruff format --check . # formatting
uvx mypy .                # type checking
pytest -q                 # tests
```

### Manual Checks
- [ ] Type hints on public function signatures
- [ ] No bare `except:` — catch specific exceptions
- [ ] Context managers for file/resource handling (`with` statements)
- [ ] No mutable default arguments (`def f(x=[])`)
- [ ] f-strings preferred over `.format()` or `%`
- [ ] `pathlib.Path` over `os.path` for new code

---

## Node / JavaScript / TypeScript

### Automated Tools
```bash
npm run lint              # ESLint
npm run typecheck         # tsc --noEmit (if TypeScript)
npm test                  # test suite
```

### Manual Checks
- [ ] `async/await` with proper error handling (try/catch or `.catch()`)
- [ ] No `any` type in TypeScript (use `unknown` or specific types)
- [ ] Dependencies in correct section (`dependencies` vs `devDependencies`)
- [ ] No `console.log` left in production code
- [ ] Proper null checks (`??` / `?.` operators)

---

## Go

### Automated Tools
```bash
go vet ./...
golangci-lint run
go test ./...
```

### Manual Checks
- [ ] Errors checked immediately after function calls
- [ ] `defer` for cleanup (file close, mutex unlock)
- [ ] No goroutine leaks — channels closed or context cancelled
- [ ] Exported names have doc comments
- [ ] Avoid `init()` functions when possible

---

## Rust

### Automated Tools
```bash
cargo clippy -- -D warnings
cargo test
cargo fmt --check
```

### Manual Checks
- [ ] `unwrap()` / `expect()` only in tests or with justification comment
- [ ] Proper lifetime annotations (avoid unnecessary `'static`)
- [ ] `Clone` not used to dodge borrow checker — consider references first
- [ ] Error types implement `std::error::Error`

---

## Shell / Bash

### Automated Tools
```bash
shellcheck *.sh
```

### Manual Checks
- [ ] `set -euo pipefail` at script start
- [ ] Variables quoted: `"$var"` not `$var`
- [ ] No hardcoded paths — use variables or `$(dirname "$0")`
- [ ] Exit codes are meaningful (not just 0/1)
- [ ] Functions used for repeated logic
