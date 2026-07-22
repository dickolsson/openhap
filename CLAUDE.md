# CLAUDE.md

OpenHAP is a HomeKit Accessory Protocol (HAP) server for **OpenBSD**, written in
Perl (v5.36, base-system Perl, minimal dependencies). It bridges MQTT-connected
Tasmota devices to Apple HomeKit: SRP-6a pairing, Ed25519, X25519,
ChaCha20-Poly1305, HKDF-SHA-512, and TLV8 over encrypted HTTP/1.1, advertised
via mDNS. OpenBSD is the production platform (pledge(2)/unveil(2), rc.d,
`_openhap` user); Linux and Darwin are supported for development and CI only.

The repo contains three Perl namespaces with distinct concerns:

- `OpenHAP::` (`lib/OpenHAP/`) — the HAP server itself
- `FuguLib::` (`lib/FuguLib/`) — generic OpenBSD-style daemon utilities
  (daemonize, privilege drop, signals, logging, process, state)
- `OpenHVF::` (`lib/OpenHVF/`) — QEMU VM harness used only for integration
  testing, driven by `bin/openhvf` and `.openhvfrc`; not shipped to users

## Commands

```sh
make check          # tidy + lint + test; MUST pass before every commit
make test           # prove -l -v t/openhvf/*.t t/openhap/*.t
prove -l t/openhap/foo.t   # run a single test file
make lint           # Perl::Critic, severity 4
make tidy           # check perltidy formatting
make tidy-fix       # auto-fix Perl formatting
make prettier       # check Markdown/JSON/YAML formatting
make prettier-fix   # auto-fix Markdown/JSON/YAML
make deps           # install runtime dependencies
make deps-test      # runtime + test dependencies
make deps-develop   # all dependencies (adds QEMU, SSH, etc.)
make integration    # provision OpenBSD VM and run integration tests
```

Ad-hoc testing in the OpenBSD VM:

```sh
make vm-provision
bin/openhvf ssh 'rcctl restart openhapd'
bin/openhvf ssh 'tail -f /var/log/daemon'
```

## Layout

- `bin/` — `openhapd` (daemon), `hapctl` (control CLI), `openhvf` (test VM CLI)
- `lib/OpenHAP/` — protocol (`HAP.pm`, `HTTP.pm`, `TLV.pm`), crypto
  (`Crypto.pm`, `SRP.pm`, `Pairing.pm`, `Session.pm`), data model
  (`Accessory.pm`, `Service.pm`, `Characteristic.pm`, `Bridge.pm`), config
  (`Config.pm`, `Storage.pm`), integration (`MQTT.pm`, `MDNS.pm`,
  `DeviceLoader.pm`), devices (`Tasmota/*.pm`)
- `t/openhap/`, `t/fugulib/`, `t/openhvf/` — unit tests;
  `t/openhap/integration/` — integration tests, run inside the OpenBSD VM
- `man/openhap/` — mdoc(7) man pages: `openhapd.8`, `hapctl.8`,
  `openhapd.conf.5`
- `spec/` — extracted protocol references (`HAP.md`, `HAP-*.md`, `MQTT.md`,
  `IMPLEMENTATIONS.md`)
- `deps/` — per-OS dependency manifests; `scripts/` — dependency and VM helpers
- `external/` — reference HAP implementations; gitignored, not present unless
  fetched

## Coding style

OpenBSD style(9): 8-character tabs, continuation lines indent 4 spaces.
Formatting is enforced by `make tidy` and `make lint` — run `make tidy-fix`
rather than hand-formatting. `.perlcriticrc` deliberately relaxes many rules to
match OpenBSD style; do not "fix" code toward generic Perl::Critic defaults.

Rules the tools cannot enforce:

- Always `use v5.36` (enables strict, warnings, say, signatures)
- Object-oriented style with signatures; object is `$self`; internal methods
  prefixed with `_`; do not name unused parameters: `sub foo($, $) { }`
- Function brace on its own line, control-structure brace on the same line:

