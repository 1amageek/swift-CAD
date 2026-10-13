"""Resolve the finite acceptance inventory; this is not execution evidence."""
from pathlib import Path
import hashlib
import itertools
import json
import re

ROOT = Path(__file__).resolve().parents[2]
DESIGN = ROOT / 'Sources/CADGeometry/OriginalDomainIdentity/OriginalDomainCoverage/DESIGN.md'
TEXT = DESIGN.read_text()
SECTIONS = {}
heading = None
for line in TEXT.splitlines():
    if line.startswith('#'):
        heading = line.lstrip('# ').strip()
        SECTIONS.setdefault(heading, [])
    elif heading:
        SECTIONS[heading].append(line)
SECTIONS = {key: '\n'.join(value).strip() for key, value in SECTIONS.items()}

SUFFIXES = ('CS', 'SSI', 'B', 'S', 'I', 'X')
FAMILIES = {
    'SRC-DS-GENERAL': (('A', 'Q'), 3),
    'SRC-BC-GENERAL': (('A', 'Q'), 3),
    'SRC-RULED-GENERAL': (('A', 'Q', 'HYPERBOLA'), 3),
    'SRC-COONS-GENERAL': (('A', 'Q', 'HYPERBOLA'), 3),
    'SRC-OFFSET-GENERAL': (tuple(f'{child}.d{d}' for child in ('A', 'Q', 'PERIODIC') for d in (-1, 0, 1)), 3),
    'SRC-REVOLUTION-GENERAL': (('A', 'Q', 'JOIN'), 3),
    'SRC-DRAFT-GENERAL': (('POS', 'NEG', 'ZERO', 'STATIONARY', 'A0', 'D0'), 3),
    'SRC-ANGULAR-GENERAL': (tuple(f'{shape}.{law}' for shape in ('CYLINDER', 'SPHERE', 'CONE', 'TORUS') for law in ('INTRINSIC', 'PHYSICAL', 'ARC')), 2),
    'SRC-GUIDE-GENERAL': (tuple(f'{child}.{direction}' for child in ('A', 'Q', 'HYPERBOLA') for direction in ('FORWARD', 'REVERSE')), 4),
    'SRC-IMPLICIT-GENERAL': (('PARABOLA.FORWARD', 'PARABOLA.REVERSE', 'PARABOLA.SPLIT', 'CLOSED', 'SINGULAR'), 4),
    'SRC-LIFT-GENERAL': (('QUADRATIC', 'CLAMP', 'ROUNDED'), 4),
}
CERTIFIED = {
    'CERT-SPHERECONE': ('full-', 'full+', 'bounded', 'open-', 'open+', 'apex'),
    'CERT-SPHERECONE-ENDPOINT': ('rootFree', 'lowerSimple', 'upperSimple', 'twoSimple', 'lowerDouble', 'upperDouble', 'twoDouble', 'lowerSimpleUpperDouble', 'lowerDoubleUpperSimple'),
    'CERT-CONECONE': ('full-', 'full+', 'bounded', 'apex.isolated', 'apex.loop', 'apex.node'),
    'CERT-CONECYLINDER': ('full-', 'full+', 'bounded', 'lowerNode', 'upperNode', 'linear'),
    'CERT-CONETORUS': ('regular0', 'regular1', 'regular2', 'regular3', 'apex'),
    'CERT-PARALLELTORI': tuple(f'{kind}{branch}' for kind, count in (('regular', 4), ('nodal', 4), ('near', 2)) for branch in range(count)),
}
REQUESTS = {
    'CS': 'Full authored curve domain and whole named target-plane UV; retain only authored lift P(T), every T root and every target-plane UV. Include contained, singleton and complete-empty controls.',
    'SSI': 'Full authored source and whole named plane in both source orders, then the declared closed quarter-box; retain every original UV and incident.',
    'B': 'Actual exact validated face, authored directed outer unit rectangle and inner [1/4,3/4]^2; all three policies; actual SSI and F(t,1/2) queries. The selected oracle is raw equality AND winding membership at every target preimage.',
    'S': 'Complete ordered D x D, original equality, minus authored diagonal and only the explicit scoped structural relations. Retain both material tuples when trimmed.',
    'I': 'The explicitly declared period/collapse/join or authored identity, restricted to both half-open scopes; symmetry and same-intermediate-owner composition. False boundary, foreign frame, crease and disjoint-scope controls are mandatory.',
    'X': 'Complete retained result through ordinary and prepared public entry, all XYZ/source tuples, rank-defined image/fiber strata and every integer cycle. No finite window substitutes for an infinite family.',
}
COMPLETION = 'Complete independent selection iff on every terminal cell; source/role/guard negatives; exact N/N-1 resources; entry/mid/final/empty/query cancellation; detached/COW lifetime; fixed Native/ASAN/WASM/Embedded; one review and finding-only confirmation; coherent commit and latest-main delivery.'
cells = []

