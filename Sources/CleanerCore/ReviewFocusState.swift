import Foundation

public struct ReviewFocusState: Equatable, Sendable {
    public private(set) var focusedCandidateID: UUID?

    public init(focusedCandidateID: UUID? = nil) {
        self.focusedCandidateID = focusedCandidateID
    }

    public mutating func focus(_ candidateID: UUID?, visibleIDs: [UUID]) {
        focusedCandidateID = candidateID
        reconcile(visibleIDs: visibleIDs)
    }

    public mutating func reconcile(visibleIDs: [UUID]) {
        guard let first = visibleIDs.first else {
            focusedCandidateID = nil
            return
        }
        if focusedCandidateID.map({ visibleIDs.contains($0) }) != true {
            focusedCandidateID = first
        }
    }
}