```perl
sub method($self, $param)
{
	if ($condition) {
		...
	}
	return $result;
}
```

- Explicit `return` except for no-return or constant methods; omit parens on
  zero-argument method calls: `$object->width`
- Inheritance via `our @ISA` (not `use parent`); no multiple inheritance;
  multiple related packages per file are fine; constants via `use constant`
- New files start with the `# ex:ts=8 sw=4:` modeline and ISC copyright header —
  copy from an existing file in `lib/`

## Error handling and security

- Return `undef` (bare `return`) for recoverable errors, `die` for programming
  errors; never use `eval` for flow control
- Never ignore return values of system calls:
  `open my $fh, '<', $file or do { warn "..."; return; };`
- No threads — multiplex with `IO::Select`
- Signal handling via `FuguLib::Signal` object handlers; daemonization and
  privilege drop via `FuguLib::Daemon` and `FuguLib::Privdrop`
- Security by default: randomness from `/dev/urandom`, design for
  pledge(2)/unveil(2), drop privileges early, fail closed, never trust external
  input
- Startup ordering in `bin/openhapd` is delicate: the daemon chowns
  `/var/db/openhapd`, drops to `_openhap`, then re-initializes logging and
  registers mDNS — changes to this order can break syslog or mDNS

## Testing

- `Test::More` with `done_testing()`; tests skip gracefully when a dependency is
  unavailable (`plan skip_all => ...`); mirror an existing test in `t/openhap/`
  when adding one
- Integration tests verify the real system end-to-end: make actual HTTP requests
  to HAP endpoints, connect to sockets, run `hapctl` and `rcctl` — never parse
  logs to assert behavior
- Be resilient to timing variations; skip when the environment lacks
  prerequisites
- Every feature needs tests

## Documentation

Three documentation sources with no information overlap:

1. Man pages in `man/openhap/` (mdoc(7)) — the authoritative technical reference
   for daemon, control utility, and configuration
2. `README.md` — high-level introduction and quick start
3. `INSTALL.md` — installation and setup procedures

Module APIs are documented in sidecar `.pod` files next to each `.pm` — never
inline POD in `.pm` files. Update the relevant documentation with any change in
behavior, options, or configuration.

## Dependencies

`deps/{OpenBSD,Linux,Darwin}.txt` are authoritative (installed by `make deps`
via `scripts/deps.sh`). Format: `<environment> <type> <name>` where environment
is `runtime`, `test`, or `develop` and type is `pkg` (OS package, preferred) or
`cpan`. The `cpanfile` exists only for development convenience and carton
compatibility — keep both in sync when adding a Perl dependency. Minimize
dependencies; use `require` for conditional loading.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/):
`<type>(<scope>): <description>` with types `feat`, `fix`, `docs`, `style`,
`refactor`, `perf`, `test`, `build`, `ci`, `chore` and module scopes such as
`hap`, `mqtt`, `crypto`, `bridge`, `config`, `daemon`, `tasmota`, `vm`. Breaking
changes take `!` or a `BREAKING CHANGE:` footer.

```
feat(mqtt): add support for retained messages
fix(crypto): correct ChaCha20-Poly1305 nonce handling
```

Always run `make check` before committing; fix formatting failures with
`make tidy-fix`.

## Gotchas

- Version numbers derive from `git rev-list --count HEAD` (release tag `b<N>`);
  there is no VERSION file
- `external/` is gitignored — skills that read reference implementations need it
  fetched first (see `spec/README.md`)
- Use `explore/` (gitignored) for scratch scripts and experiments, never `/tmp`
- Audit findings go to `SCRATCHPAD-<N>.md` files (gitignored)

## What NOT to do

- `eval` for flow control
- Ignore return values of system calls
- Regex when simple string operations suffice
- Features without tests
- Indirect object notation (`new Class` instead of `Class->new`)
- Code that fails `make lint`
- Dependencies without justification
- Threads (use `IO::Select` for multiplexing)
- Code refs without parentheses (except delegation)
- Old-style function prototypes unless creating syntax
- `wantarray()` to change semantics (optimization only)
