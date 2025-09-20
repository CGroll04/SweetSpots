//
//  Firestore+Extensions.swift
//  SweetSpots
//
//  Created by Charlie Groll on 2025-09-11.
//

import SwiftUI
import FirebaseFirestore


enum FirestoreWrapperError: Error, LocalizedError {
    case unexpectedNilReference
    
    var errorDescription: String? {
        "An unexpected error occurred while communicating with the database."
    }
}

extension CollectionReference {
    /// A modern async/await wrapper for adding a document that correctly handles all error paths.
    @discardableResult
    func addDocument<T: Encodable>(from data: T) async throws -> DocumentReference {
        try await withCheckedThrowingContinuation { continuation in
            var ref: DocumentReference?
            
            do {
                // The call to addDocument(from:completion:) can itself throw an
                // encoding error, so we must wrap it in a `do-catch`.
                ref = try self.addDocument(from: data) { error in
                    if let error = error {
                        // This handles network errors from the completion handler.
                        continuation.resume(throwing: error)
                    } else if let ref = ref {
                        // This handles the success case.
                        continuation.resume(returning: ref)
                    } else {
                        // This handles the unlikely case of no error and no reference.
                        continuation.resume(throwing: FirestoreWrapperError.unexpectedNilReference)
                    }
                }
            } catch {
                // This handles encoding errors thrown synchronously by `addDocument`.
                continuation.resume(throwing: error)
            }
        }
    }
}
