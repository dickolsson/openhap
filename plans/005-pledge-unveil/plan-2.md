# Phase 2 — mDNS client without exec

Replace the `mdnsctl publish` child with a native client speaking imsg over
`/var/run/mdnsd.sock`, implemented against the phase 1 spec. This phase changes
no security posture on its own; it removes the only `exec` in the daemon, which
is what lets phase 3 pledge without `proc exec`. Independently shippable: it
deletes a child process, a log file, and a kill-on-shutdown path.

Depends on phase 1 for `spec/MDNS-Imsg.md` and `spec/MDNS-Control.md`, and
specifically on measurements 2, 4 and 5 from task 1.2 — the `imsg_hdr` layout,
whether same-socket TXT replacement works, and whether the group name must equal
the instance name. **Those three decide this phase's API. Do not start until
they are recorded in the spec.**

## Tasks

### 2.1 `FuguLib::Imsg`

Framing only, no mdnsd knowledge:

- `new(fh => $fh)` over an already-connected handle, so tests can use a
  `socketpair` and the module never opens anything itself.
- `send(type => $n, data => $bytes)` — header **as recorded in
  `spec/MDNS-Imsg.md`** from the installed `/usr/include/imsg.h`, followed by
  payload. Do not hardcode a layout from this plan: the field set changed in the
  2024 imsg rework (`len` widened to `uint32_t`, `flags` removed), so a
  plan-time guess would be wrong on one side of that change. Pin the field
  widths and order as named constants in one place, with a comment citing the
  spec section.
- Refuse payloads that exceed the **payload** bound rather than truncating.
  `MAX_IMSGSIZE` bounds the whole message, so the bound is
  `MAX_IMSGSIZE - sizeof(imsg_hdr)`, not `MAX_IMSGSIZE`.
- `recv(timeout => $seconds)` — buffered, returns `{ type, data }` for one whole
  message, `undef` on timeout or clean EOF; short reads accumulate across calls.
  `IO::Select` for the timeout, never `alarm`.
- **`$SIG{PIPE}`.** Writing to a socket the peer has closed raises SIGPIPE,
  which Perl does not ignore by default and `IO::Socket::UNIX` does not
  suppress. `send` must localise `$SIG{PIPE} = 'IGNORE'` and return `undef` with
  `$!` set to `EPIPE`, or a peer that closes mid-conversation kills the whole
  process — which is exactly what the EOF test in 2.2 exercises.
- A private encoder seam. The conformance test in 2.3 has to assert encoded
  bytes against a literal, and none of the public methods returns them, so
  expose the header encoder as a testable internal (`_encode_header`) rather
  than leaving the test to scrape a socketpair.
- No fd passing (`SCM_RIGHTS`): the mdnsd group protocol does not use it, and
  omitting it keeps `sendfd`/`recvfd` out of the promise set.

**No logging.** No module under `lib/FuguLib/` references a logger, and the
convention is that the caller decides — `Privdrop` dies, `Process` reports
through `on_error`/`on_success` callbacks. Return outcomes; let `bin/openhapd`
log. Reaching for `$OpenHAP::logger` from `lib/FuguLib/` would contradict the
namespace split in `CLAUDE.md` and would die in `t/fugulib/*.t`, which sets no
OpenHAP globals.

Ships with `man/fugulib/Imsg.3p`, a `MAN3P` entry in the `Makefile`, and
`t/fugulib/imsg.t`. The module test is platform-independent — round-trip over a
`socketpair`, an oversized payload rejection, a truncated-header read, a
two-messages-in-one-read case, and a write-after-peer-close returning `undef`
rather than dying. Byte-exact header assertions belong in the conformance test
(2.3), not here.

The man page documents the API. It does not restate the framing — that is
`spec/MDNS-Imsg.md`'s job — and points there instead.

### 2.2 `FuguLib::MDNS`

The mdnsd group protocol, OpenHAP-agnostic:

- Constants for the `imsg_type` enum values used here. The enum is positional,
  so pin all of `IMSG_NONE`(0) through `IMSG_CTL_GROUP_PUBLISHED`(17) in order,
  taken from `spec/MDNS-Control.md` rather than re-read from the header, with a
  comment citing the section.
