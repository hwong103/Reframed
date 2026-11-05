struct LocalMCPListenerGeneration {
  private(set) var current: UInt64 = 0

  mutating func begin() -> UInt64 {
    current &+= 1
    return current
  }

  mutating func invalidate() {
    current &+= 1
  }

  func accepts(_ generation: UInt64) -> Bool {
    generation == current
  }
}
