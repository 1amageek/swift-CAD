# Original STEP Length Source

## Purpose and Scope
Child of [Original STEP Placement](../DESIGN.md), with no children. Owns original foreign length-unit records and their exact coordinate gain. Native LengthUnit's binary numeric convention remains with CADCore.

## Responsibilities and Boundaries
Retains actual unit, dimensions and measure identities, SI prefix, conversion name, original decimal factor token and base source. Exchange owns parsing/context membership and re-emitting legal unit entities. Geometry owns exact rational arithmetic and normalized frame action.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Parent](../DESIGN.md) | parent | original placement gain | Converts raw model location exactly | Missing descriptor denotes native binary convention |
| [Rational Algebra](../../../../CADGeometry/RationalBivariateAlgebra/DESIGN.md) | depends on | RationalAlgebraAdmitting and ExactRationalCoefficient | Exact decimal arithmetic | One original caller ledger and depth |

## Architecture
```text
context -> original SI/conversion unit graph -> exact decimal gain
 -> original normalized placement -> geometry action
```

## Contracts and Invariants
SI prefix gain is exactly ten to its declared integer power. Decimal conversion tokens retain sign, digits and exponent; gain preparation uses exact rational arithmetic without parsing through Double. Conversion dimensions are exactly length exponent one and six zero exponents. Chain source identities and operand order survive persistence. Native codecs require every declared field, reject unknown keys and debit the package's original exact allowance before collection growth. Source nesting follows the caller depth; factor size follows caller work/storage, with no implicit precision/depth relaxation.

## Failure, Concurrency, and Constraints
Immutable Sendable values own the source graph. Invalid decimal grammar, nonpositive conversion, invalid dimensions, original identity conflicts and actual resource exhaustion are typed failures. No empty/default source substitutes for an absent foreign context.

## Verification and Change Impact
Source authoring precedes execution. Behavioral evidence must distinguish exact MILLImetre location 1000 -> 1 metre from a binary 0.001 factor, retain two-generation raw custom chains, reject malformed decimal/exponent/dimensions and exercise the original caller limits. Changes affect placement/primitive readers, Native strict codecs, portable source encoding and context writers.

Native identity fields use the parent [Native identity adapter](../DESIGN.md#native-identity-adapter). Explicit encoding retains every original conversion field and nullable prefix; source schema and exact decimal interpretation do not change.
