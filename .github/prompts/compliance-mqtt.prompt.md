# Tasmota MQTT Protocol Compliance Review

Review the OpenHAP codebase for strict compliance with the Tasmota MQTT protocol
specification.

Document all findings in `SCRATCHPAD-<N>.md` (with N being the next available
number).

## Background

Read `spec/README.md` to understand the context and available reference
materials for the protocols OpenHAP implements.

## Specification

Study `spec/MQTT.md` thoroughly. This document defines how Tasmota devices
communicate over MQTT and how OpenHAP must interact with them. Pay attention to:

- Topic naming conventions and patterns
- Command/response message formats
- JSON payload structures
- Device state reporting mechanisms
- Device type-specific behaviors

## Review Approach

Compare the OpenHAP MQTT implementation against the specification systematically.
Focus on correctness—places where the implementation deviates from what the
specification requires or makes incorrect assumptions about Tasmota behavior.

For each aspect of the protocol, examine the relevant OpenHAP modules and verify
they handle Tasmota communication correctly. Look for:

- Incorrect topic patterns
- Wrong message formats or payloads
- Missing or incorrect response handling
- Improper value parsing or conversion
- Assumptions that don't match Tasmota behavior
- Missing device states or command variants

## What to Document

For each finding, record:

1. **What the spec requires** — cite the specific requirement from `spec/MQTT.md`
2. **What the code does** — identify the file and relevant code section
3. **The discrepancy** — explain how the implementation differs
4. **Severity** — will this cause device control failures, state sync issues, or
   minor protocol deviations?

## Scope

Review the MQTT and Tasmota integration code, particularly:

- MQTT client implementation
- Topic subscription patterns
- Command publishing
- Response parsing
- Telemetry handling
- Device state synchronization
- Device-specific modules (Tasmota/*.pm)

Do not review HAP protocol code or general infrastructure unless it directly
affects MQTT/Tasmota compliance.

## Output

Produce a compliance report that can guide remediation. Prioritize findings by
impact on device interoperability and user experience.
