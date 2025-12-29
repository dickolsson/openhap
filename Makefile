.PHONY: all build check clean clean-man deps format format-fix install install-man integration lint man package test uninstall upgrade vm-provision vm-up

# Filesystem configuration
PREFIX			?= /usr/local
BINDIR			?= $(PREFIX)/bin
LIBDIR			?= $(PREFIX)/libdata/perl5/site_perl
SHAREDIR		?= $(PREFIX)/share
MANDIR			?= $(PREFIX)/man
SYSCONFDIR		?= /etc
LOCALSTATEDIR		?= /var

# Build configuration
BUILD			?= $(shell git rev-list --count HEAD)
TAG			?= b$(BUILD)
PACKAGE			= openhap-$(TAG)
TARBALL			= $(PACKAGE).tar.gz

# GitHub configuration
GITHUB_OWNER		?= dickolsson
GITHUB_REPO		?= openhap
GITHUB_RELEASE		= https://github.com/$(GITHUB_OWNER)/$(GITHUB_REPO)/releases/download/$(TAG)/$(TARBALL)

# Build tools
FTP			= $(shell command -v curl >/dev/null 2>&1 && echo "curl -fLo" || echo "ftp -o")
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

integration: vm-provision
	@./scripts/integration.sh

lint:
	perl -MPerl::Critic::Command -e 'Perl::Critic::Command::run()' -- --severity 4 --verbose 8 lib/ bin/openhapd bin/hapctl

man: $(CATMAN5) $(CATMAN8)

%.cat5: %.5
	$(MANDOC) -Tascii $< > $@

%.cat8: %.8
	$(MANDOC) -Tascii $< > $@

package: clean
	mkdir -p build/$(PACKAGE)/bin
	mkdir -p build/$(PACKAGE)/lib/OpenHAP/Tasmota
	mkdir -p build/$(PACKAGE)/etc/rc.d
	mkdir -p build/$(PACKAGE)/share/openhap/examples
	mkdir -p build/$(PACKAGE)/man/openhap
	# Binaries
	cp bin/openhapd bin/hapctl build/$(PACKAGE)/bin/
	# Perl libraries
	cp lib/OpenHAP/*.pm lib/OpenHAP/*.pod build/$(PACKAGE)/lib/OpenHAP/
	cp lib/OpenHAP/Tasmota/*.pm lib/OpenHAP/Tasmota/*.pod build/$(PACKAGE)/lib/OpenHAP/Tasmota/
	# rc.d script
	cp etc/rc.d/openhapd build/$(PACKAGE)/etc/rc.d/
	# Example configuration
	cp share/openhap/examples/openhapd.conf.sample build/$(PACKAGE)/share/openhap/examples/
	# Man pages
	cp $(MAN5) $(MAN8) build/$(PACKAGE)/man/openhap/
	# Makefile and cpanfile for installation
	cp Makefile cpanfile build/$(PACKAGE)/
	# Documentation
	cp README.md INSTALL.md LICENSE build/$(PACKAGE)/
	cd build && tar -czvf $(TARBALL) $(PACKAGE)
	rm -rf build/$(PACKAGE)

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

upgrade:
	@echo "==> Downloading $(TARBALL)"
	$(FTP) ../$(TARBALL) $(GITHUB_RELEASE);
	cd .. && tar -xzf $(TARBALL)
	@echo "==> Upgrade by running:\n    make uninstall\n    cd ../$(PACKAGE)\n    make install"

vm-provision: vm-up
	@./scripts/vm-provision.sh

vm-up:
	@./scripts/vm-up.sh
