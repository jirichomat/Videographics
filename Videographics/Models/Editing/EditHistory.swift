//
//  EditHistory.swift
//  Videographics
//

import Foundation

/// Manages undo/redo stacks for edit actions
@MainActor
@Observable
class EditHistory {
    /// Maximum number of undo levels to keep
    private let maxUndoLevels = 50

    /// Stack of actions that can be undone
    private var undoStack: [EditAction] = []

    /// Stack of actions that can be redone
    private var redoStack: [EditAction] = []

    /// Callback triggered when history changes (for rebuilding composition)
    var onHistoryChanged: (() -> Void)?

    /// Whether there are actions that can be undone
    var canUndo: Bool {
        !undoStack.isEmpty
    }

    /// Whether there are actions that can be redone
    var canRedo: Bool {
        !redoStack.isEmpty
    }

    /// Description of the action that would be undone
    var undoActionDescription: String? {
        undoStack.last?.actionDescription
    }

    /// Description of the action that would be redone
    var redoActionDescription: String? {
        redoStack.last?.actionDescription
    }

    /// Execute an action and add it to the undo stack
    /// - Parameter action: The action to perform
    func perform(_ action: EditAction) {
        action.execute()
        record(action)
    }

    /// Record an already-executed action to the undo stack
    /// Use this when the action was performed directly (e.g., during drag/trim)
    /// - Parameter action: The action that was already executed
    func record(_ action: EditAction) {
        undoStack.append(action)

        // Clear redo stack when new action is performed
        redoStack.removeAll()

        // Limit undo stack size
        if undoStack.count > maxUndoLevels {
            undoStack.removeFirst()
        }

        onHistoryChanged?()
    }

    /// Undo the most recent action
    func undo() {
        guard let action = undoStack.popLast() else { return }

        action.undo()
        redoStack.append(action)

        onHistoryChanged?()
    }

    /// Redo the most recently undone action
    func redo() {
        guard let action = redoStack.popLast() else { return }

        action.execute()
        undoStack.append(action)

        onHistoryChanged?()
    }

    /// Clear all history (call when switching projects)
    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