def add(identifier, recipe, phase, variant=None, suffix=None, extra=None):
    assert recipe in SECTIONS, recipe
    cells.append(dict(id=identifier, binding=recipe, variant=variant, consumer=suffix,
        implementationOrder=phase, **(extra or {})))

for curve, surface in itertools.product(('LINE', 'CIRCLE-ANALYTIC', 'CIRCLE-NATIVE', 'ELLIPSE', 'HYPERBOLA', 'PARABOLA'),
        ('PLANEX2', 'PLANEZ0', 'CYLINDER', 'SPHERE', 'TORUS', 'CONE')):
    add(f'CS-PRIMITIVE.{curve}.{surface}', 'Primitive curve public matrix', 2,
        dict(curve=curve, surface=surface), 'CS')
for first, second in itertools.combinations_with_replacement(('PLANE', 'NATIVE', 'CYLINDER', 'CONE', 'SPHERE', 'TORUS'), 2):
    add(f'SSI-PRIMITIVE.{first}.{second}', 'Primitive surface public matrix', 2,
        dict(first=first, second=second), 'SSI')

# Every historical named input remains addressable; later exact source-pair
# definitions override the four old certified oracle gaps, never rounded laws.
overrides = {
    'CS-CERT-CONECONE-FULL-NEG-01': 'Certified branch expansion and source authority',
    'CS-CERT-CONECONE-FULL-POS-01': 'Certified branch expansion and source authority',
    'CS-CERT-CONECONE-POSITIVE-PLANE-01': 'Certified branch expansion and source authority',
    'CS-CERT-CONECYLINDER-POSITIVE-PLANE-01': 'Certified branch expansion and source authority',
    'CS-CERT-CONETORUS-REGULAR-PLANE-01': 'Certified branch expansion and source authority',
}
named = {}
for section, body in SECTIONS.items():
    for line in body.splitlines():
        if not line.startswith('| '):
            continue
        first = line.split('|')[1]
        for identifier in re.findall(r'\b(?:CS|SSI|SRC|CERTIFIED|B|S|I|PROJECTION|M8)-[A-Z0-9.-]+-01(?:\.[A-Z]+)?\b', first):
            named[identifier] = section
for identifier, section in sorted(named.items()):
    phase = 1 if 'CALLER' in identifier else 6 if identifier.startswith('PROJECTION') else 8 if identifier.startswith('M8') else 5 if identifier.startswith(('B-', 'S-', 'I-')) else 4 if any(x in identifier for x in ('CERT', 'IMPLICIT', 'JOIN', 'LIFT')) else 3
    add(identifier, overrides.get(identifier, section), phase,
        extra=dict(namedRow=identifier, historicalBinding=section))

base_instances = []
for prefix, (variants, phase) in FAMILIES.items():
    for variant in variants:
        if prefix == 'SRC-GUIDE-GENERAL':
            forms = [('curve', ('CS', 'I', 'X')), ('ruledHost', ('SSI', 'B', 'S', 'I', 'X')), ('coonsHost', ('SSI', 'B', 'S', 'I', 'X'))]
        elif prefix == 'SRC-IMPLICIT-GENERAL':
            forms = [('curve', ('CS', 'I', 'X'))]
        elif prefix == 'SRC-LIFT-GENERAL':
            forms = [('curve', ('CS', 'I', 'X')), ('host', ('B', 'S'))]
        elif prefix == 'SRC-DRAFT-GENERAL':
            forms = [('curve', ('CS', 'I', 'X')), ('wall', SUFFIXES)]
        else:
            forms = [('surface', SUFFIXES)]
        for form, suffixes in forms:
            base_instances.append((prefix, variant, form, suffixes))
            for suffix in suffixes:
                add(f'{prefix}.{variant}.{form}.{suffix}', 'Remaining source branch registry', phase,
                    dict(branch=variant, form=form), suffix, dict(sourcePrefix=prefix))
