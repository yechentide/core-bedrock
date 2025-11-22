//
// Created by yechentide on 2025/11/21
//

import LvDBWrapper

public enum DimensionTransfer {
    /// Transfer mode for dimension data
    public enum TransferMode: CaseIterable, Sendable {
        /// Delete all target keys for dimension, then write all source keys
        case override
        /// Copy only keys that do not exist in target
        case skipExisting
        /// Put each key (overwrite or add)
        case replacePerKey
    }

    private static let batchThreshold = 512

    /// Transfers dimension data from source to target database.
    /// - Parameters:
    ///   - source: Source database to read from
    ///   - target: Target database to write to
    ///   - dimension: Dimension to transfer
    ///   - mode: Transfer mode controlling how keys are handled
    /// - Throws: If database operations fail
    public static func transfer(
        from source: LevelKeyValueStore,
        to target: LevelKeyValueStore,
        dimension: MCDimension,
        mode: TransferMode
    ) throws {
        switch mode {
        case .override:
            try self.deleteTargetDimensionKeys(target: target, dimension: dimension)
            try self.copyKeys(from: source, to: target, dimension: dimension, mode: .replacePerKey)
        case .skipExisting:
            try self.copyKeys(from: source, to: target, dimension: dimension, mode: .skipExisting)
        case .replacePerKey:
            try self.copyKeys(from: source, to: target, dimension: dimension, mode: .replacePerKey)
        }
    }

    /// Deletes all keys for the specified dimension from the target database.
    /// - Parameters:
    ///   - target: Target database to delete keys from
    ///   - dimension: Dimension to delete keys for
    /// - Throws: If database operations fail
    private static func deleteTargetDimensionKeys(
        target: LevelKeyValueStore,
        dimension: MCDimension
    ) throws {
        let iter = try target.makeIterator()
        defer { iter.close() }

        let batch = LvDBWriteBatch()
        var batchCount = 0

        iter.moveToFirst()
        while iter.isValid {
            guard let keyData = iter.currentKey else {
                iter.moveToNext()
                continue
            }

            let parsedKey = LvDBKey.parse(data: keyData)
            if case let .subChunk(_, _, dim, _, _) = parsedKey, dim == dimension {
                batch.remove(keyData)
                batchCount += 1

                if batchCount >= self.batchThreshold {
                    try target.writeBatch(batch)
                    batch.clear()
                    batchCount = 0
                }
            }

            iter.moveToNext()
        }

        // Flush remaining operations
        if batchCount > 0 {
            try target.writeBatch(batch)
        }
    }

    /// Copies dimension keys from source to target database.
    /// - Parameters:
    ///   - source: Source database to read from
    ///   - target: Target database to write to
    ///   - dimension: Dimension to copy keys for
    ///   - mode: Transfer mode (skipExisting or replacePerKey)
    /// - Throws: If database operations fail
    private static func copyKeys(
        from source: LevelKeyValueStore,
        to target: LevelKeyValueStore,
        dimension: MCDimension,
        mode: TransferMode
    ) throws {
        let iter = try source.makeIterator()
        defer { iter.close() }

        let batch = LvDBWriteBatch()
        var batchCount = 0

        iter.moveToFirst()
        while iter.isValid {
            guard let keyData = iter.currentKey,
                  let valueData = iter.currentValue else {
                iter.moveToNext()
                continue
            }

            let parsedKey = LvDBKey.parse(data: keyData)

            // Filter for dimension keys
            let shouldProcess: Bool = if case let .subChunk(_, _, dim, _, _) = parsedKey {
                dim == dimension
            } else {
                // Unknown or non-subChunk keys are skipped
                false
            }

            if shouldProcess {
                // Check if we should skip based on mode
                let shouldWrite: Bool = switch mode {
                case .skipExisting:
                    !target.containsKey(keyData)
                case .replacePerKey, .override:
                    true
                }

                if shouldWrite {
                    batch.put(keyData, value: valueData)
                    batchCount += 1

                    if batchCount >= self.batchThreshold {
                        try target.writeBatch(batch)
                        batch.clear()
                        batchCount = 0
                    }
                }
            }

            iter.moveToNext()
        }

        // Flush remaining operations
        if batchCount > 0 {
            try target.writeBatch(batch)
        }
    }
}
