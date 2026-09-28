//
//  UndoStack.swift
//  Hangly
//
//  Value-type undo and redo.
//

/// Linear undo history over a value.
///
/// The caller owns the current value; the stack holds only what came before and,
/// after an undo, what came after. Recording a new change discards the redo branch,
/// which is the behaviour every editor has and every user expects.
struct UndoStack<Value: Equatable> {
    private(set) var past: [Value] = []
    private(set) var future: [Value] = []

    /// Oldest entries are dropped beyond this.
    var limit = 100

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    /// Call with the value *before* a change is applied.
    mutating func record(_ previous: Value) {
        past.append(previous)
        if past.count > limit {
            past.removeFirst(past.count - limit)
        }
        future.removeAll()
    }

    /// - Parameter current: The value now, which becomes redoable.
    /// - Returns: The value to restore, or `nil` if there is nothing to undo.
    mutating func undo(current: Value) -> Value? {
        guard let previous = past.popLast() else { return nil }
        future.append(current)
        return previous
    }

    mutating func redo(current: Value) -> Value? {
        guard let next = future.popLast() else { return nil }
        past.append(current)
        return next
    }

    mutating func clear() {
        past.removeAll()
        future.removeAll()
    }
}
