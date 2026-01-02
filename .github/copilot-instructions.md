# GitHub Copilot Instructions for OpenHAP

## Project Overview

OpenHAP is a Perl-based HomeKit Accessory Protocol (HAP) server for **OpenBSD**.
It bridges MQTT-connected Tasmota devices to Apple HomeKit using SRP-6a,
Ed25519, X25519, ChaCha20-Poly1305, HKDF-SHA-512, and TLV8 encoding over
encrypted HTTP/1.1 sessions.

**Core Principles:**

- **Correctness over features**: Handle all edge cases, return early on errors,
  avoid deep nesting
- **Security by default**: Use `/dev/urandom`, design for pledge(2)/unveil(2),
  fail closed, drop privileges early, never trust external input
- **Documentation**: Man pages (mdoc(7)) are authoritative, POD in separate
  `.pod` files, document all public methods
- **Configuration**: Simple syntax, sensible defaults,
  lowercase_with_underscores keys

**Module Organization:** Core protocol (HAP.pm, HTTP.pm, TLV.pm), Security
(Crypto.pm, SRP.pm, Pairing.pm, Session.pm), Data model (Accessory.pm,
Service.pm, Characteristic.pm, Bridge.pm), Configuration (Config.pm,
Storage.pm), Integration (MQTT.pm), Devices (Tasmota/\*.pm).

## Commit Messages

