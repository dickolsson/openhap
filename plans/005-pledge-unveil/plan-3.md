# Phase 3 — `FuguLib::Sandbox` and pledge(2)

Build the platform abstraction and apply the pledge. Depends on phase 2: while
`openhapd` spawns `mdnsctl`, the promise set would need `proc exec` and the
exercise would be close to pointless.

## Tasks

### 3.1 `FuguLib::Sandbox`

One module, both mechanisms, three platforms. The whole point is that callers
never write `if ($^O eq 'openbsd')`.

```perl
FuguLib::Sandbox->is_supported;                       # 1 on OpenBSD, '' elsewhere
FuguLib::Sandbox->pledge(promises => $string);        # 1, or die
FuguLib::Sandbox->unveil(paths => [[$path, $perms]]); # 1, or die
FuguLib::Sandbox->unveil_lock;                        # 1, or die
```

- On OpenBSD, `OpenBSD::Pledge` and `OpenBSD::Unveil` are loaded at compile
  time. They are base-system modules; failing to load them there means a broken
  Perl, so that is fatal at `use` time rather than a runtime fallback to "no
  protection".
- Off OpenBSD every method is a no-op returning 1.
- `pledge` and `unveil` failures `die` with the promise string or path and `$!`.
  Fail closed: there is no `force => 0` and no warn-and-continue mode. A daemon
  that cannot restrict itself must not start.
- `unveil(paths => [[$path, $perms], ...])` takes an **ordered list of pairs**,
  applies them in order, and reports which pair failed. Not a flat
  `path => $perms` hash: hash key order is randomised, duplicate paths are
  inexpressible, and unveil _replaces_ rather than merges a path's permissions,
  so parent-then-child ordering is load-bearing.
- Each pair may be marked optional (a third element, or a `{ optional => 1 }`
  form — pick one and document it). A missing **required** path is a failure,
  not a skip: a typo'd path silently accepted is the failure mode that makes
  unveil useless. A missing **optional** path is skipped and reported to the
  caller. Phase 4 needs both, because three of its paths are legitimately absent
  on a working system.
- `unveil_lock` calls `OpenBSD::Unveil::unveil()` with **no arguments**. Not
  `unveil(undef, undef)`: the XS defaults to `NULL` only when the arguments are
  _absent_, so two `undef` SVs arrive as `""` and the call fails with `ENOENT` —
  which, under the die-on-failure rule above, would stop the daemon from
  starting at all.
- Keep it stateless: class methods, no object. It wraps two syscalls that are
  themselves process-global.
- **No logging.** No module under `lib/FuguLib/` references a logger, and a
  stateless class has nowhere to keep a "logged once" flag anyway. The caller
  logs. `is_supported` is how a caller or a test distinguishes enforcement from
  emulation — a return value, not a log line to be grepped. This matters for
  phase 5, whose integration tier is forbidden from parsing logs.

Ships with `man/fugulib/Sandbox.3p`, a `MAN3P` entry, and `t/fugulib/sandbox.t`.

The test must be meaningful on both kinds of platform, which needs care:

- Everywhere: `is_supported` agrees with `$^O`; a no-op platform returns 1 from
  every method and does not die; a malformed `paths` argument dies.
- On OpenBSD only: **`pledge()` in a forked child, assert in the parent.** A
  pledge violation goes through the kernel's `pledge_fail()`, which resets the
  handler to `SIG_DFL` and delivers an uncatchable `SIGABRT` — the child is gone
  at the moment of violation and cannot emit a TAP line about it. So the child
  pledges `stdio`, attempts `socket(AF_INET)`, and `POSIX::_exit`s if it somehow
  survives; the parent `waitpid`s and asserts `POSIX::WIFSIGNALED($?)` and
  `POSIX::WTERMSIG($?) == POSIX::SIGABRT` — not the raw-bitmask prose form
  `$? & 127 == SIGABRT`, a precedence trap: `==` binds tighter than `&`, so it
  parses as `$? & (127 == SIGABRT)` and is constant false. The macros also
  distinguish a child that _exited_ with status 134 from one _killed_ by signal
  6, which matters for the core-dump route below. Never assert in the child:
  `Test::More` in a forked child duplicates the inherited test counter and
  interleaves TAP on the same fd, which `prove` reports as a plan mismatch, and
  the parent must never pledge itself or it takes the rest of the suite down.
- **Suppress the core dump.** The abort drops `perl.core` into the test's cwd —
  the repo root under `prove -l` — against `CLAUDE.md`'s "leave no partial
  files". Set `RLIMIT_CORE` to 0 in the child before pledging. `BSD::Resource`
  is in neither `deps/OpenBSD.txt` nor `cpanfile`, so either add it as an
  OpenBSD test dependency (`p5-BSD-Resource`) or have the forked child exec
  `sh -c 'ulimit -c 0; exec perl ...'`. The two routes are **not** otherwise
  interchangeable: without the explicit `exec`, the shell — not the pledging
  perl — is the parent's direct child, and a shell that reaps an aborted
  grandchild exits normally with status 134, so `WIFSIGNALED` is false in the
  parent and the termsig assertion fails even when pledge worked. With the
  `exec`, the shell replaces itself and the SIGABRT lands in the parent's wait
  status as before. The re-exec'd perl inherits none of `prove -l`'s switches,
  so pass the repo lib explicitly (`-I` or `PERL5LIB`). Decide before writing
  the test, and clean up any core file the test does produce.
