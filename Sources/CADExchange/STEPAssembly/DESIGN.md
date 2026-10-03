# STEP Assembly

## Purpose and Scope

This component owns exact STEP assembly interchange and the structural transport
needed by PARX.X3 product attributes: part definitions,
placed occurrences, shared parts, nesting, and local coordinate systems through
public STEPExchange and OfficialFormatExchange paths. Parent:
[CADExchange](../DESIGN.md). No children. It composes the existing exact geometry
reader/writer; it does not port OCCT implementation code.

## Responsibilities and Boundaries

The reader owns product-definition and shape-representation association,
occurrence placement syntax, standard coordinate-frame interpretation, and
explicit admission of representation alternatives. Existing ExactSTEPReader
owns exact local geometry. Each local source body is retained by one existing
ImportedBRepFeature; DocumentAssembly references these real FeatureIDs.
Assembly Evaluation owns placed world output and correspondence.

The writer serializes one local geometry representation per nonempty canonical
FeatureID list shared by retained leaf definitions, distinct definition metadata,
an optional whole-part style carrier representation, and one
usage relationship per direct source occurrence. It never manufactures a new
part definition for each expanded leaf path. Source DAG and validated local
artifacts authorize export; a flattened world B-rep alone cannot claim to retain
assembly structure. Ordinary B-rep-only STEP export remains a single product.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADExchange](../DESIGN.md) | parent | ByteSource/ByteSink, facade routes, limits, atomic URL output | Owns public format routing | All failures occur before output publication |
| [Document Assembly](../../CADIR/DocumentAssembly/DESIGN.md) | depends on | source definitions, occurrences, local frames | Retains assembly semantics in CAD source | The current strict envelope is owned by CADCore; source assembly is required nullable |
| [STEP Attributes](../STEPAttributes/DESIGN.md) | coordinates with | lexical fields, retained definition/topology entity maps, whole-part mapped-item carrier | Preserves source attribute target scope | Attribute policy remains owned by STEP Attributes |
| [Assembly Evaluation](../../CADKernel/AssemblyEvaluation/DESIGN.md) | depends on | local artifacts and world correspondence | Confirms source-to-geometry consistency | World geometry cannot substitute for local definitions |
| [CADTopology](../../CADTopology/DESIGN.md) | depends on | ownership-closed exact B-rep extraction/validation | Retains exact local parts | Unsupported geometry remains typed refusal |

## Architecture

```mermaid
flowchart LR
    Bytes[Bounded STEP bytes] --> Syntax[Product/representation/placement parser]
    Syntax --> Geometry[Exact local geometry reader]
    Geometry --> Features[ImportedBRepFeature sources]
    Syntax --> DAG[DocumentAssembly source DAG]
    Features --> Document[Validated CADDocument]
    DAG --> Document
    Document --> Evaluation[Assembly Evaluation]
    Evaluation --> Writer[Definition geometry + usage writer]
    Writer --> Table[One bounded STEP entity table]
    Table --> Output[Atomic complete output]
```

## Contracts and Invariants

- Product definitions are related to local shape representations through
  PRODUCT_DEFINITION_SHAPE and SHAPE_DEFINITION_REPRESENTATION. Assembly edges
  retain NEXT_ASSEMBLY_USAGE_OCCURRENCE identity and parent/child definition
  references, with CONTEXT_DEPENDENT_SHAPE_REPRESENTATION providing placement.
  Multiple usages of the same product definition retain one shared definition.
- For a representation relationship with transformation, rep_1 is the child
  representation and rep_2 the parent. ITEM_DEFINED_TRANSFORMATION item_1 is
  the child reference frame and item_2 its placed frame in the parent. The local
  transform is frame_2 composed with inverse(frame_1); nested world placement is
  parent-world composed with local. Nonorigin reference frames are supported.
- Representation contexts on a transformed relationship have distinct entity
  identities, even when they use the same units. Referenced transformation axes
  belong to the matching representation items. Writers generate a distinct geometric
  context for each definition; equal unit values do not imply equal contexts.
