//
//  UndoableDeleteHandler.swift
//  ClimbingProgram
//
//  Created by Shahar Noy on 07.10.25.
//

import Foundation
import SwiftData

public protocol UndoIdentifiable {
    associatedtype ID: Hashable
    var id: ID { get }
}

public protocol UndoSnapshotting {
    associatedtype Item: UndoIdentifiable & PersistentModel
    func makeSnapshot(from item: Item) -> Any
    @MainActor func restore(from snapshot: Any, into context: ModelContext) throws
    @MainActor func fetchByID(_ id: Item.ID, in context: ModelContext) throws -> Item?
}

@MainActor
public struct UndoableDeleteHandler<S: UndoSnapshotting> {
    private let snapshotter: S
    private weak var undoManager: UndoManager?
    private weak var context: ModelContext?

    private var lastDeletedID: S.Item.ID?
    private var lastSnapshot: Any?

    public init(snapshotter: S) {
        self.snapshotter = snapshotter
    }

    public mutating func attach(context: ModelContext, undoManager: UndoManager?) {
        self.context = context
        let assigned = undoManager ?? UndoManager()
        context.undoManager = assigned
        self.undoManager = assigned
    }

    public mutating func delete(_ item: S.Item, actionName: String = "Delete") {
        guard let context else { return }
        if context.undoManager == nil {
            let assigned = undoManager ?? UndoManager()
            context.undoManager = assigned
        }

        undoManager?.beginUndoGrouping()
        undoManager?.setActionName(actionName)

        lastDeletedID = item.id
        lastSnapshot = snapshotter.makeSnapshot(from: item)

        context.delete(item)
        undoManager?.endUndoGrouping()

        do { try context.save() } catch { }
    }

    public func performUndoAndEnsureRestore() {
        guard let context else { return }

        guard let snap = lastSnapshot else { return }

        do {
            try snapshotter.restore(from: snap, into: context)
            try context.save()
        } catch {
            print("Undo restore failed: \(error)")
        }
    }
}