- On OpenBSD only: a child that unveils `$tmpdir` read-only, locks, then fails
  to open a file outside it and succeeds inside it — same child/parent split.
- On OpenBSD only, same child/parent split: the disposition semantics. A missing
  **required** path makes `unveil` die — the child expects the die and reports
  it as a distinct exit status — and a missing **optional** path does not: that
  child mixes a real tempdir pair with a nonexistent optional pair, locks,
  proves the real pair still enforces, and exits 0. These are the semantics
  phase 4's inventory stands on; they are implemented and documented in this
  phase, so they are tested in this phase — phase 4 extends them, it does not
  introduce them.
- A bogus promise string dies rather than being accepted.

Guard the OpenBSD-only cases per-subtest with a skip message naming the reason;
the file as a whole is not OpenBSD-specific, so no file-level `skip_all`.

The OpenBSD-only subtests need an OpenBSD executor, and none exists today:
`make check` runs on Linux CI, and `scripts/integration:22` ships only
`t/openhap/integration/`, `t/lib/` and `lib/OpenHAP/Test/` into the VM, whose
`prove` loop runs only `t/openhap/integration/*.t`. So this phase also extends
`scripts/integration` to tar `t/fugulib/` into the VM and add it to the `prove`
run — the installed `site_perl` tree, refreshed by `vm-provision` on every run
and already on the include path at `scripts/integration:73`, provides
`FuguLib::*` — adds `t/fugulib/*.t` to `integration.yml`'s explicit path
includes, and updates `t/CLAUDE.md`'s tier table, which currently says the
module tier runs on the host only. Module-tier rules still apply inside the VM:
these files keep their skip-gracefully guards; on OpenBSD the guards simply
never fire.

### 3.2 Resolve the one genuinely late load

`prot_exec` stays out of the promise set. The earlier draft of this plan
justified that with a preload block covering "the XS runtime dependencies" and a
forced `Math::BigInt` modular exponentiation. **Both premises were wrong**, and
the block shrinks accordingly:

- Every XS dependency is already loaded by a compile-time `use` on the graph
  reachable from `bin/openhapd:7`: `Crypt::Curve25519`, `Crypt::Ed25519`,
  `Crypt::AuthEnc::ChaCha20Poly1305`, `Crypt::KeyDerivation` and `Digest::SHA`
  at `Crypto.pm:5-10`; `JSON::XS` at `HAP.pm:6`; `Digest::SHA` at `HAP.pm:8`.
  `Sys::Syslog` is loaded unconditionally at `FuguLib/Log.pm:22`. Nothing to
  preload.
- `Math::BigInt` resolves its backend inside `import`, not at first arithmetic,
  so `use Math::BigInt try => 'GMP'` at `SRP.pm:9` — reached at compile time via
  `HAP.pm:13` → `Pairing.pm:5` — has GMP's shared object open before
  `GetOptions` runs. A forced modexp would be dead code, and an acceptance
  criterion resting on it could not fail.

What remains is one `require` not settled at compile time: `Net::MQTT::Simple`
at `MQTT.pm:50`. It is **not** deferred by a down broker — the require completes
before the connect attempt (`MQTT.pm:57`) inside the same `eval`, and
`bin/openhapd:88` runs `mqtt_connect` unconditionally at startup — so an
installed module is in `%INC` pre-pledge in every scenario. The genuinely late
case is narrow: the module absent at startup and installed while the daemon
runs, when a later reconnect's require succeeds post-pledge. It is **pure
Perl**, so it needs no `prot_exec` — only `rpath` and a reachable library tree,
which phase 4's unveil provides and which that narrow case is the standing
reason for. Resolve it before the pledge anyway, so its own transitive
dependencies load while loading is unrestricted:

```perl
# Resolve the one module the daemon may load lazily, before the pledge and
# unveil restrict us.  Net::MQTT::Simple is pure Perl, so this is not
# about prot_exec -- it is about its transitive dependencies (sockets,
# and whatever getprotobyname touches) being resolved while @INC is
# still fully reachable.  It stays optional: it is the only cpan runtime
# dependency, and openhapd serves HomeKit without it.
eval { require Net::MQTT::Simple; 1 };
```

**Keep it non-fatal.** An unguarded `use`/`require` would make the absence of
the only `cpan` runtime dependency (`deps/OpenBSD.txt`) a startup failure, where
`bin/openhapd:88-97` currently logs "MQTT broker not available, will retry in
background" and keeps serving. That would violate `CLAUDE.md`'s "`require`
optional dependencies so they stay optional" and falsify this phase's own
byte-identical-behaviour criterion.

