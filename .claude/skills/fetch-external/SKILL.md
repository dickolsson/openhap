---
name: fetch-external
description:
  Fetch the reference sources into the gitignored external/ directory
  (HAP-python, HAP-NodeJS, HomeSpan, HomeKitADK, Tasmota-Docs). Use when
  external/ is missing or empty, or before running the spec-hap, spec-mqtt,
  implementations, or compliance skills.
---

# Fetch External Reference Sources

## Objective

Populate `external/` with the reference implementations and documentation that
the spec and analysis skills read. `external/` is gitignored and never
committed; every fresh checkout starts without it.

## Workflow

1. Shallow-clone the sources:

   ```sh
   mkdir -p external
   git clone --depth 1 https://github.com/ikalchev/HAP-python external/HAP-python
   git clone --depth 1 https://github.com/homebridge/HAP-NodeJS external/HAP-NodeJS
   git clone --depth 1 https://github.com/HomeSpan/HomeSpan external/HomeSpan
   git clone --depth 1 https://github.com/apple/HomeKitADK external/HomeKitADK
   git clone --depth 1 https://github.com/tasmota/docs external/Tasmota-Docs
   ```

2. Verify the key paths exist:
   - `external/HAP-python/pyhap/resources/services.json`
   - `external/HAP-NodeJS/src/lib/definitions/`
   - `external/HomeSpan/docs/ServiceList.md`
   - `external/HomeKitADK/HAP/`
   - `external/Tasmota-Docs/docs/MQTT.md`

## Source Map

Prefer sources in this order when extracting protocol details:

| Source                              | Content                                                      | Best for                              |
| ----------------------------------- | ------------------------------------------------------------ | ------------------------------------- |
| `HAP-python/pyhap/resources/*.json` | All services and characteristics as machine-readable JSON    | UUIDs, formats, permissions           |
| `HAP-NodeJS/src/lib/definitions/`   | Complete TypeScript service/characteristic definitions       | Type details, value constraints       |
| `HomeSpan/docs/`                    | Human-readable protocol docs (ServiceList, TLV8, Categories) | Prose explanations of protocol areas  |
| `HomeKitADK/HAP/*.h`                | Apple's official, well-commented C headers                   | Protocol constants, pairing internals |
| `Tasmota-Docs/docs/`                | Tasmota MQTT, Commands, Lights, Buttons-and-Switches, Status | Tasmota MQTT protocol                 |

Notes:

- The public HAP specification is R2 (July 2019); newer revisions require MFi
  membership. The sources above are the practical reference.
- HomeKitADK was archived by Apple in October 2025 but remains accessible
  read-only.

## Output

A populated `external/` directory. Nothing is committed.

## References

- `spec/CLAUDE.md` — which skill generates which `spec/` file from these sources
