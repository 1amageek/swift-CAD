from fractions import Fraction as Q
import json
import struct

# Independent rational bounds; no CAD evaluator or regenerated coefficient law.
def atan_bounds(x, terms):
    total = sum(((-1) ** n * x ** (2*n+1) / (2*n+1) for n in range(terms)), Q(0))
    next_term = (-1) ** terms * x ** (2*terms+1) / (2*terms+1)
    return min(total, total+next_term), max(total, total+next_term)

a0,a1 = atan_bounds(Q(1,5),40)
b0,b1 = atan_bounds(Q(1,239),16)
pi0,pi1 = 16*a0-4*b1,16*a1-4*b0
period = Q.from_float(struct.unpack(">d",bytes.fromhex("401921fb54442d18"))[0])
assert 3*pi1/2 < period < 2*pi0
assert Q(1,4) < pi0/(2*period) <= pi1/(2*period) < Q(3,4)
assert Q(3,4) < 3*pi0/(2*period) <= 3*pi1/(2*period) < 1

# Both authored angles lie in these strict rational brackets. Alternating
# sine/cosine bounds give sin(x)<x and cos(x)>1-x*x/2 on these intervals.
alpha0,alpha1 = atan_bounds(Q(1,2),40)
beta0,beta1 = atan_bounds(Q(3,8),40)
assert Q(46,100) < alpha0 < alpha1 < Q(47,100)
assert Q(35,100) < beta0 < beta1 < Q(37,100)
alpha_max,beta_max = Q(47,100),Q(37,100)
cos_alpha_min = 1-alpha_max*alpha_max/2
sphere_linear_abs_min = 4*cos_alpha_min-alpha_max
assert sphere_linear_abs_min > 0
assert sphere_linear_abs_min**2-8 > 0

q_min = cos_alpha_min**2-beta_max**2
b_max = 4*alpha_max**2*beta_max
k_abs_max = 16*alpha_max**2
assert q_min > Q(13,20)
assert b_max < Q(1,3)
assert k_abs_max < Q(18,5)
# q<=1, so sqrt(b*b-q*k)<2 and both parameterized slants are bounded.
assert Q(1,3)**2+Q(18,5) < 4
slant_abs_max = (Q(1,3)+2)/Q(13,20)
reference_z_min = 4-beta_max*slant_abs_max
assert reference_z_min > 0
print(json.dumps({
 "scope":"Independent full-branch oracle guard/root-domain bounds only; no CAD acceptance",
 "periodBits":"401921fb54442d18",
 "periodStrictlyBelowMathematicalFullTurn":True,
 "sphereDiscriminantLowerBound":str(sphere_linear_abs_min**2-8),
 "coneQuadraticLowerBound":str(q_min),
 "referenceConeZLowerBound":str(reference_z_min),
 "reversedQuarterSubcurveIncludesOnlyFirstPhysicalRoot":True
},indent=2))
