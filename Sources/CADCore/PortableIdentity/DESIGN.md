# Portable Identity

## Purpose and Scope

This component owns the Foundation-free 128-bit identity value used by
`CADCore.TaggedID`. It is a child of [CADCore](../DESIGN.md). It owns byte
order, UUID-compatible canonical text, random version/variant bits, and typed
malformed-input failure. It does not own source-envelope serialization,
Foundation adapters, transaction UUIDs, or application publication.

## Responsibilities and Boundaries

The component stores exactly two UInt64 words and exposes deterministic,
portable operations. `TaggedID<Tag>` remains the typed identity wrapper and
retains its existing equality, ordering, hashing, and high/low construction
semantics; its explicit Native UUID and Codable adapters remain owned by
`CADCore/TaggedID.swift`. CADExchange owns strict Native/STEP wire and schema
admission. CADIR owns persistent record meaning and source fingerprints.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADCore](../DESIGN.md) | parent | Foundation-free Core values | Provides the module boundary and typed failure policy | Do not reintroduce Foundation into the common value |
| [CADExchange](../../CADExchange/DESIGN.md) | used by | strict Native/STEP wire and schema admission | Consumes the explicit `TaggedID` adapters at exchange boundaries | UUID compatibility is explicit; no silent migration |
| [CADIR](../../CADIR/DESIGN.md) | used by | tagged persistent references | Stores document, assembly, attribute, and topology references | Source envelope/Codable capability remains separate |

## Architecture

```text
random or explicit words
          -> PortableIdentity128
          -> TaggedID<Tag>
          -> persistent CADIR references / exchange adapters
```

## Contracts and Invariants

- `high` and `low` are preserved exactly; UUID bytes use the current big-endian
  word mapping.
- Canonical text is exactly `8-4-4-4-12` hexadecimal characters with uppercase
  output. Parsing is case-insensitive but rejects malformed length, separators,
  or non-hex input with a typed error.
- Random construction sets RFC 4122 version 4 and variant 2 bits and does not
  return a constant or guessed identity.
- Equality, ordering, and hashing compare the two words exactly as the current
  `TaggedID` implementation does.
- Codable is not claimed by this component. Embedded Swift currently marks
  Codable unavailable; Native source serialization must use its explicit
  adapter contract until that separate migration is complete.

## Verification and Change Impact

Core tests must cover a known UUID byte vector, canonical text round trip,
malformed refusal, random version/variant bits, and equality/order/hash and
high/low preservation through `TaggedID`. Native tests must cover the existing
UUID text and dynamic-key admission without changing source identity meaning.
Changes require review of the eight production `rawValue.uuidString`
consumers, deterministic high/low callers, and the STEP occurrence UUID
adapter. This component does not prove the full CADIR Codable graph or Embedded
package portability.
