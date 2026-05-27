import A2UICore
import A2UIParser

public protocol A2UIAgentStepStream: AsyncSequence, Sendable
where Element == A2UIAgentStep {}
