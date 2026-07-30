# Phase 1 — The mDNS protocol reference and the measurements

Write the mdnsd control protocol into `spec/` before writing a line of client
code, teach the coverage tooling to see it, and take the measurements phase 2's
API depends on. Independently shippable: it adds a protocol reference, permanent
citation support for it, and a recorded set of measurements, with no behaviour
change.

This phase exists because phase 2 implements a wire protocol against another
daemon's in-memory struct layout. Deriving that from a header while writing the
client would bury the assumptions in Perl comments. Writing it down first puts
them in the one place this repo already trusts for protocol facts.

## Tasks

### 1.1 Read the upstream sources

The spec-generation and reference-fetching skills were removed in `2da2b57`, and
`external/` is gitignored and not required to exist. Clone what you need locally
and cite it; nothing in this phase depends on a fetcher skill or on a populated
`external/`:

```sh
git clone --depth 1 https://github.com/haesbaert/mdnsd external/openmdns
```

The sources that matter are `mdnsd/mdns.h` (the `imsg_type` enum, the structs,
the socket path), `mdnsd/control.c` (the server side of the group state machine
— `control_group_add`, `control_group_reset`, `control_group_add_service`,
`control_group_commit`, `control_notify_pg`, `pg_get`), `libmdns/mdnsl.c`
(client sequences and payload shapes) and `mdnsctl/` (what a real client sends).

`haesbaert/mdnsd` is upstream, but the OpenBSD `net/openmdns` port may carry
patches and **the installed port is authoritative for us**. `cynix/openmdns` is
a maintained fork; if the port tracks it, read that instead and say so in the
provenance. Base-system `imsg` framing is not in openmdns at all — the installed
`/usr/include/imsg.h` is its authority.

### 1.2 Take the measurements

Seven measurements, all inside the OpenBSD VM (`make integration`, or the
`openhvf` skill for an interactive shell). Items 1–5 are what the spec records;
items 2, 4 and 5 **gate phase 2's API** — phase 2 does not start until they are
settled — and item 7 gates phase 5's test design the same way.

1. **`struct mdns_service` ABI.** Compile a short C probe against the installed
   `/usr/local/include/mdns.h` printing `sizeof` and `offsetof` for every field.
2. **`imsg_hdr` layout**, from the installed `/usr/include/imsg.h`. Do not
   assume it: the 2024 imsg rework widened `len` to `uint32_t` and removed
   `flags`, so a release before and after that change have different headers.
   Record the field set, the widths, whether `len` includes the header,
   `MAX_IMSGSIZE`, and the maximum _payload_ that follows from it
   (`MAX_IMSGSIZE` bounds the whole message, so the payload bound is
   `MAX_IMSGSIZE - sizeof(imsg_hdr)`).
3. **A byte-exact publish conversation.** `ktrace -i mdnsctl publish ...` then
   `kdump`, capturing the `write(2)` payloads on the control socket. This
   settles what no header can: whether `app` carries `hap` or `_hap`
   (`mdnsctl/parser.c` may normalise what `MDNS.pm:93` passes as `hap`), what
   `mdnsctl` puts in `target`/`addr`, and what `priority`/`weight` default to.
   Note which bytes are sender-specific — the header carries the sender's pid —
   because those cannot be replayed literally by a different process.
4. **Whether same-socket TXT replacement works.** Send `GROUP_RESET` →
   `GROUP_ADD_SERVICE` → `GROUP_COMMIT` on a held connection and check whether
   the advertised TXT actually changes, by browsing from outside.
   `control_group_reset` looks its group up with `pg_get(0, msg, NULL)` while
   `control_group_add` created it with `pg_get(1, msg, c)`, and `pg_get` matches
   on `pg->c == c` — so on upstream the reset may never find a
   controller-created group, leaving it `PG_STA_COMMITED`, making
   `control_group_add_service` reject it (it requires `PG_STA_NEW`), and leaving
   `control_group_commit` to re-announce the **old** records while still
   replying PROBING/ANNOUNCING/PUBLISHED. A client would read that as success
   with a stale record. If the port fixed that lookup, check the other branch:
   `pg_kill` frees the group, so the following commit may reach
   `control_notify_pg(c, NULL, ...)` and dereference `pg->name`, killing mdnsd
   and mDNS for the whole host. **Do this measurement in the VM, never against a
   host you care about.** Whatever the outcome, record it — including
   "same-socket reset does not work, republish instead", which is what
   `MDNS.pm:176-183` does today.
