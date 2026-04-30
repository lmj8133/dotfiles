---
scope: Firmware / embedded C development
trigger: C/C++ files (.c/.h/.cpp), register access, ISR, peripheral drivers, in-house build system, linker scripts, vendor SDK config files
---

# Firmware Rules

## Build & Verify

* **Builds run in a vendor IDE, not from the shell.** Do not suggest `make`, `cmake`, or `gcc` invocations for the firmware build itself unless the project shows they exist.
* Verification on hardware is typically: re-flash → observe UART log → use ICE if needed.
* When asked to "verify" or "test" a hardware-side change, ask the user how they will verify (log inspection, ICE step-through, regression on hardware) — don't assume automated regression exists.

## Coding Style

* **New C code uses strict K&R**:
  * Function-definition `{` on its own line
  * Control-structure `{` on the same line as the keyword
  * Tab indentation
* **For existing code, do not reformat to K&R.** Per global §2 (Surgical changes), don't rewrite the brace / indent style of code you didn't author. New functions / files / blocks you create from scratch follow strict K&R; modifications to existing code keep the original style to avoid noisy diffs that obscure the real change (especially when reviewing or merging colleagues' work).
* All hardware-touching variables: `volatile`. Memory-mapped reads/writes use sized types (`uint32_t`, not `int`).
* Be explicit about **integer width and signedness** (`uint8_t` not `char`, `int32_t` not `int`) when the value crosses a hardware or protocol boundary.

## Before Modifying Code

These vary per project and **must not be assumed** — check existing patterns first:

* **RTOS or bare-metal** — read `main.c` / startup code or scheduler entry to determine. ISR-safety, blocking calls, and stack discipline depend on this.
* **Register access pattern** — direct `*(volatile uint32_t*)0x...`, CMSIS, vendor HAL, or in-house driver layer. **Match the surrounding file's existing pattern** (this applies to both new and existing code — do not introduce a new abstraction either way).
* **Memory allocation** — check whether `malloc`/`free` is used. Many firmware projects forbid dynamic allocation; default to **static / pool-only** unless the project clearly uses heap.

## ISR Discipline

* Keep handlers short: no blocking calls, no `printf` (or only ISR-safe variants), defer real work via flags / queues to a non-ISR context.
* Shared state between ISR and main context: `volatile` + atomic access or critical section.

## Logging

* UART log is the primary observation channel.
* **Match the project's existing log macro / level convention** (look for `LOG_INFO`, `printf`, `DBG_PRINT`, etc.) — do not introduce a new logging facility.

## Testability — Host-side Unit Tests with GoogleTest

Host-side unit testing is being introduced. The chosen framework is **GoogleTest** (used to test C code via a C++ test harness).

When writing new firmware code:

* **Separate pure logic from hardware access.** Pure logic (parsing, state machines, transformations) should live in functions that take buffers / structs as input — not in functions that read registers directly.
* This makes the production code testable on a host without retrofitting a hardware abstraction layer.

When writing or scaffolding tests:

* **Test files are C++** (`.cpp`), production code stays **C** (`.c`/`.h`).
* Wrap C headers in `extern "C" { ... }` when including from `.cpp`, or ensure the C header itself uses `#ifdef __cplusplus` guards.
* **Test layout: `tests/` directory** with its own host build (default to CMake unless the project specifies otherwise) — kept independent from the vendor IDE firmware build.
* Hardware-dependent code (register access, peripheral drivers) is **out of scope** for host tests. Stub or fake it at the interface boundary.

## Risky Operations

These trigger global rule §1(b) (irreversible or affects shared state) — confirm before acting:

* Re-flashing customer-shipped boards or production / mass-production fixtures
* Erasing / writing non-volatile memory (calibration data, MAC address, fuses)
* Changing linker scripts, memory map, or interrupt vector table
* Modifying bootloader or DFU paths
* Bumping any toolchain / SDK version that other team members share

## Domain-Specific Ask Triggers

Cases in firmware work where the answer would change the approach:

* "Is there an RTOS?" — only when the change involves blocking calls, shared state, or anything that could run in ISR context
* "What's the register access convention?" — only when introducing access to a peripheral that has no existing pattern in this file
* "How will you verify?" — only when the change is non-trivial and I need to shape it for your verification path
* "Is dynamic memory allowed?" — only when I'd otherwise reach for `malloc`