- Assembly rigid placements have scale one and positive determinant. Unsupported
  scaling, reflection, external definitions, missing placement, conflicting
  representation associations, cyclic products, and alternative flattened
  assembly geometry fail explicitly. No default identity transform is inferred
  for a missing occurrence placement.
- Admitted standard assembly syntax includes transformed representation
  relationships with item-defined axis frames and proper-rigid Cartesian
  transformation operators. Representation-map/mapped-item structure must be
  resolved with its standard origin/target semantics when admitted; unsupported
  or ambiguous variants are explicitly refused and never silently flattened.
- STEPFieldReading exposes bounded lexical entity fields, references, strings,
  numeric values, and tuple structure to STEP Attributes. STEPAssemblySyntax
  implements this contract; consumers do not duplicate its lexical parser.
- STEPStringCoding owns ISO 10303-21 string token encoding and decoding. The
  shared lexical contract exposes bounded decoding with actual consumed work.
  It admits doubled apostrophes/backslashes, direct UTF-8, X, S, X2, X4 and
  per-string PA through PI ISO 8859 alphabet selection. UCS blocks contain
  complete scalar groups, not surrogate pairs; invalid scalars, undefined page
  entries, malformed directives and incomplete blocks fail explicitly. No Unicode
  normalization or replacement character repairs input. Quote/depth/envelope
  lexers recognize ASCII delimiters on Unicode scalar boundaries, including
  a combining scalar immediately after an apostrophe. Their existing marker,
  nesting and resource rules remain authoritative. Writers emit portable
  ASCII tokens with canonical explicit UCS blocks and doubled literal delimiters.
  The normative encoded-token ceiling is 32769 octets including quotes; caller
  input/output/work ceilings may be smaller. Input and output bytes and scalar
  traversal are admitted before allocation/growth. Decode work counts input
  octets plus emitted scalars; encode work counts input octets plus encoded
  octets. Input traversal stops at a caller ceiling without scanning the remainder.
  Consumer operation counters
  charge actual consumed work and retained text. Cancellation propagates.
- The persistent source graph retains PRODUCT, PRODUCT_DEFINITION_FORMATION and
  PRODUCT_DEFINITION as distinct owners. A shared PRODUCT and formation are written
  once and referenced by distinct definitions; no metadata is cloned per view.
  PRODUCT.id, formation.id and PRODUCT_DEFINITION.id retain their original strings,
  including empty and UUID-shaped strings. `$` and `''` remain distinct for each
  optional description. Formation UR1 is enforced; the specified-source subtype
  accepts only MADE, BOUGHT and NOT_KNOWN. Unsupported product graph subtypes fail.
- Public STEP entity admission recognizes EXTERNAL_SOURCE, IDENTIFICATION_ROLE
  and APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT before invoking this component.
  Admission of their entity names does not certify their semantics: the source
  identity reader still validates namespace, role, target, UUID and caller ceilings.
- Product, formation and definition typed UUIDs use a separate standard
  APPLIED_EXTERNAL_IDENTIFICATION_ASSIGNMENT with EXTERNAL_SOURCE
  IDENTIFIER('urn:swiftcad:assembly-source-id') and IDENTIFICATION_ROLE named
  'product', 'formation' or 'definition'. Each assignment has one matching entity
  target and a canonical UUID assigned_id. The role/source are an explicit
  application identification namespace, not a universal standard UUID role.
  Their business identifiers never supply native UUID authority. Existing X2
  occurrence identity transport and occurrence source fields are unchanged by
  this product-owner contract. Absent assignments
  cause distinct entity-scoped source identities to be generated; export retains
  them through explicit assignments. Duplicate/competing assignments, malformed
  UUIDs and role/target mismatches fail. Other namespaces or unsupported assignment
  variants fail explicitly instead of being silently discarded. Identity parsing
  charges the same caller work/text/entity ceilings and checks cancellation.
