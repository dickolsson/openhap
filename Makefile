.PHONY: all build check clean clean-man deps format format-fix install install-man integration lint man package provision test uninstall vm-up

# Configuration
BUILD			?= $(shell git rev-list --count HEAD)
TAG				?= b$(BUILD)
PREFIX			?= /usr/local
BINDIR			?= $(PREFIX)/bin
LIBDIR			?= $(PREFIX)/libdata/perl5/site_perl
SHAREDIR		?= $(PREFIX)/share
MANDIR			?= $(PREFIX)/man
SYSCONFDIR		?= /etc
LOCALSTATEDIR	?= /var

# Build tools
PERLTIDY		= perl -MPerl::Tidy -e 'Perl::Tidy::perltidy()'
MANDOC			?= mandoc

# Man pages
MAN5			= man/openhap/openhapd.conf.5
MAN8			= man/openhap/openhapd.8 man/openhap/hapctl.8
CATMAN5			= $(MAN5:.5=.cat5)
CATMAN8			= $(MAN8:.8=.cat8)

all: deps check

build: package

check: format lint test

clean: clean-man
	rm -rf build
	rm -f *.tmp

clean-man:
	rm -f $(CATMAN5) $(CATMAN8)

deps:
	cpanm --notest --installdeps .

format:
	@find lib bin -name '*.pm' -o -name 'openhapd' -o -name 'hapctl' | while read f; do \
		$(PERLTIDY) -- --standard-output "$$f" | diff -q "$$f" - >/dev/null 2>&1 || echo "$$f"; \
	done | grep . && echo "Run 'make format-fix' to fix formatting" && exit 1 || echo "All files formatted correctly"

format-fix:
	@find lib bin -name '*.pm' -o -name 'openhapd' -o -name 'hapctl' | while read f; do \
		$(PERLTIDY) -- -b -bext='/' "$$f"; \
	done

install: install-man
	# Install binaries
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 bin/openhapd $(DESTDIR)$(BINDIR)/openhapd
	install -m 755 bin/hapctl $(DESTDIR)$(BINDIR)/hapctl
	# Install Perl libraries
	install -d $(DESTDIR)$(LIBDIR)/OpenHAP
	install -d $(DESTDIR)$(LIBDIR)/OpenHAP/Tasmota
	install -m 644 lib/OpenHAP/*.pm $(DESTDIR)$(LIBDIR)/OpenHAP/
	install -m 644 lib/OpenHAP/*.pod $(DESTDIR)$(LIBDIR)/OpenHAP/
	install -m 644 lib/OpenHAP/Tasmota/*.pm $(DESTDIR)$(LIBDIR)/OpenHAP/Tasmota/
	install -m 644 lib/OpenHAP/Tasmota/*.pod $(DESTDIR)$(LIBDIR)/OpenHAP/Tasmota/
	# Install rc.d script
	install -d $(DESTDIR)$(SYSCONFDIR)/rc.d
	install -m 755 etc/rc.d/openhapd $(DESTDIR)$(SYSCONFDIR)/rc.d/openhapd
	# Install example configuration
	install -d $(DESTDIR)$(SYSCONFDIR)/examples
	install -m 644 share/openhap/examples/openhapd.conf.sample $(DESTDIR)$(SYSCONFDIR)/examples/openhapd.conf
	# Create data directory
	install -d -m 700 $(DESTDIR)$(LOCALSTATEDIR)/db/openhapd

install-man:
	# Install man pages
	install -d $(DESTDIR)$(MANDIR)/man5
	install -d $(DESTDIR)$(MANDIR)/man8
	install -m 644 $(MAN5) $(DESTDIR)$(MANDIR)/man5/
	install -m 644 $(MAN8) $(DESTDIR)$(MANDIR)/man8/

integration: provision
	@./scripts/integration.sh

lint:
	perl -MPerl::Critic::Command -e 'Perl::Critic::Command::run()' -- --severity 4 --verbose 8 lib/ bin/openhapd bin/hapctl

man: $(CATMAN5) $(CATMAN8)

%.cat5: %.5
	$(MANDOC) -Tascii $< > $@

%.cat8: %.8
	$(MANDOC) -Tascii $< > $@

package: clean
	mkdir -p build/openhap-$(TAG)/bin
	mkdir -p build/openhap-$(TAG)/lib/OpenHAP/Tasmota
	mkdir -p build/openhap-$(TAG)/etc/rc.d
	mkdir -p build/openhap-$(TAG)/share/openhap/examples
	mkdir -p build/openhap-$(TAG)/man/openhap
	# Binaries
	cp bin/openhapd bin/hapctl build/openhap-$(TAG)/bin/
	# Perl libraries
	cp lib/OpenHAP/*.pm lib/OpenHAP/*.pod build/openhap-$(TAG)/lib/OpenHAP/
	cp lib/OpenHAP/Tasmota/*.pm lib/OpenHAP/Tasmota/*.pod build/openhap-$(TAG)/lib/OpenHAP/Tasmota/
	# rc.d script
	cp etc/rc.d/openhapd build/openhap-$(TAG)/etc/rc.d/
	# Example configuration
	cp share/openhap/examples/openhapd.conf.sample build/openhap-$(TAG)/share/openhap/examples/
	# Man pages
	cp $(MAN5) $(MAN8) build/openhap-$(TAG)/man/openhap/
	# Makefile and cpanfile for installation
	cp Makefile cpanfile build/openhap-$(TAG)/
	# Documentation
	cp README.md INSTALL.md LICENSE build/openhap-$(TAG)/
	cd build && tar -czvf openhap-$(TAG).tar.gz openhap-$(TAG)
	rm -rf build/openhap-$(TAG)

provision: vm-up
	@./scripts/provision.sh

test:
	prove -l -v t/openhvf/*.t
	prove -l -v t/openhap/*.t

uninstall:
	# Remove binaries
	rm -f $(DESTDIR)$(BINDIR)/openhapd
	rm -f $(DESTDIR)$(BINDIR)/hapctl
	# Remove Perl libraries
	rm -rf $(DESTDIR)$(LIBDIR)/OpenHAP
	# Remove man pages
	rm -f $(DESTDIR)$(MANDIR)/man5/openhapd.conf.5
	rm -f $(DESTDIR)$(MANDIR)/man8/openhapd.8
	rm -f $(DESTDIR)$(MANDIR)/man8/hapctl.8
	# Remove rc.d script
	rm -f $(DESTDIR)$(SYSCONFDIR)/rc.d/openhapd
	# Remove example configuration
	rm -f $(DESTDIR)$(SYSCONFDIR)/examples/openhapd.conf
	# Note: /etc/openhapd.conf and /var/db/openhapd are preserved

vm-up:
	@./scripts/vm-up.sh