Comment it as above, because the next reader will otherwise delete it as a
redundant `require`. And note the standing rule: **if a future change introduces
a module that loads lazily, it belongs here.**

### 3.3 Apply the pledge in `bin/openhapd`

After the mDNS advertisement is established and before the signal handlers and
`$hap->run()`:

```
stdio rpath wpath cpath fattr flock inet dns unix
```

Derivation is in the design; the code carries a comment per promise so a future
reader can shrink the set safely. Also:

- **`unix` is conditional on phase 1's measurement 4.** It is needed only if
  `update_txt` reconnects to mdnsd. An already-connected socket needs just
  `stdio` to read and write — `PLEDGE_UNIX` gates `socket`, `connect` and
  `bind`, all of which happen before the pledge. If measurement 4 showed
  same-socket `GROUP_RESET` works and `FuguLib::MDNS` never reconnects, drop
  `unix` and say so in the comment. Do not carry a promise nothing exercises.
- Both `-f`/foreground and daemon mode pledge identically.
- `-n`/`--check` exits at `bin/openhapd:34-37`, before any of this. Leave it
  alone; a config check is not a long-running process.
- Log at info that the pledge was applied, naming the promise set — from
  `bin/openhapd`, not from `FuguLib::Sandbox`. On a no-op platform log nothing,
  so a reader of the log can tell the two apart. Tests use `is_supported`, not
  the log.

### 3.4 Documentation

- `man/fugulib/Sandbox.3p` is the API reference for the module (FuguLib is
  documented in man3p, not in sidecars). Document the ordered-pairs form, the
  required/optional distinction, the die-on-failure contract, and the lock
  semantics.
- `man/openhap/openhapd.8`: state the promise set and that OpenBSD is the only
  platform where it is enforced. The full SECURITY section lands in phase 5,
  once unveil is in place; here, one accurate paragraph.
- Do not touch the pledge/unveil truth-claims in `README.md`, `CLAUDE.md:7` and
  `:107-108`, or `web/index.body.html` — those become fully true at the end of
  phase 4, and hedging them for one phase then unhedging them is churn. The
  FuguLib module count and scope are different: they have a final true value at
  every phase, so this phase updates `web/fugulib.body.html` from eight to nine
  (adding the `Sandbox` entry) and extends `CLAUDE.md:13-14`'s scope line,
  exactly as phase 2 did for eight — and rewords the page's "no dependencies
  outside core Perl" clause to "no dependencies outside core Perl and the
  OpenBSD base system", which `Sandbox`'s use of
  `OpenBSD::Pledge`/`OpenBSD::Unveil` makes necessary: they are base-system
  additions to OpenBSD's perl, not core modules. Phase 5 verifies rather than
  fixes.

## Deliverables

- `lib/FuguLib/Sandbox.pm`, `man/fugulib/Sandbox.3p`, `Makefile` `MAN3P` entry
- `t/fugulib/sandbox.t`
- Changes to `bin/openhapd` (the lazy-load resolution, the pledge call)
- Changes to `scripts/integration` (ship and prove `t/fugulib/` in the VM),
  `.github/workflows/integration.yml` (path includes), `t/CLAUDE.md` (tier
  table)
- `man/openhap/openhapd.8` paragraph
- `web/fugulib.body.html` (nine modules, `Sandbox` entry, dependency clause) and
  the `CLAUDE.md:13-14` scope line
- Possibly `deps/OpenBSD.txt` + `cpanfile` (`p5-BSD-Resource`), if that is how
  the core dump gets suppressed

## Acceptance criteria

- On OpenBSD, `openhapd` starts, pairs, serves characteristics, publishes mDNS,
  and survives an MQTT broker restart — all under the pledge. The MQTT case
  matters most: reconnection is the one code path that resolves names after the
  pledge point (and, when the module was absent at startup, retries the
  `Net::MQTT::Simple` require), and it is the likeliest thing to abort in
  production rather than in a test.
- `openhapd` starts and serves with `Net::MQTT::Simple` **not installed**,
  exactly as it does today — the preload does not make it mandatory.
- `t/fugulib/sandbox.t` proves a pledge violation aborts a forked child on
  OpenBSD, asserting in the parent on the wait status, proves the disposition
  semantics (missing required dies, missing optional does not), and proves the
  no-op contract elsewhere. It leaves no core file behind.
- `make integration` runs `t/fugulib/sandbox.t` inside the VM, where its
  OpenBSD-only subtests execute rather than skip.
- `make check` green on Linux and Darwin with behaviour byte-identical to
  before.
- `kdump`/`ktrace` of a running `openhapd` shows no `pledge` violation and no
  `mmap` with `PROT_EXEC` after startup.
- `mandoc -Tlint -W warning` clean.
