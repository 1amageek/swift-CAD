import L0
import IssuedGraphs
@testable import GraphFixtures
@main struct LedgerProbe {
static func main() {
do { _ = try GraphFixtures.makeParameterRefinement(); print("PASS make") } catch { describe(error) }
do { try GraphFixtures.parameterRefinement(); print("PASS wrapper") } catch { describe(error) }
}
nonisolated static func describe(_ error: any Error) {
if let n = error as? NativeExactRelationFailure {
switch n { case .scalar(let s): print("NATIVE SCALAR"); describe(s)
case .geometry(let e): print("GEOMETRY"); describe(e)
case .invalidDomain: print("INVALID DOMAIN")
case .domain: print("DOMAIN")
default: print("OTHER NATIVE") }
} else if let s = error as? ExactScalarFailure {
switch s { case .cancelled: print("CANCELLED")
case .resourceLimit(let resource): print("RESOURCE"); switch resource { case .work: print("WORK"); case .storage: print("STORAGE"); case .valueDepth: print("DEPTH"); default: print("OTHER RESOURCE") }
default: print("OTHER SCALAR") }
} else if let f = error as? GraphFixtures.Failure {
if case .incorrect(let line) = f { print("ASSERTION"); print(line) }
} else { print("OTHER ERROR") }
}
}
