#!/usr/bin/env python3
"""Exact rational proof for both cone coefficient interpretations; no libm or curve samples."""
from fractions import Fraction as F
from math import factorial
from pathlib import Path
import hashlib
import json
import sys

HERE = Path(__file__).resolve().parent
PRIOR = HERE.parent / 'cert-spherecone-apex-height-scalar-20261012' / 'worksheet.json'
prior_bytes = PRIOR.read_bytes()
prior_sha = hashlib.sha256(prior_bytes).hexdigest()
assert prior_sha == 'e701c73185f341a3c6ea379dc9dac4d91e25e52ffe020d959a2ab160602d603a'
prior = json.loads(prior_bytes)
alpha = F(522020799781813, 1125899906842624)
assert 0 < alpha < F(1, 2)
assert str(alpha) == prior['coefficientImport']['alpha']['exactRational']

# For 0 < alpha < 1/2, successive absolute Taylor terms strictly decrease to zero.
# The alternating-series remainder gives these exact closed lower/upper bounds.
sin_lower = alpha - alpha**3/F(factorial(3)) + alpha**5/F(factorial(5)) - alpha**7/F(factorial(7))
sin_upper = alpha - alpha**3/F(factorial(3)) + alpha**5/F(factorial(5))
cos_lower = 1 - alpha**2/F(factorial(2)) + alpha**4/F(factorial(4)) - alpha**6/F(factorial(6))
cos_upper = 1 - alpha**2/F(factorial(2)) + alpha**4/F(factorial(4))
assert 0 < sin_lower < sin_upper and 0 < cos_lower < cos_upper
# Use tan = sin/cos only to bound the mathematical coefficient, never to cancel height factors.
tan_lower, tan_upper = sin_lower/cos_upper, sin_upper/cos_lower
A_lower, A_upper = 1 + tan_lower**2, 1 + tan_upper**2
values = dict(sine=(sin_lower, sin_upper, F(7,16), F(15,32)),
              cosine=(cos_lower, cos_upper, F(7,8), F(29,32)),
              slope=(tan_lower, tan_upper, F(31,64), F(33,64)),
              quadraticA=(A_lower, A_upper, F(79,64), F(81,64)))
proofs = {}
for key, (lower, upper, box_lower, box_upper) in values.items():
    assert box_lower < lower <= upper < box_upper
    actual = F(prior['coefficientImport'][key]['exactRational'])
    assert box_lower <= actual <= box_upper
    proofs[key] = dict(taylorLower=str(lower), taylorUpper=str(upper),
        box=[str(box_lower), str(box_upper)],
        strictLowerMargin=str(lower-box_lower), strictUpperMargin=str(box_upper-upper),
        importedBinaryCoefficient=str(actual), bothMeaningsContained=True)

c_min, c_max = F(7,8), F(29,32)
k_max, A_min = F(33,64), F(79,64)
assert A_min*c_min > 0
exact_basis_upper = c_max*2*k_max*F(1)/(A_min*c_min)
generous_basis_upper = c_max*2*k_max*(F(1,64)+F(65,64))/(A_min*c_min)
assert exact_basis_upper == F(957,1106) < 1
assert generous_basis_upper == F(31581,35392) < 1

# Import a positive finite binary64 value exactly from bits, without floating arithmetic.
def positive_binary64(bits):
    word = int(bits, 16)
    assert word >> 63 == 0
    exponent, significand = ((word >> 52) & 2047)-1023-52, (word & ((1 << 52)-1))+(1 << 52)
    return F(significand*(1 << exponent), 1) if exponent >= 0 else F(significand, 1 << -exponent)

prior_outward_upper = positive_binary64(prior['independentRationalBoxHeightInterval']['upperBits'])
common_upper = F(15,16)
assert generous_basis_upper < common_upper
assert prior_outward_upper < common_upper < 1 < 2
out = dict(cell='CS-CERT-SPHERECONE-APEX-EMPTY-01',
    exactStoredAlpha=str(alpha), alphaBits='3fddac670561bb50',
    premise='0 < alpha < 1/2; each absolute Taylor term ratio is alpha^2/((n+1)*(n+2)) < 1, and terms tend to zero. Alternating-series remainders enclose mathematical sin(alpha), cos(alpha).',
    TaylorPolynomials=dict(sinLower='x-x^3/3!+x^5/5!-x^7/7!',sinUpper='x-x^3/3!+x^5/5!',
        cosLower='1-x^2/2!+x^4/4!-x^6/6!',cosUpper='1-x^2/2!+x^4/4!'),
    coefficientBounds=proofs,
    wholeAngleHeightFormula='B=a+k*(rc*cos(theta)+rs*sin(theta)); z=c*(2*B/(A*c)); a=0; theta arbitrary real.',
    boundRule='abs(z) <= c_max*2*k_max*(abs(rc)_max+abs(rs)_max)/(A_min*c_min), with independently bounded numerator/denominator c; no source-factor cancellation.',
    exactBasis=dict(rc='0',rs='1',heightUpper=str(exact_basis_upper),gapToOne=str(1-exact_basis_upper)),
    generousBasis=dict(absRcMax='1/64',absRsMax='65/64',heightUpper=str(generous_basis_upper),gapToOne=str(1-generous_basis_upper)),
    frozenBinaryOutwardUpper=str(prior_outward_upper),commonStrictHeightUpper=str(common_upper),
    conclusion='Both interpretations exclude plane Z=2 over every closed T in [0,1], independently of sphere membership and source UV reconstruction. Every requested tuple, root, overlap, image, fiber and incident set is empty.',
    priorWorksheet=dict(path=str(PRIOR),sha256=prior_sha),
    calculation=dict(language='Python Fraction integer/rational arithmetic only',python=sys.version,
        worksheetSourceSHA256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        curvePointSamples=0,libmCalls=0,CADBuilds=0,CADRuntimeCalls=0),
    remaining='Actual public source/domain exclusion receipt consumption and ordinary CS runtime remain UNOBSERVED/open.')
(HERE/'worksheet.json').write_text(json.dumps(out, indent=2)+'\n')
print('allCoefficientContainmentChecks=True')
print('exactBasisHeightUpper='+str(exact_basis_upper))
print('generousBasisHeightUpper='+str(generous_basis_upper))
print('frozenBinaryOutwardUpper='+str(prior_outward_upper))
print('commonStrictHeightUpper='+str(common_upper)+' < 1 < 2')