- `new(socket_path => ...)` defaulting to `/var/run/mdnsd.sock`. **No separate
  `group` parameter** if measurement 5 confirmed that mdnsd looks the group up
  under the service's name and `libmdns` enforces `group == name`: in that case
  the group name is derived from the instance name inside `publish_service`, and
  the unusable combination is simply not expressible. If measurement 5 refuted
  it, keep `group` and say so.
- `connect()` — `IO::Socket::UNIX` `SOCK_STREAM`; returns `undef` when the
  socket is missing or unreachable, matching how `MDNS.pm:70` treats a missing
  `mdnsctl` today. The caller logs.
- `publish_service(name =>, app =>, proto =>, port =>, txt =>, timeout =>)` —
  `GROUP_ADD`, `GROUP_ADD_SERVICE`, `GROUP_COMMIT`, then read replies until
  `GROUP_PUBLISHED`, an error type, or timeout. `GROUP_PROBING` and
  `GROUP_ANNOUNCING` are not terminal. `timeout` defaults to 2s but **must be a
  parameter**: with it hardcoded, the timeout subtest is an unavoidable 2-second
  wall-clock wait in every `make check` run and cannot be made resilient to
  timing variation as `CLAUDE.md` requires.
- `txt` is a **formatted string**, already `key=value` pairs joined per the
  encoding section of `spec/MDNS-Control.md`. `FuguLib::MDNS` does not know what
  a TXT key means. See 2.4 for where the formatting lives.
- `update_txt(txt => ...)` — mechanism **per measurement 4**. If same-socket
  `GROUP_RESET` → `GROUP_ADD_SERVICE` → `GROUP_COMMIT` was shown to work, do
  that. If it was shown to re-announce the stale record or to crash mdnsd — the
  likely outcome from reading `control_group_reset`'s `pg_get(0, msg, NULL)`
  lookup — then `update_txt` closes and republishes, which is what
  `MDNS.pm:177-185` does today and what `control_close` cleans up correctly.
  Retain `name`/`app`/`proto`/`port` from `publish_service` so `update_txt` can
  re-send `GROUP_ADD_SERVICE` without them being passed again. Whichever path is
  taken, comment it with the spec citation, because the wrong one fails
  silently.
- `withdraw()` — close the socket; that is the entire operation.
- `is_published()` — used by `OpenHAP::HAP` to avoid driving updates onto an
  unpublished handle (2.4).
- Group-name and instance-name inputs longer than the field are an error, not a
  silent truncation.
- The `struct mdns_service` field offsets and size come from the spec, as named
  constants in one place, so an openmdns change is a one-line edit next to a
  citation. Include the architecture the layout was measured on in that comment
  — the `LIST_ENTRY` width and the 864-byte total are LP64-specific.
- On an OpenBSD host whose architecture does not match the ABI the spec was
  measured on (non-LP64), `publish_service` refuses and returns `undef` rather
  than encoding garbage for a differently-laid-out mdnsd — the caller logs and
  HAP keeps serving, the usual `FuguLib::MDNS` failure contract.
- No logging, for the reasons in 2.1.

Ships with `man/fugulib/MDNS.3p`, a `MAN3P` entry, and `t/fugulib/mdns.t`. The
module test stands up a temporary `AF_UNIX` listener as a fake mdnsd and drives
the reply paths — `PUBLISHED`, `ERR_COLLISION`, `ERR_DOUBLE_ADD`, EOF
mid-conversation, a short reply timeout, and an over-length name — on Linux and
Darwin unchanged, which is where CI exercises it. The EOF case depends on 2.1's
`$SIG{PIPE}` handling and the timeout case on the `timeout` parameter; neither
is testable without them.

### 2.3 Conformance tests

Per `t/CLAUDE.md`, one `.t` per normative topic file, named after the lowercased
stem: `t/conformance/mdns-imsg.t` and `t/conformance/mdns-control.t`. This is
the tier that closes the loop opened in phase 1 — the spec records what the
protocol is, these assert our encoder produces it.

Both follow the conformance rules: every subtest name starts with a citation,
wire examples are replayed byte-exactly, vectors live inline with no network and
no `external/`, `Test::More` + `subtest`, `skip_all` on missing CPAN
dependencies.

- `mdns-imsg.t` — header encoding field by field against `[MDNS-Imsg §…]`, via
  2.1's `_encode_header` seam: field widths and order as measured, whether `len`
  counts the header, the payload-bound refusal, and message-boundary handling on
  a split read. Do not assert "byte order" against a little-endian capture while
  the encoder uses native-endian `pack` — that assertion is tautological on
  every host this repo runs on and protects nothing. Assert the field _layout_,
  which is what can actually be wrong.