for (prefix, variant, form, suffixes), operation, nesting in itertools.product(base_instances, ('IMAGE', 'WORD', 'TRAVERSAL'), (1, 2)):
    for suffix in suffixes:
        add(f'SRC-COMPOSE-GENERAL.{prefix}.{variant}.{form}.{operation}.N{nesting}.{suffix}',
            'Remaining source branch registry', 4, dict(childPrefix=prefix, childVariant=variant, form=form, operation=operation, nesting=nesting), suffix,
            dict(sourcePrefix='SRC-COMPOSE-GENERAL'))
for prefix, variants in CERTIFIED.items():
    for variant, suffix in itertools.product(variants, ('CS', 'SSI', 'X')):
        add(f'{prefix}.{variant}.{suffix}', 'Certified branch expansion and source authority', 4, variant, suffix, dict(sourcePrefix=prefix))

pcurve_source = ROOT / 'Sources/CADGeometry/SurfaceParameterCurve.swift'
pcurve_text = pcurve_source.read_text()
pcurve_enum = pcurve_text[pcurve_text.index('public enum SurfaceParameterCurve:'):]
pcurves = re.findall(r'^    (?:indirect )?case (\w+)', pcurve_enum, re.M)
assert len(pcurves) == 17 and len(set(pcurves)) == 17
for pcurve in pcurves:
    directions = ('sourceToOffset', 'offsetToSource') if pcurve == 'offsetSurfaceImage' else ('first', 'second') if pcurve == 'certifiedAnalyticPair' else ('authored',)
    for direction, policy, missing in itertools.product(directions, ('closed', 'strictInterior', 'boundary'), (False, True)):
        add(f'B-PCURVE.{pcurve}.{direction}.{policy}.{"MISSING" if missing else "RETAINED"}',
            'All pcurve cases and actual boundary callers', 5,
            dict(pcurve=pcurve, direction=direction, policy=policy, missing=missing), 'B')
rolling_source = ROOT / 'Sources/CADGeometry/OriginalSourceIssuance/OriginalRollingBallCurveGraphCoverage.swift'
rolling = re.findall(r'^    case (\w+)', rolling_source.read_text(), re.M)
for selector in rolling + ['angular', 'algebraic', 'hyperbolic', 'polyline', 'periodicOffsetRail']:
    rails = ('affine', 'constantU', 'constantV') if selector in ('retainedLift', 'coonsLift', 'boundaryLift', 'derivativeLift') else ('authored',)
    for rail, suffix in itertools.product(rails, SUFFIXES):
        add(f'SRC-ROLLING-SELECTOR.{selector}.{rail}.{suffix}', 'Remaining source branch registry', 3,
            dict(selector=selector, rail=rail), suffix)

# The M0 rows own their finite public input matrix, not an unrestricted
# Cartesian product of every geometry name. Preserve every original row.
m0_rows = []
for line in SECTIONS['M0 implementation acceptance and ownership'].splitlines():
    if line.startswith('| ') and any(term in line for term in ('Native degree-one', 'Native tensor', 'Infinite original', 'Stored-N plane', 'Circle/ellipse', 'Cylinder / cone', '| Sphere |', '| Torus |', 'Rigid/affine', 'Offset/rolling', 'Implicit/certified')):
        family = line.split('|')[1].strip()
        m0_rows.append(dict(family=family, matrixRow=line,
            binding='M0 implementation acceptance and ownership',
            lowerEvidence='Tests/OriginalDomainConsumerVerification/Evidence/M0M3FinalMainIntegration/VERIFICATION.md'))

accepted = ([f'4-P{i}' for i in range(1, 12)] + [f'5-C{i}' for i in range(1, 13)] +
    [f'6-I{i}' for i in range(1, 5)] + [f'6-B{i}' for i in range(1, 12)] +
    [f'6-S{i}' for i in range(1, 12)] + ['M7', 'M8'])
