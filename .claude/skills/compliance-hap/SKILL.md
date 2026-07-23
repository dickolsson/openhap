---
name: compliance-hap
description:
  Audit the OpenHAP codebase for HomeKit Accessory Protocol compliance against
  spec/HAP.md and spec/HAP-*.md, writing findings to a scratchpad file. Use when
  asked to review, audit, or verify HAP protocol correctness or spec compliance.
---

# HomeKit Accessory Protocol Compliance Review

## Objective

Review the OpenHAP codebase for strict compliance with the HomeKit Accessory
Protocol specification.

## Preconditions

`spec/HAP.md` and `spec/HAP-*.md` must exist — regenerate them with the
`spec-hap` skill if missing.

## Specification

Study the HAP specification files in `spec/` thoroughly:

- `spec/HAP.md` — Overview, glossary, and index to topic files
- `spec/HAP-*.md` — Detailed topic-specific specifications

These documents define the protocol requirements that OpenHAP must implement
correctly. Pay attention to:

- Exact values, formats, and encodings
- Required vs optional behaviors
- Error handling requirements
- Cryptographic parameters and constants
- Protocol state machines

## Review Approach

Compare the OpenHAP implementation against the specification systematically.
Focus on correctness—places where the implementation deviates from what the
specification requires.

For each area of the protocol, examine the relevant OpenHAP modules and verify
they implement the specification correctly. Look for:

- Incorrect values or constants
- Missing protocol steps or state transitions
- Improper encoding/decoding
- Wrong cryptographic parameters
- Missing error handling
- Deviations from required behavior

## What to Document

For each finding, record:

1. **What the spec requires** — cite the specific requirement from the relevant
   `spec/HAP*.md` file
2. **What the code does** — identify the file and relevant code section
3. **The discrepancy** — explain how the implementation differs
4. **Severity** — will this cause interoperability failures, security issues, or
   minor protocol violations?

## Scope

Review the core HAP implementation modules, particularly:

- Pairing protocols (SRP, pair setup, pair verify)
- Session encryption
- TLV8 encoding/decoding
- HTTP endpoint handling
- mDNS advertisement
- Accessory/service/characteristic modeling
- Event notifications

Do not review device-specific code (Tasmota integration) or infrastructure code
unless it directly affects HAP protocol compliance.

## Output

A compliance report that can guide remediation, recorded per the scratchpad
convention in the root CLAUDE.md. Prioritize findings by impact on HomeKit
interoperability.
