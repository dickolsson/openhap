# HomeKit Accessory Protocol Compliance Review

Review the OpenHAP codebase for strict compliance with the HomeKit Accessory
Protocol specification.

Document all findings in `SCRATCHPAD-<N>.md` (with N being the next available
number).

## Background

Read `spec/README.md` to understand the available reference implementations and
documentation sources for HAP.

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

Produce a compliance report that can guide remediation. Prioritize findings by
impact on HomeKit interoperability.