assert len(accepted) == 51
assert len({cell['id'] for cell in cells}) == len(cells)
assert len(CERTIFIED) == 6  # Five families plus the sphere/cone endpoint enum.
interactions = [name for name in named if name.startswith('M8-')]
assert len(interactions) == 12
assert len(m0_rows) == 11
row_refs = {}
for cell in cells:
    body = SECTIONS[cell['binding']]
    key = cell.get('sourcePrefix') or cell.get('namedRow')
    if key:
        rows = [line for line in body.splitlines() if line.startswith('| ') and key in line.split('|')[1]]
        if rows:
            row = rows[-1]
            row_key = cell['binding'] + ':' + row.split('|')[1].strip()
            row_refs[row_key] = dict(binding=cell['binding'], firstColumn=row.split('|')[1].strip(),
                SHA256=hashlib.sha256(row.encode()).hexdigest())
            cell['rowRef'] = row_key
    cell['inputRef'] = dict(binding=cell['binding'], variant=cell['variant'])
    cell['expectedRef'] = dict(binding=cell['binding'], consumer=cell['consumer'])
    cell['stopRef'] = dict(binding=cell['binding'], row=cell.get('rowRef'),
        observation='Use only linked runtime evidence; otherwise static missing-receipt cause, not reproduced failure.')
    assert body
    if cell.get('sourcePrefix') == 'SRC-DRAFT-GENERAL' and cell['variant']['branch'] in ('STATIONARY', 'A0'):
        cell['expected'] = 'Explicit required-coverage/source-guard failure; never empty success.'
    if cell.get('sourcePrefix') == 'CERT-SPHERECONE-ENDPOINT' and cell['variant'] in ('twoDouble', 'lowerSimpleUpperDouble', 'lowerDoubleUpperSimple'):
        cell['expected'] = ('Complete parent source-pair SSI despite the invalid candidate constructor.' if cell['consumer'] == 'SSI'
            else 'Explicit invalid certified-constructor refusal; not a missing positive capability.')
groups = {suffix: [cell['id'] for cell in cells if cell.get('consumer') == suffix] for suffix in SUFFIXES}
groups['CALLER'] = [cell['id'] for cell in cells if 'CALLER' in cell['id']]
groups['M8'] = interactions
crosswalk = {}
for identifier in accepted:
    group = 'I' if identifier.startswith('5-') else 'B' if identifier.startswith('6-B') else 'S' if identifier.startswith('6-S') else 'M8' if identifier.startswith('6-I') or identifier == 'M8' else 'X' if identifier == 'M7' else 'SSI'
    crosswalk[identifier] = dict(instanceGroup=group, namedContract=identifier)
    assert groups[group]
catalog = dict(schemaVersion=1, baseline='66d02269', authority=str(DESIGN.relative_to(ROOT)),
    acceptedContractIDs=accepted, pcurveCases=pcurves, rollingSelectors=rolling,
    certifiedBranches=CERTIFIED, m0Matrix=m0_rows,
    contractCrosswalk=crosswalk, instanceGroups=groups, rowRefs=row_refs,
    bindingRefs={name: dict(heading=name, SHA256=hashlib.sha256(body.encode()).hexdigest()) for name, body in SECTIONS.items()},
    consumerContracts=REQUESTS, completion=COMPLETION,
    cells=sorted(cells, key=lambda c: (c['implementationOrder'], c['id'])),
    sourceSHA256=hashlib.sha256(TEXT.encode()).hexdigest(),
    ownership='Definitions only. PROGRESS.md alone owns execution and completion state. Static gaps are not reproduced runtime failures. Catalog presence accepts no implementation.')
output = ROOT / 'Tests/OriginalPublicAcceptanceVerification/AcceptanceCells.json'
head = json.dumps({key: value for key, value in catalog.items() if key != 'cells'}, indent=2, ensure_ascii=False)
serialized = head[:-2] + ',\n  \"cells\": [\n' + ',\n'.join('    ' + json.dumps(cell, separators=(',', ':'), ensure_ascii=False) for cell in catalog['cells']) + '\n  ]\n}\n'
assert json.loads(serialized) == json.loads(json.dumps(catalog))
output.write_text(serialized)
print(f'PASS {len(cells)} explicit stable instances; 51 contracts, 17 pcurve cases, {len(rolling)} rolling selectors, five certified families and 12 interactions')