- `mdns-control.t` — the `imsg_type` ordinals; `struct mdns_service` encoded
  byte-exactly, including the zeroed `LIST_ENTRY`, the internal padding, and NUL
  padding of each fixed field; TXT `.` joining; the reply/error type meanings;
  and the publish conversation from the spec's worked example.

Two constraints on "byte-exact" that the spec's worked example must respect:

- **The header carries the sender's pid.** The captured conversation holds
  `mdnsctl`'s pid; our encoder writes the test process's. Assert the
  sender-specific bytes are _well-formed_ (the pid field equals `$$`) and the
  rest byte-for-byte, and say so in the subtest name. Claiming a literal
  whole-message match would be a criterion no implementation can meet.
- **Assert the whole `struct mdns_service` buffer against a literal**, not field
  by field — a field-by-field check passes even when the total size or padding
  is wrong. This is the assertion that matters most: it is the only thing
  standing between an openmdns layout change and a daemon that silently
  advertises garbage. No architecture guard: the encoder is built from fixed
  spec constants (2.2), so it emits identical bytes on every host and this test
  passes or fails identically everywhere — a skip would have nothing to prevent.
  The real non-LP64 risk is the _module_ speaking the measured LP64 ABI to a
  differently-laid-out mdnsd, and that is handled where it lives: the spec names
  the measured architecture (1.3) and `FuguLib::MDNS` refuses to publish on a
  non-LP64 OpenBSD host (2.2).

Also update `t/CLAUDE.md`'s conformance section with the new topic ↔ test
mapping, and remove the temporary exception note phase 1 left in
`spec/CLAUDE.md` — this task closes the gap it described.

`./scripts/spec-coverage` (no `--quiet`; the `make` target suppresses per-file
lines) should now report real coverage for both topic files where it reported 0
in phase 1.

### 2.4 Rewire `openhapd`, move the TXT formatting, and delete `OpenHAP::MDNS`

- **Move the TXT formatting into `OpenHAP::HAP`.** `plan-2`'s earlier draft
  claimed this knowledge "already lives in `HAP::get_mdns_txt_records`". It does
  not: `HAP.pm:1085-1106` returns a bare hashref, and the `key=value` formatting
  _and_ the deterministic `sort keys` ordering live at `MDNS.pm:85-87`, inside
  the module being deleted. Add a method beside `get_mdns_txt_records` that
  returns the formatted string, and keep the ordering deterministic — mdnsd's
  TXT delimiter makes ordering observable, and `t/openhap/mdns.t:239` tests it
  today. That test's successor lives in `t/openhap/hap.t`.
- `bin/openhapd`: replace the `OpenHAP::MDNS->new(...)` construction
  (`:108-112`) with `FuguLib::MDNS`, and `register_service` (`:157`) with
  `connect` + `publish_service`, passing `hap`/`tcp` and the formatted TXT
  string from the call site. Log the outcome here — the module does not.
- **`OpenHAP::HAP` must guard on `is_published`.** `set_mdns` keeps its
  signature, but `$hap->set_mdns($mdns)` runs at `bin/openhapd:113`, long before
  the connect, and `HAP::_refresh_mdns` (`HAP.pm:138-153`) guards only on
  `defined $self->{mdns}` before calling the update at `:148`. Today that is
  safe _only_ because `OpenHAP::MDNS::update_txt_records` short-circuits with
  `return 1 unless $self->{registered}` (`MDNS.pm:181`) — a guard inside the
  deleted module. Without a replacement, a daemon that started with `mdnsd` down
  writes to a closed handle the first time a user pairs. Add the `is_published`
  check in `_refresh_mdns`, and make `update_txt` a no-op when unpublished as
  well: two guards, because this one kills the daemon at pairing time. (Note:
  there is no `HAP::update_txt_records` sub — `HAP.pm:148` is a _call_ into the
  mdns object from `HAP::_refresh_mdns`.)
- The shutdown cleanup (`bin/openhapd:166-176`) calls `withdraw` instead of
  `unregister_service`.
- Remove the `$db_path/mdnsctl.log` machinery and the now-unused `log_dir`
  plumbing. Check whether `FuguLib::Process` retains any other caller; if
  `spawn_command`/`terminate` become dead code, say so in the commit message and
  leave removal to a separate change — `FuguLib` is a library and its API is not
  ours to prune on the way past.