- Only the exact writer-authored bare profile uses the ordinary geometry route:
  PRODUCT.id SWIFTCAD, empty product name/description, base formation with empty
  version/description, and PD.id design with empty description. `$` is not an
  empty description. Any other product/PD identifier or nullable distinction uses
  the source product graph, including empty and UUID-shaped business identifiers. Source identity assignments also require
  this route so UUID authority is not discarded. The authored root envelope's
  definition is removed only with its reserved identifier/name, empty local
  geometry, canonical blank descriptions/version and base formation, canonical
  design identifier, and no native identity assignment on any of its three owners.
  Matching business labels on a genuine described or identified product do not
  authorize cleanup. Its formation/product are removed only if no retained
  definition references them.
- Distinct product definitions may associate the same exact local shape
  representation. The reader extracts that actual representation identity and
  its owned unit once, reuses its complete FeatureID list, and retains every
  definition association in a one-to-many transfer. It never merges equal-valued
  representations or duplicates the local B-rep to obtain PD-specific targets.
  A contextual path selects its actual definition membership; a GISU selects
  its explicit shape-aspect PD and then checks representation/item membership.
  A bare mapped assembly item referencing a representation with several possible
  definitions remains ambiguous; NAUO/CDSR retains an explicit child definition.
- The writer caches nonempty leaf geometry by canonical FeatureID identity,
  retaining one topology/entity map and geometric representation. Each PD keeps
  its own metadata, PDS and native UUID assignment. Empty or child assembly
  representations remain distinct. Different canonical groups with partially
  overlapping FeatureIDs are refused before output: the present complete-group
  representation transport cannot preserve one owner across partial groups.
  Modular partial-group transport remains incomplete; duplicating geometry is
  not an admitted substitute. If any definition sharing a feature list
  requires whole-part appearance, every definition in that group receives its
  own proved identity carrier over one unassociated shared inner representation.
  One shared carrier cannot be treated as a single-PD part attachment: such
  representation-level set scope is refused before publication.
- A whole-part styling carrier is structural transport for one real product
  definition. Its product-associated outer representation contains exactly one
  MAPPED_ITEM plus its frame. The representation map refers to an unassociated
  inner representation containing the complete retained local geometry and its
  origin. Equal declared units and explicitly resolved identity origin/target
  transformation are required. The inner representation has no nested mapped
  usage, competing geometry association, or cycle. These conditions are checked
  before classifying ordinary mapped items as assembly occurrences.
- An admitted carrier retains the existing definition and ImportedBRepFeature;
  it creates no additional feature, definition, occurrence, or semantic name.
  The carrier entity maps to the part attribute target, while inner geometry
  entities retain their body/face maps. A styled MAPPED_ITEM therefore preserves
  whole-part scope rather than expanding that scope into body assignments.
  Overriding face styles retain their explicit predecessor relationship.
- Carrier export is admitted for definitions with real local geometry. Empty
  subassemblies and mixed local-geometry/child definitions keep their existing
  admission contracts. Unsupported or ambiguous carrier structures fail before
  publication; they are not flattened or assigned guessed identity placement.
- Local geometry and placement translations are normalized using their declared
  representation length units. Multiple contexts declaring the same unit are
  not mistaken for conflicting units. Conflicting or unsupported unit contexts
  are refused unless the reader completely resolves each local context.
- Writer geometry helpers append local parts to one globally bounded entity
  table with per-part topology maps. Entity IDs do not collide across parts,
  even when native local topology IDs do. Assembly representations include their
  coordinate-frame items; empty geometry is not an invalid empty item set.
- Import publishes a validated assembly CADDocument and its placed exact B-rep.
  Export through memory and URL facades consumes the same evaluated-source
  assembly contract. Shared definitions, direct local placements, and nesting
  survive STEP and strict native save/load without becoming presentation metadata.
- Parsing, structural traversal, expansion, and entity writing charge existing
  exchange byte/entity/nesting/work/time budgets and explicit assembly evaluation
  limits before standard source expansion or consistency reconstruction. Export
  consistency uses its exchange ceilings, rather than trusting a larger retained
  evaluation allowance. Cancellation propagates; failures publish no partial document/model
  and do not modify an existing URL output.

