//
//  EditAction.swift
//  Videographics
//

import Foundation

/// Protocol defining an undoable/redoable edit action
@MainActor
protocol EditAction: AnyObject {
    /// Human-readable description of the action for UI display
    var actionDescription: String { get }

    /// Execute the action (or re-execute for redo)
    func execute()

    /// Undo the action
    func undo()
}