### 2.5 The full consumer inventory

This phase breaks six other files — five by deleting `lib/OpenHAP/MDNS.pm` and
`.pod`, a sixth by 2.4's own rewiring of `_refresh_mdns`, which is why a grep
for the module name does not find it. Every one needs a disposition **in this
phase**, or neither `make check` nor `make integration` can be green as the
acceptance criteria require:

| file                                   | disposition                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `t/openhap/mdns.t`                     | Delete. Move the TXT-ordering coverage (`:239`) to `t/openhap/hap.t` against the new formatter.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `t/conformance/hap-mdns.t`             | **Rewrite, do not delete.** `:23` does `use_ok('OpenHAP::MDNS')` and `:37`, `:94`, `:181`, `:190` construct it. Re-point those four subtests at `OpenHAP::HAP`'s TXT formatter and the `FuguLib::MDNS` call arguments. See the note below.                                                                                                                                                                                                                                                                                                                                                                                                        |
| `t/openhap/integration/mdns-cleanup.t` | **Rewrite or delete — its premise is inverted.** `:32` asserts `mdnsctl_count > 0` and `:37` asserts captured mdnsctl PIDs. Integration tests never skip, so this fails deterministically after this phase. Fold whatever survives into the new assertions in 2.7.                                                                                                                                                                                                                                                                                                                                                                                |
| `t/openhap/hap.t`                      | **Rewrite the `MockMDNS` package** — broken by 2.4's rewiring, not the deletion: `_refresh_mdns` gains an `is_published` guard the mock lacks (the first state-changing refresh dies with "Can't locate object method"), and `update_txt_records($hashref)` becomes `update_txt(txt => $string)`. Give the mock the `FuguLib::MDNS` surface — `is_published` toggleable and returning true so updates flow, `update_txt` taking the formatted string — assert on string content (`sf=0`/`sf=1`), keep the `[HAP-mDNS §8]` citations on the rewritten assertions, and add an `is_published`-false case: the natural unit test for 2.4's new guard. |
| `t/openhap/integration/mdns.t`         | `:19-22` dies unless the `mdnsctl` _binary_ exists. Change the precondition to `mdnsd` running; `mdnsctl` is now only a test tool for browsing.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `scripts/integration`                  | Still `pkill`s `mdnsctl` as pre-run cleanup (`:41-49`) and greps for it in failure diagnostics (`:98`). Both become dead; remove them.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |

`t/conformance/hap-mdns.t` deserves care beyond "make it compile":
**`[HAP-mDNS §10]` is cited nowhere else in the tree** — only at
`t/conformance/hap-mdns.t:89`, inside one of the four subtests that constructs
the deleted module. `[HAP-mDNS §4]` and `[HAP-mDNS §6]` are likewise cited there
and otherwise only in `t/openhap/integration/mdns.t`, which moves them out of
`make check` and into the VM. So a careless rewrite silently lowers HAP-mDNS
coverage, and phase 5's "coverage no lower than phase 2 left it" would then
measure against an already-regressed baseline. **Record HAP-mDNS coverage before
and after this phase and keep it equal.** At this plan's revision the baseline
is `spec/HAP-mDNS.md` 17/20 sections cited (TOTAL 153/171), with
`[HAP-mDNS §10]` held solely by `t/conformance/hap-mdns.t:89`; re-measure at
phase start with `./scripts/spec-coverage` — without `--quiet`, which hides the
per-file lines — in case the tree has moved.

### 2.6 Ordering, privileges, and documentation

- Keep the current ordering — privdrop, then advertise — and update the stale
  comment at `bin/openhapd:115-117`, which explains it in terms of killing a
  child process.
