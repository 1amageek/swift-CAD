#if L4_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

struct ExactTopologyCounts {
 var generated = 0
 var closures = 0
 var pieces = 0
 var depth: ExactScalarDepth
 mutating func retain<A: ExactScalarAdmission & ~Copyable>(_ other: ExactScalarDepth, _ a: inout A) throws {
  depth = try .init(value:max(depth.value,other.value),coefficient:max(depth.coefficient,other.coefficient))
  try a.admitDepth(value:depth.value,coefficient:depth.coefficient)
 }
}
