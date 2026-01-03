# Finding Apple's HAP specification in AI-ready formats

The HomeKit Accessory Protocol specification exists in several AI-friendly
formats through community implementations, though Apple's official PDF requires
conversion. **The best sources for an AI coding agent are HAP-python's JSON
files and HAP-NodeJS TypeScript definitions**, both actively maintained with
complete service and characteristic definitions. Apple's open-source HomeKitADK
was archived in October 2025 but remains accessible.

## Official Apple sources offer PDF-only specification

Apple provides the HAP specification through
**developer.apple.com/homekit/specification/**, though access requires a free
Apple Developer ID and license agreement acceptance. The publicly available
version is **Release R2, dated July 26, 2019**, spanning approximately 256-259
pages covering IP transport, Bluetooth LE transport, pairing protocols, and all
services/characteristics.

The PDF covers comprehensive protocol details including HAP objects, the
accessory attribute database, pair setup/verify procedures, TLV encoding,
characteristic permissions, and IP camera/RTP handling. While PDF-to-text
conversion is possible, this specification is **over 5 years old** and lacks
newer features like Thread networking support (added November 2020 for MFi
members).

Commercial versions (R8, R15, R25+) require **MFi Program membership** at
mfi.apple.com, which mandates business registration, a D-U-N-S Number, and NDA
execution. A repository at **github.com/seydx/hap-r13** contains HAP
Specification R13 PDF, a newer version than the publicly available R2.

## Apple HomeKitADK provides markdown and C header documentation

Apple's official open-source implementation at **github.com/apple/HomeKitADK**
was archived on October 28, 2025 but remains fully accessible in read-only mode.
This repository offers the most official AI-friendly documentation:

- **Documentation directory**: Contains `getting_started.md` and other markdown
  files
- **HAP directory**: Well-commented C header files defining the complete
  protocol
- **Key files**: `HAPPairing.h` (pairing protocol), `HAPCharacteristic*.h`
  (characteristic definitions), `HAPService*.h` (service definitions)
- **License**: Apache 2.0, non-commercial use only

The ADK implements complete HAP functionality for IP and Bluetooth LE transports
with **2,600+ stars and 234 forks**. HTML documentation can be generated from
markdown using `make docs`. Espressif maintains an active port at
**github.com/espressif/esp-apple-homekit-adk** for ESP32 platforms.

## HAP-python offers the most AI-friendly JSON format

The HAP-python project at **github.com/ikalchev/HAP-python** provides **pure
JSON definition files** that are ideal for AI coding tools. **The complete
source code is checked out locally under `external/HAP-python/` and available to
study.**

| File                                   | Content                                                        | Lines         |
| -------------------------------------- | -------------------------------------------------------------- | ------------- |
| `pyhap/resources/services.json`        | All HAP services with UUIDs, required/optional characteristics | ~580          |
| `pyhap/resources/characteristics.json` | All HAP characteristics with UUIDs, formats, permissions       | Comprehensive |
| `pyhap/const.py`                       | Protocol constants                                             | Complete      |

The JSON format includes service UUIDs, required and optional characteristics
arrays, and structured data that can be directly parsed by AI systems. The
project maintains **653 stars**, was last updated November 2024 (v4.9.2), and
has documentation at **hap-python.readthedocs.io**. This is the **single best
source for structured, machine-readable HAP definitions**.

## HAP-NodeJS delivers comprehensive TypeScript definitions

The primary Homebridge implementation at **github.com/homebridge/HAP-NodeJS**
offers exceptional TypeScript documentation. **The complete source code is
checked out locally under `external/HAP-NodeJS/` and available to study.**

- **API Documentation**:
  https://developers.homebridge.io/HAP-NodeJS/modules.html
- **Service definitions**: `src/lib/Service.ts` and
  `src/lib/definitions/ServiceDefinitions.ts`
- **Characteristic definitions**: `src/lib/Characteristic.ts` and
  `src/lib/definitions/CharacteristicDefinitions.ts`
- **Coverage**: ~45 services, ~128 characteristics per HAP specification

With **2,700+ stars** and active development (v2.0.2 released September 2025),
HAP-NodeJS provides complete type definitions with JSDoc documentation. The
TypeScript source files serve as both implementation reference and protocol
specification, making them highly valuable for AI coding agents building HomeKit
accessories.

## HomeSpan provides excellent markdown documentation

The HomeSpan project at **github.com/HomeSpan/HomeSpan** targets ESP32
development with outstanding markdown documentation. **The complete source code
is checked out locally under `external/HomeSpan/` and available to study.**

- `docs/ServiceList.md` – Complete list of all HAP services and characteristics
- `docs/Categories.md` – All HAP accessory categories
- `docs/Reference.md` – Full API reference
- `docs/TVServices.md` – Undocumented television services
- `docs/TLV8.md` – TLV8 characteristic handling

Licensed under MIT with **2,000+ stars**, HomeSpan implements the full HAP-R2
specification and was last updated October 2025 (v2.1.6). The documentation is
specifically written for developers new to HomeKit, making it valuable for AI
agents learning the protocol.

## Additional implementations with protocol documentation

Several other repositories contain useful HAP documentation in various formats:

**Go implementation (github.com/brutella/hap)**: Clean Go source with godoc
comments, documented at pkg.go.dev/github.com/brutella/hap. Implements
hierarchical accessory/service/characteristic model with mDNS announcement.

**Rust implementation (github.com/ewilken/hap-rs)**: Full HAP implementation
supporting all services and characteristics, with custom characteristic support.
Documentation available through docs.rs.

**Elixir implementation (github.com/mtrudel/hap)**: HexDocs documentation at
hexdocs.pm/hap covering HAP.AccessoryServer, HAP.Service, and HAP.Characteristic
structs.

**Apple Home Key (github.com/kormax/apple-home-key)**: Reverse-engineered NFC
protocol documentation for HomeKit locks in markdown format, covering
authentication flows and cryptographic details.

## Recommended sources for AI coding agents

For building HomeKit software with an AI coding agent, prioritize these sources
in order:

1. **HAP-python JSON files** (`external/HAP-python/pyhap/resources/`) – Most
   machine-readable format for service/characteristic definitions
2. **HAP-NodeJS TypeScript source** (`external/HAP-NodeJS/src/lib/`) – Complete
   type definitions with comprehensive documentation
3. **HomeSpan markdown docs** (`external/HomeSpan/docs/`) – Human-readable
   protocol explanation in plain text
4. **Apple HomeKitADK headers** – Official C definitions with detailed comments
5. **HAP-R2 PDF (converted)** – Authoritative reference when edge cases arise

## Conclusion

The HAP specification is available in AI-friendly formats primarily through
community implementations rather than official Apple channels. **HAP-python's
JSON files represent the optimal format** for direct machine parsing, while
HAP-NodeJS TypeScript definitions provide the most comprehensive type-safe
documentation. Apple's archived HomeKitADK offers official markdown and C header
documentation under Apache 2.0 licensing.

Key version information: the public non-commercial specification is **R2 from
July 2019**, covering approximately 45 services and 128 characteristics. Apple's
transition toward Matter (with HomeKitADK archived October 2025) suggests HAP
development may receive less official support going forward, making
community-maintained implementations increasingly important for ongoing
development.