- **Do not assert the wheel privilege model without measuring it.** The comment
  at `:116` says `_openhap` must be in `wheel` to reach `/var/run/mdnsd.sock`
  (root:wheel 0660). That claim is doubly unverified.
  `FuguLib::Privdrop::drop_privileges` calls only `POSIX::setgid`/`setuid` and
  never `setgroups`/`initgroups` — and a single-value `$) = $gid` assignment
  (`Privdrop.pm:73`) does not invoke `setgroups` either: perlvar passes only the
  numbers _after_ the first to `setgroups()`. So the drop leaves supplementary
  groups untouched — a root-started daemon _retains_ whatever its parent had,
  typically including wheel (gid 0), and `_openhap`'s `/etc/group` membership
  never reaches the daemon's credentials at all. That retained-groups mechanism
  is exactly what `man/fugulib/Privdrop.3p` CAVEATS already documents for
  reaching the mdnsd socket. Measure rather than argue, with an instrument that
  can see process credentials — `id` cannot; it would only echo the `/etc/group`
  database that `INSTALL.md:31` pre-seeds. A probe started the same way the
  daemon is (rc at boot inherits differently from a `doas` shell) performs the
  same `drop_privileges` call as root, prints `$)` after the drop (its trailing
  numbers are the live `getgroups` list; core `POSIX` exposes no `getgroups()`),
  then makes the `unveil`-free connect attempt. Write down what is true, and
  disposition the two operator-facing restatements of the wheel model in the
  same change: `INSTALL.md:31` (`usermod -G wheel _openhap`, rendered to the
  public site) and `scripts/vm-provision:169-171`, which seeds the same
  membership into the VM — where it can keep integration green for the wrong
  reason. Update or delete both per the measurement. The companion comment at
  `bin/openhapd:156` carries the same claim and disappears with the `mdnsctl`
  spawn it annotates — do not leave it half-corrected. Phase 5 documents the
  result in `openhapd.8`, so a false claim here becomes a false claim about a
  privilege boundary in an installed man page.
- `man/openhap/openhapd.8`: the daemon no longer spawns a child and needs
  `mdnsd(8)` running rather than `mdnsctl(8)` installed. Add `mdnsd(8)` to SEE
  ALSO, state that registration is a held control-socket connection with no
  child process, and tighten the existing CAVEATS wording: it already says a
  running mDNS daemon is required, so the requirement itself is not new, but
  after this phase the dependency is specifically openmdns's `mdnsd` and its
  control protocol, not any substitutable mDNS daemon. Neither this page nor
  `.claude/skills/openhapd/SKILL.md` mentions `mdnsctl` or `mdnsctl.log`, so
  there is no stale child-process text to fix.
- Two FuguLib documents narrate the pattern this phase deletes; rewrite both
  alongside the stale comment above. The usage example at
  `lib/FuguLib/Privdrop.pm:38` says
  `$mdns->register_service();  # Forks mdnsctl as root` — wrong today
  (registration runs after the drop, `bin/openhapd:157`) and doubly wrong after
  this phase — and while in that file, fix the comments at `Privdrop.pm:72-73`,
  which gloss `$(` and `$)` backwards (`$(` is the real gid, `$)` the
  effective). The EXAMPLES section of `man/fugulib/Process.3p` spawns
  `mdnsctl publish`; the API it demonstrates is unchanged, so re-point the
  example at a neutral long-lived command rather than enshrining the pattern
  this plan exists to remove. Leave `Privdrop.3p`'s CAVEATS alone — it concerns
  groups, not the child, and is the subject of the measurement above.
- The FuguLib module count and scope change in this phase, and the documentation
  changes with the fact, not in phase 5: `web/fugulib.body.html:8` goes from
  "Six modules" to eight, with `Imsg` and `MDNS` added to the `<dl>` and the
  page's intro enumeration extended to match; `CLAUDE.md:13-14`'s FuguLib scope
  line gains the mdnsd client and imsg framing; and `CLAUDE.md:45`'s
  `lib/OpenHAP/` layout enumeration drops `MDNS.pm`, which this phase deletes.
  `web.yml` deploys the site on any `man/**.3p` push, so shipping this phase
  without the count fix publishes a manuals index listing eight FuguLib pages
  beside a body claiming six.
- `deps/OpenBSD.txt` keeps `openmdns` — the daemon is still required; only the
  CLI is no longer invoked by `openhapd`. It remains a test dependency for
  browsing.
- `.github/workflows/`: the workflows filter on explicit path includes
  (`81baa1b`). Confirm `lib/FuguLib/**`, `t/fugulib/**`, `t/conformance/**` and
  `spec/**` are covered, or the new tests silently never run in CI.

### 2.7 Integration coverage

Extend `t/openhap/integration/` (which never skips — see
`t/openhap/integration/CLAUDE.md`) to assert, inside the VM:

