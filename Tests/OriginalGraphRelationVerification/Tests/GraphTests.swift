import Testing
import GraphFixtures
@Test(.serialized,.timeLimit(.minutes(1)),arguments:0..<6)
func issuedGraphRelations(_ mode:Int) throws { try GraphFixtures.run(mode) }