**Always follow the [Conventional Commits](https://www.conventionalcommits.org/)
standard** for all commit messages.

Format: `<type>[optional scope]: <description>`

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`,
`ci`, `chore`

Scopes (optional): Use module/component names like `hap`, `mqtt`, `crypto`,
`bridge`, `config`, `daemon`, `tasmota`, `vm`, etc.

Examples:

```
feat(mqtt): add support for retained messages
fix(crypto): correct ChaCha20-Poly1305 nonce handling
docs(readme): update installation instructions
refactor(bridge): simplify accessory registration
test(srp): add edge case tests for SRP-6a
chore(deps): update CryptX to 0.080
```

Indicate breaking changes with `!` or in the footer:

```
feat(hap)!: change default port to 51828

BREAKING CHANGE: The default port has changed from 51827 to 51828.
Update your configuration files accordingly.
```

**Before Committing:**

Always run `make check` before committing. This runs code tidying checks
(`make tidy`), linting (`make lint`), and tests (`make test`). All checks must
pass before code can be committed. Use `make tidy-fix` to automatically fix Perl
formatting issues if needed.

## Documentation

**Documentation must always be kept up-to-date** with any code changes.

The project has three primary documentation sources, each serving a distinct
purpose with **no overlap of information**:

1. **Man pages (`man/`)** — The main authoritative technical documentation
   - `openhapd.8` — Daemon operation, command-line options, signals
   - `hapctl.8` — Control utility usage and commands
   - `openhapd.conf.5` — Configuration file format and all options
   - Written in mdoc(7) format

2. **README.md** — High-level project introduction and quick start
   - What the project is and why it exists
   - Key features and capabilities
   - Quick start guide with minimal setup
   - Links to detailed documentation (man pages, INSTALL.md)

3. **INSTALL.md** — Complete installation and setup procedures
   - Prerequisites and dependencies
   - Step-by-step installation instructions
   - Platform-specific notes
   - Post-installation verification

**When making changes:**

- Update man pages when changing functionality, options, or configuration
- Update README.md when changing project scope, features, or quick start steps
- Update INSTALL.md when changing installation requirements or procedures
- Ensure no information is duplicated across these documents
- Use POD files (`.pod`) to document internal APIs and module interfaces

## Ad-hoc Testing in OpenBSD VM

For quick testing of changes in an actual OpenBSD environment:

1. Provision the code to the VM: `make vm-provision`
2. Run commands in the VM: `bin/openhvf ssh '<command>'`

Example workflow:

```sh
make vm-provision
bin/openhvf ssh 'rcctl restart openhapd'
bin/openhvf ssh 'tail -f /var/log/daemon'
```

## Full Integration Test Suite

Run the complete integration test suite (provisions VM, runs all tests):

```sh
make integration
```

This builds the package, provisions it to the VM, and runs all integration
tests.

## Coding Style

Always `use v5.36` (enables `strict`, `warnings`, `say`, signatures). Follow
OpenBSD style(9): 8-character tabs, continuation lines indent 4 spaces.

**Signatures and Methods:** Use object-oriented style with signatures. Packages
under `OpenHAP::`. Name object `$self`, prefix internal methods with `_`:

```perl
sub new($class, $state) { bless {state => $state}, $class; }
sub method($self, $p1, $p2) { ... }
sub _internal($self, $param) { ... }
```

Default values: `sub foo($self, $default = undef) { ... }` Variadic:
`sub wrapper($self, @p) { do_something(@p); }` Omit parentheses for zero-arg
calls: `$object->width` Explicit `return` except for no-return or constant
methods: `sub isFile($) { 1; }` Do not name unused parameters, document with
comments: `sub foo($, $) { }`

**Formatting:** Function brace on own line, control structure brace on same
line:

```perl
sub method($self, $param1, $param2)
{
	if ($condition) {
		...
	}
	return $result;
}
```

Anonymous subs: indent one tab, as arguments start on new line:

```perl
my $s = sub($self) { ... };
f($a, $b,
    sub($self) { ... });
```

**Data Structures:** Use autovivification: `push @{$self->{list}}, $value` Check
existence: `@{$self->{list}} > 0` No quotes on simple hash keys, omit arrows:
`$self->{a}{b}`

**Syntax:** Omit parentheses for built-ins and prototyped functions. Use modern
operators: `$value //= $something`

**Packages:** Multiple related classes per file allowed. No multiple
inheritance. Inheritance via `our @ISA`:

```perl
package OpenHAP::Derived;
our @ISA = qw(OpenHAP::Base);
```

Delegation passing `@_` unchanged (only case for code refs without signatures):

```perl
sub visit_notary { &Lender::visit_notary; }  # no parens
```

Constants via `constant` pragma:

```perl
use constant { DEFAULT_PORT => 51827 };
```

**Full Example:**

```perl
# ex:ts=8 sw=4:
# $OpenBSD$
#
# Copyright (c) YEAR Author <email@example.org>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

use v5.36;
package OpenHAP::Example;
use constant { DEFAULT_VALUE => 42 };

sub new($class, $state) { bless {state => $state}, $class; }
sub value($self) { return $self->{value} // DEFAULT_VALUE; }
sub set_value($self, $v) { $self->{value} = $v; return $self; }

sub process($self, $data, $options = undef)
{
	return if !defined $data;
	my $result = $self->_transform($data);
	$result = $self->_apply_options($result, $options) if defined $options;
	return $result;
}

sub _transform($self, $data) { ...; return $transformed; }
1;
```

## Dependencies and Error Handling

**Dependencies:** Use OpenBSD base packages: `pkg_add p5-*`. Minimize
dependencies, list in `cpanfile`. All crypto via `CryptX`, `Crypt::Ed25519`,
`Crypt::Curve25519`. Use `require` for conditional loading.

**Error Handling:** Return undef for recoverable errors, die for programming
errors. Use try/catch for cleanup:

```perl
use OpenHAP::Error;
try { ... } catch { ... };
```

Failable methods:

```perl
sub load_data($self, $file)
{
	open my $fh, '<', $file or do { warn "Cannot open $file: $!"; return; };
	# Process...
	return $data;
}
```

**Signal Handling:** Use object-based handlers that auto-restore:

```perl
my $handler = OpenHAP::SigHandler->new;
$handler->set('INT', 'TERM', sub($sig) { ... });
```

Register exit cleanup: `OpenHAP::Handler->atend(sub($) { ... });`

**Caching:** Lazy initialization:
`OpenHAP::Auto::cache(expensive_value, sub($self) { ... });` Call as
`$self->expensive_value` - computes once, caches.

## Testing

Structure tests with `use v5.36`, `use Test::More`, skip if dependencies
unavailable. Group related tests in blocks. Run via `make test`,
`prove -l -v t/openhap/`, or `prove -l t/openhap/foo.t`. Quality: `make lint`
(Perl::Critic severity 4).

```perl
#!/usr/bin/env perl
use v5.36;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
BEGIN { eval { require SomeModule }; plan skip_all => 'SomeModule not available' if $@; }
use_ok('OpenHAP::ModuleName');
{ my $obj = OpenHAP::ModuleName->new($state); ok(defined $obj, 'Created'); }
done_testing();
```

## Common Patterns

Reading `/dev/urandom`:

```perl
sub generate_random_bytes($length)
{
	open my $fh, '<', '/dev/urandom' or die "Cannot open /dev/urandom: $!";
	read $fh, (my $bytes), $length;
	close $fh;
	return $bytes;
}
```

File locking:

```perl
use Fcntl qw(:flock);
open my $fh, '+<', $file or return;
flock($fh, LOCK_EX) or return;
# ... work ...
close $fh;
```

Method chaining: `$object->configure->initialize->start`

Forking:

```perl
my $pid = fork;
if ($pid == 0) { $DB::inhibit_exit = 0; exec @command or exit 1; }
```

## What NOT to Do

- ❌ `eval` for flow control
- ❌ Ignore return values of system calls
- ❌ Regex when simple string operations suffice
- ❌ Features without tests
- ❌ Indirect object notation (`new Class` vs `Class->new`)
- ❌ Code that fails `make lint`
- ❌ Dependencies without justification
- ❌ Threads (use IO::Select for multiplexing)
- ❌ Code refs without parentheses (except delegation)
- ❌ Old-style function prototypes unless creating syntax
- ❌ `wantarray()` to change semantics (optimization only)