- `mdnsctl browse hap tcp` sees the advertised service after `openhapd` starts —
  bare app and proto words, the syntax the existing test already uses at
  `t/openhap/integration/mdns.t:40`; `_hap._tcp` is dns-sd syntax and means
  nothing to `mdnsctl`. TXT assertions use the resolving form,
  `mdnsctl browse -r hap tcp`, as `browse_txt()` does today (`mdns.t:88-91`).
- No child process at all. Not via `pgrep -P $(pgrep openhapd)`: the daemon's
  p_comm is `perl` (shebang exec), so bare `pgrep openhapd` matches nothing, the
  outer `pgrep -P` errors with empty output, and the check passes
  unconditionally — the tree already knows this, matching the daemon with
  `pexp="perl ${daemon}.*"` in `etc/rc.d/openhapd` and `pkill -f` in
  `scripts/integration`. Instead: resolve
  `pid=$(pgrep -f 'perl.*/bin/openhapd')`, assert **exactly one** pid was found
  — the guard that keeps the test non-vacuous and catches over-matching — then
  assert `pgrep -P $pid` prints nothing and exits 1. Also assert no
  `mdnsctl.log` is created.
- The TXT record changes after a pairing state change (`sf` flips). This is the
  assertion that catches a broken `update_txt` — and given measurement 4, it is
  the most important test in this phase, because the failure mode is a _silent_
  stale record with a successful-looking reply sequence. Assert the browsed TXT,
  never the return value.
- The advertisement disappears within a few seconds of `openhapd` exiting, which
  is the socket-close contract.
- The daemon starts and serves with `mdnsd` stopped, logging a warning.

Assert on observable behaviour, not on log contents —
`t/openhap/integration/CLAUDE.md` forbids parsing logs.

## Deliverables

- `lib/FuguLib/Imsg.pm`, `lib/FuguLib/MDNS.pm`
- `man/fugulib/Imsg.3p`, `man/fugulib/MDNS.3p`, `Makefile` `MAN3P` entries
- `t/fugulib/imsg.t`, `t/fugulib/mdns.t`
- `t/conformance/mdns-imsg.t`, `t/conformance/mdns-control.t`
- A TXT formatter on `OpenHAP::HAP` plus its test in `t/openhap/hap.t`
- Rewritten `t/conformance/hap-mdns.t` and the `MockMDNS` package in
  `t/openhap/hap.t`; rewritten or deleted
  `t/openhap/integration/mdns-cleanup.t`; changed
  `t/openhap/integration/mdns.t`, `scripts/integration`
- New integration assertions in `t/openhap/integration/`
- Changes to `bin/openhapd`, `lib/OpenHAP/HAP.pm`, `man/openhap/openhapd.8`
- Changes to `lib/FuguLib/Privdrop.pm` (usage example, `$(`/`$)` comments),
  `man/fugulib/Process.3p` (EXAMPLES), `INSTALL.md` and `scripts/vm-provision`
  (wheel-model disposition per the 2.6 measurement), `web/fugulib.body.html`
  (eight modules), `CLAUDE.md` (FuguLib scope line, `lib/OpenHAP/` layout line),
  `t/CLAUDE.md` (topic ↔ test mapping), `spec/CLAUDE.md` (exception note
  removed)
- Deleted: `lib/OpenHAP/MDNS.pm`, `lib/OpenHAP/MDNS.pod`, `t/openhap/mdns.t`

## Acceptance criteria

- `t/conformance/mdns-control.t` asserts the whole encoded `struct mdns_service`
  against a literal; changing any offset constant makes it fail.
- `./scripts/spec-coverage` (no `--quiet`) reports non-zero coverage for
  `MDNS-Imsg` and `MDNS-Control`, and **HAP-mDNS coverage is unchanged from the
  baseline recorded in 2.5**; `make spec-coverage` exits zero.
- `mdnsctl browse` in the VM sees the service, the browsed TXT updates on a
  pairing state change, and the advertisement disappears when the daemon exits.
- `openhapd` spawns no child process at all: with the daemon's pid resolved by
  `pgrep -f` and asserted unique, `pgrep -P $pid` prints nothing and exits 1.
- A missing or unreachable `/var/run/mdnsd.sock` logs a warning and leaves the
  HAP server serving; pairing while unpublished does not kill the daemon.
- `make check` green on Linux (tests use `socketpair`/`AF_UNIX` and need no
  mdnsd); `make integration` green on OpenBSD — which requires every row of 2.5
  to have been carried out.
- `mandoc -Tlint -W warning` clean for both new man pages.