5. **Whether the group name must equal the service instance name.**
   `control_group_add_service` appears to look the group up under the
   _service's_ name, and `libmdns` appears to enforce
   `strcmp(group, ms->name) != 0`. If so, `FuguLib::MDNS` must not expose them
   as independent parameters.
6. **The real path set**, for phase 4's unveil inventory: `ktrace -i` (the `-i`
   is load-bearing — without it the `mdnsctl` child's opens are missed entirely)
   a full pairing plus an MQTT broker restart, `kdump`, and list every path the
   daemon opens, **attributed per pid**. This is the only reliable way to catch
   resolver files (`/etc/hosts`, `/etc/resolv.conf`, `/etc/services`,
   `/etc/protocols`), `/etc/localtime`, and whatever `Net::MQTT::Simple` touches
   on reconnect. This daemon is two phases older than the one phase 4 restricts,
   so record two filters with the data or phase 4's additive consumption imports
   junk: mark the records that belong to the `mdnsctl` child (its exec,
   `mdnsctl.log`, its socket connect — phase 2 deletes all three, though
   `/var/run/mdnsd.sock` itself returns as the daemon's own optional row), and
   mark opens that precede the eventual unveil point (the config file at
   `bin/openhapd:32`, the log at `:42`, `getpwnam`'s passwd db at `:122`), which
   must not become inventory rows. Record the result by updating `plan-4.md`
   4.1's inventory in place, with provenance noted there — the VM run is the
   expensive part and this phase is already in the VM, but a path inventory is
   not a protocol fact and has no place in `spec/`. Phase 4 re-validates the set
   against the rewired daemon before locking the inventory.

7. **What the platform can observe about an applied pledge and unveil**, for
   phase 5's proof tests: as root, `ktrace` a trivial pledged-and-unveiled perl
   one-liner, then record exactly what `kdump` renders for the `pledge` and
   `unveil` calls — does the promise string appear, do unveil's path and
   permission arguments (expect the path as a NAMI record and the lock as an
   argument-less call), and under which trace points — and whether
   `ps -o pledge` exists on this release and what it prints (expect a decoded
   promise set, not the input string, with input order lost). Confirm too that a
   root-owned `ktrace` keeps tracing across the daemon's setuid privdrop. Phase
   5's trace assertions are designed against this answer, exactly as phase 2's
   API is designed against items 2, 4 and 5 — the earlier draft asserted
   "`kdump` prints the string" unmeasured, the one observability claim in a plan
   that gates every mdnsd claim on measurement. Record it by updating
   `plan-5.md` 5.1 in place.

Derived layout to check measurement 1 against (LP64; `MAXLABELLEN` 64,
`MAXPROTOLEN` 4, `MAXHOSTNAMELEN` 256, `MAXCHARSTR` = `MAXHOSTNAMELEN`):

| offset | field      | C type           | bytes |
| ------ | ---------- | ---------------- | ----- |
| 0      | `entry`    | `LIST_ENTRY`     | 16    |
| 16     | `app`      | `char[64]`       | 64    |
| 80     | `proto`    | `char[4]`        | 4     |
| 84     | `name`     | `char[256]`      | 256   |
| 340    | `target`   | `char[256]`      | 256   |
| 596    | `priority` | `u_int16_t`      | 2     |
| 598    | `weight`   | `u_int16_t`      | 2     |
| 600    | `port`     | `u_int16_t`      | 2     |
| 602    | `txt`      | `char[256]`      | 256   |
| 858    | (padding)  |                  | 2     |
| 860    | `addr`     | `struct in_addr` | 4     |

864 bytes total. The `LIST_ENTRY` is mdnsd's own list linkage, two pointers
wide, and goes on the wire as zeros. **If the measurement disagrees, the
measurement wins** and the table in the spec is the measured one — this table is
a cross-check, not a source. Note that the two-pointer `LIST_ENTRY` and the 864
total are LP64-specific; record the architecture measured on, because phase 2's
encoder derives its size from the spec.

### 1.3 Write the spec files

Three hand-authored files, per `spec/CLAUDE.md`. **Numbered `##`/`###` headings
throughout** — the inventory regex in `scripts/spec-coverage:81` matches only
`##` and `###` with a leading number, so a `####` heading cannot be cited and a
heading whose number is missing is invisible. Anything a conformance test needs
to cite must be `##` or `###`.

Every claim cites the upstream file and line it came from, as the surrounding
`spec/` files do. A provenance block near the top of `MDNS.md`, matching
`MQTT.md`'s: the upstream repository and commit read, the installed port version
(`pkg_info -I openmdns` — `-Q` queries the remote repository, not the installed
set), the OpenBSD release and architecture measured on, and the
`/usr/include/imsg.h` version. Measurements that a later edit does not redo
carry forward with their provenance intact — say so explicitly, so a reader
knows which numbers were re-measured and which were inherited.

- `spec/MDNS.md` — index and overview. Glossary (imsg, control socket, group,
  service, probing, announcing, collision), the publish flow end to end, links
  to the topic files, provenance. Unhyphenated, so `spec-coverage` treats it as
  an index and does not count its sections.
- `spec/MDNS-Imsg.md` — framing, **as measured in 1.2 item 2**. Header field
  layout and byte order, whether `len` counts the header, `MAX_IMSGSIZE` and the
  derived payload bound, partial reads and message boundaries, `peerid`/`pid`
  semantics (including that `pid` is sender-specific), and the fd-passing
  facility with an explicit note that we do not use it and why (it would need
  `sendfd`/`recvfd` in the pledge).
- `spec/MDNS-Control.md` — the control protocol. Socket path and permissions,
  the full `imsg_type` enum with ordinal values, the group publish sequence,
  reply and error semantics, the `struct mdns_service` ABI as measured with its
  architecture noted, TXT string encoding including the `.` delimiter and its
  no-escaping consequence, field length limits, and — from measurements 4 and 5
  — a section on TXT replacement and a section on the group/instance name
  relationship. Specify browse/resolve/lookup message shapes too: they share the
  enum and framing, cost a paragraph each, and stop the file from looking like
  it describes the whole protocol when it describes a third of it.

Include a byte-exact worked example of a full publish conversation from the 1.2
item 3 capture, with the sender-specific bytes marked as such. That example is
what phase 2's conformance test replays.

### 1.4 Teach the tooling about the new family

- `scripts/spec-coverage:109-110` — extend the citation pattern from
  `(?:HAP|MQTT)[A-Za-z0-9-]*` to include `MDNS`. Without this, `[MDNS-Imsg §2]`
  never matches: the citation is not counted, and — worse — is not stale-checked
  either, so it silently rots when the spec changes.
- `t/CLAUDE.md:70` documents that grep pattern; update it in lockstep. Do
  **not** document the topic ↔ test mapping yet: the conformance tests land in
  phase 2, and `t/CLAUDE.md` must not name files that do not exist. Phase 2 adds
  that mention (task 2.3).
- `spec/CLAUDE.md` — add the `MDNS.md` / `MDNS-*.md` bullet to the Purpose list.
  Do **not** name an owning skill: that file states these are hand-maintained
  documents edited in place, and there is no `spec-mdns` skill. That file also
  states that adding a topic file means adding its conformance test, which this
  phase deliberately does not do: note the exception beside the new bullet — the
  MDNS topic files' conformance tests land with the mDNS client implementation —
  worded without plan numbering so it reads standalone. Phase 2 removes the note
  when it closes the gap (task 2.3).

No `Makefile` change: `spec-coverage` globs `spec/*.md` and picks the new files
up on its own.

### 1.5 Cover the new regex branch permanently

`t/scripts/spec-coverage.t` already drives the script as a subprocess against a
fixture tree built in a `tempdir` and asserts coverage counts, `--quiet`,
`--uncovered`, and both `STALE` classes. Add an `MDNS-*` fixture stem to it, so
the new alternation in the citation regex is covered by `make check` from the
moment it lands.

Follow the existing convention exactly: the fixture stems are assembled at
runtime from split string literals (`my $STEM = 'HAP-' . 'Fixture8'`) precisely
so that `spec-coverage`, when run over the real `t/` tree, does not treat the
test's own source as a citation. An `MDNS-` fixture stem must be split the same
way or it will report itself as a stale citation against the real `spec/`.

This replaces the throwaway verification the earlier draft of this plan
prescribed — add a temporary citation, confirm it counts, add a bogus one,
confirm `STALE`, then delete both. That ritual does this file's job by hand and
then destroys the evidence, shipping the new branch with no permanent coverage;
`t/CLAUDE.md`'s tooling tier already mandates the subprocess-and-assert shape.

### 1.6 Verify the tooling sees the new files

`./scripts/spec-coverage`, run without `--quiet`, must list the two new topic
files — the `make spec-coverage` target passes `--quiet`, which suppresses every
per-file line and prints only the TOTAL, so it can decide the exit status but
not the listing. Coverage reads 0/N until phase 2 — that is correct and
non-fatal: `scripts/spec-coverage:200` is `exit(@stale ? 1 : 0)`, so low
coverage never fails the tool. That is what makes this phase shippable alone.

## Deliverables

- `spec/MDNS.md`, `spec/MDNS-Imsg.md`, `spec/MDNS-Control.md`
- Measurements 1–5 from 1.2, recorded in the spec files with provenance;
  measurement 6 recorded in `plan-4.md` 4.1 and measurement 7 in `plan-5.md`
  5.1, each with its provenance
- Changes to `scripts/spec-coverage`, `t/scripts/spec-coverage.t`,
  `t/CLAUDE.md`, `spec/CLAUDE.md`

## Acceptance criteria

- The `struct mdns_service` layout and the `imsg_hdr` layout in the spec are the
  measured ones, and the spec names the OpenBSD release, architecture and port
  version they were measured on.
- `spec/MDNS-Control.md` records what measurement 4 found about same-socket TXT
  replacement and what measurement 5 found about the group/instance name
  relationship, in numbered citable sections. Phase 2's API depends on both.
- `spec/MDNS-Control.md` contains a byte-exact publish conversation captured
  from a real `mdnsctl`, with sender-specific bytes marked, sufficient for phase
  2 to replay without re-deriving anything.
- The measured path set (measurement 6) is recorded in `plan-4.md` 4.1 with
  per-pid attribution and both staleness filters applied, and the observability
  answer (measurement 7) in `plan-5.md` 5.1 — each where its consuming phase
  reads it.
- Every section a conformance test will cite is a numbered `##` or `###`
  heading.
- `./scripts/spec-coverage` (no `--quiet`) lists both topic files and reports 0
  covered sections for them; `make spec-coverage` exits zero.
- `t/scripts/spec-coverage.t` covers the `MDNS` citation branch and passes; the
  fixture stem is split so it does not self-match.
- `make check` green. This phase **does** change Perl that `make check` gates:
  `PERLSRC` (`Makefile:36`) globs `lib bin scripts` for `*.pm` or a perl
  shebang, and `scripts/spec-coverage` begins `#!/usr/bin/env perl`, so both
  `make lint` and `make tidy` cover it — expect perltidy to reflow the citation
  regex.
- `make prettier` clean.
