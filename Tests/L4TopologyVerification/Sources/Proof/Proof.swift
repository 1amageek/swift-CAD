import L4Fixtures
@main struct L4Proof {
 static func main() throws {
  try TopologyFixtures.folded()
  try TopologyFixtures.affineClosures()
  try TopologyFixtures.quantifiedClosure()
  try TopologyFixtures.graphClosure()
  try TopologyFixtures.zeroAndFailures()
  try TopologyFixtures.connectivity()
  try TopologyFixtures.partialTarget()
  try TopologyFixtures.singularComponents()
  try TopologyFixtures.partialIncidence()
  try LifecycleFixtures.retained()
  try LifecycleFixtures.resourcesAndCancellation()
  try TopologyFixtures.closeDistinctPoints()
  print("PASS: independent L4 topology")
 }
}