The string authority is [ISO 10303-21, section 6.4.3](https://www.steptools.com/stds/step/IS_final_p21e3.html).
Product/formation/definition ownership and identifier optionality follow the standard EXPRESS
[PRODUCT](https://www.steptools.com/stds/stp_aim/html/t_product.html) and
[PRODUCT_DEFINITION](https://www.steptools.com/stds/stp_aim/html/t_product_definition.html),
[FORMATION](https://www.steptools.com/stds/stp_aim/html/t_product_definition_formation.html),
and [external identification targets](https://www.steptools.com/stds/stp_aim/html/t_external_identification_item.html).

The standard placement authority is
[ISO 10303-43 representation structures](https://www.steptools.com/stds/smrl/data/resource_docs/representation_structures/sys/4_schema.htm)
and the [PDM Schema Usage Guide 4.3, sections 3.4 and 4.4](https://www.mbx-if.org/home/wp-content/uploads/2024/05/pdmug_release4_3.pdf).
The [official OCCT STEP guide](https://github.com/Open-Cascade-SAS/OCCT/blob/master/dox/user_guides/step/step.md)
documents product/usage/representation mapping and alternative-geometry
ambiguity. These sources establish semantics, not an implementation dependency.

## Runtime Flows

```text
ByteSource -> envelope/entities -> product/representation graph -> local exact parts
 -> source DAG + feature sources -> source validation -> exact assembly evaluation
 -> complete ImportedExchangeModel

EvaluatedDocument -> validate source/local/world correspondence -> serialize definitions
 once -> serialize direct usages/frames -> complete bytes -> ByteSink/atomic URL
```

## State, Ownership, and Lifecycle

The parser borrows complete owned input within its existing byte-source scope.
Entity and association indexes are operation-local. Returned source values own
their exact local models and structural identities. Writer topology dictionaries
are local to each definition, while the entity table belongs to the complete
write operation. No mutable state persists across calls.

## Failure, Concurrency, and Constraints

New assembly operations use a public protocol and typed failures. Existing STEP
syntax, geometry, unit, cancellation, and resource errors propagate. Admission
checks representation ambiguity before publishing source. Export assembles the
entire bounded output before committing to a sink, preserving the existing
facade's atomic URL transaction.

## Verification and Change Impact

[STEPAssemblyExchangeTests](../../../Tests/CADExchangeTests/STEPAssemblyExchangeTests.swift)
owns independently authored standard fixtures containing shared parts, nested
usage, nonorigin frames, and rotation/translation. Assertions verify local and
world coordinates, product sharing, direct placement values, typed correspondence,
public facade in-memory/URL round trips, strict native persistence, source edits,
ambiguity/dangling/cycle/resource/cancellation refusal, and atomic failures.
[STEPAttributesExchangeTests](../../../Tests/CADExchangeTests/STEPAttributesExchangeTests.swift)
owns independently authored whole-part carrier fixtures, multiple local bodies,
face style overrides, source scope round trips, and invalid carrier refusal.
Existing STEPAssemblyExchangeTests verify that genuine mapped occurrences remain
assembly edges rather than styling carriers.
[STEPStringExchangeTests](../../../Tests/CADExchangeTests/STEPStringExchangeTests.swift)
owns independent encoded literals, malformed/resource/cancellation boundaries,
and public STEP/native description and attributed Unicode round trips.
[SharedSTEPProductTests](../../../Tests/CADExchangeTests/SharedSTEPProductTests.swift)
owns independent shared PRODUCT/formation with distinct represented definitions,
raw identifiers versus assigned UUIDs, two STEP generations, native persistence,
shared-name and local attribute edits, incremental geometry reuse and stale receipt
refusal, malformed/competing identity and bounded failure.
Existing ExactSTEPExchangeTests retain ordinary single-product geometry/unit
regression ownership. Changes require coordinated verification of DocumentAssembly,
Assembly Evaluation, native strict schema, and public STEP facade routing.

Unassociated singleton physical target views are consumed by the
[STEP Attributes contract](../STEPAttributes/DESIGN.md); they refer existing exact
items and do not become local geometry owners or PD shape associations.
[SharedSTEPRepresentationTests](../../../Tests/CADExchangeTests/SharedSTEPRepresentationTests.swift)
verify one local owner and multiple real PD/world instances across Native and two
public STEP generations, with shared geometry and distinct structural carriers.
