# Prompt: Analyze HAP Implementations

## Objective

Study how mature open source HAP implementations work and document the practical
patterns in `spec/IMPLEMENTATIONS.md`. The goal is to help AI coding agents
understand _how_ real projects solve HAP problems, not just _what_ the protocol
requires.

## Background

Read `spec/README.md` first — it explains what source material is available in
`external/` and why certain implementations are preferred.

## What to Analyze

Explore the implementations in `external/` and extract practical knowledge:

- **HAP-python** — Python implementation with JSON service/characteristic files
- **HAP-NodeJS** — TypeScript implementation powering Homebridge
- **HomeSpan** — ESP32 implementation with excellent documentation
- **HomeKitADK** — Apple's official (archived) reference implementation

Focus on IP transport only. Skip Bluetooth LE, Thread, cameras, and Matter.

## Questions to Answer

Rather than mechanically listing features, answer these practical questions:

**Architecture:**

- How do implementations model the accessory → service → characteristic
  hierarchy?
- What data structures represent HAP objects at runtime?
- How are service/characteristic definitions loaded or declared?

**Pairing & Crypto:**

- What are the actual steps in pair setup and pair verify?
- What crypto primitives are used and in what order?
- How are session keys derived and managed?
- What are the exact HKDF salt and info strings?

**TLV Encoding:**

- How do implementations encode/decode TLV8?
- How are long values (>255 bytes) split across fragments?
- What type codes are used and for what purposes?

**HTTP Handling:**

- What endpoints exist and what do they do?
- How is encrypted HTTP different from normal HTTP?
- What status codes are returned and when?

**Events:**

- How do implementations track characteristic subscriptions?
- How are EVENT responses formatted and sent?

**mDNS:**

- What service type is advertised?
- What TXT record fields are required and what do they mean?

## How to Analyze

1. **Read the source** — Explore files in `external/` to find answers
2. **Compare implementations** — Note where they agree (likely protocol
   requirement) vs. differ (implementation choice)
3. **Extract specifics** — Actual constants, exact byte sequences, real code
   patterns
4. **Cite sources** — Reference specific files so readers can verify

## Output

Create `spec/IMPLEMENTATIONS.md` documenting what you learned. Organize the
content around the questions above, but let the structure emerge from your
findings. Include:

- Concrete details (actual constants, specific algorithms, exact formats)
- Code snippets where they illuminate a pattern
- Comparisons showing how different projects solve the same problem
- File references with paths so readers can dig deeper

The document should help someone implementing HAP understand not just what to
build, but how proven implementations approached it.
