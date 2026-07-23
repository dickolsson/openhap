---
name: add-dependency
description:
  Add or change a runtime, test, or develop dependency. Use when a new Perl
  module or OS package is needed, or when editing deps/*.txt or the cpanfile.
---

# Add a Dependency

## Objective

Add a dependency to the authoritative manifests in `deps/` while keeping the
dependency footprint minimal.

## Workflow

1. Question the need first: dependencies require justification. Prefer the Perl
   base system, and use `require` for conditional loading so optional
   dependencies stay optional.

2. Add a line to each applicable platform manifest — `deps/OpenBSD.txt`,
   `deps/Linux.txt`, `deps/Darwin.txt` — in the format:

   ```
   <environment> <type> <name>
   ```

   where `<environment>` is `runtime`, `test`, or `develop` and `<type>` is
   `pkg` (OS package) or `cpan`. Prefer `pkg` over `cpan`: OS packages are
   vetted, binary, and upgraded with the system (on OpenBSD use the native
   `p5-*` packages).

3. If it is a Perl dependency, add it to the `cpanfile` too. The `cpanfile`
   exists only for development convenience and carton compatibility — the
   `deps/*.txt` manifests remain authoritative, and the two must stay in sync.

4. Verify with `make deps` (runtime), `make deps-test`, or `make deps-develop`
   on the platforms you can, and run `make check`.

5. Commit with the `build` type, e.g. `build: add p5-Foo-Bar for <reason>`.

## References

- `scripts/deps.sh` — how the manifests are parsed and installed
- `INSTALL.md` — user-facing installation steps
