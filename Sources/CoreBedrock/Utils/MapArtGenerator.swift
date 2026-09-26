//
// Created by yechentide on 2025/11/21
//

public import CoreGraphics
public import Foundation

public typealias MapArtGenerationEvent = CBOperationEvent<MapArtGenerationProgress, Never, Never, Never>

public enum MapArtGenerationProgress: Sendable {
    case splittingImage(processedTileCount: Int, totalTileCount: Int)
    case allocatingMapIDs(allocatedCount: Int, totalCount: Int)
    case generatingMapData(processedMapCount: Int, totalMapCount: Int)
    case savingMapData(savedMapCount: Int, totalMapCount: Int)
    case injectingItem
}

public enum MapArtGenerator {
    private static let tileSize = 128

    /// Generates map art from an image, packs the maps into a shulker box,
    /// and inserts it into the specified player's inventory.
    /// Reports progress via an AsyncThrowingStream of MapArtGenerationEvent.
    ///
    /// - Parameters:
    ///   - database: The level database used to store generated map data
    ///   - image: The source image to convert into map art
    ///   - playerKey: The database key identifying the target player
    ///   - shulkerBoxName: Optional custom name for the shulker box containing the maps
    public static func generateAndGiveToPlayer(
        database: any KeyValueStore,
        image: CGImage,
        playerKey: Data,
        shulkerBoxName: String? = nil
    ) -> AsyncThrowingStream<MapArtGenerationEvent, any Error> {
        let (stream, continuation) = AsyncThrowingStream<MapArtGenerationEvent, any Error>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let database = database
        let task = Task {
            do {
                try self.run(
                    database: database,
                    image: image,
                    playerKey: playerKey,
                    shulkerBoxName: shulkerBoxName,
                    report: { continuation.yield(.progress($0)) }
                )
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
        return stream
    }

    // MARK: - Private workers

    private static func run(
        database: any KeyValueStore,
        image: CGImage,
        playerKey: Data,
        shulkerBoxName: String?,
        report: @Sendable @escaping (MapArtGenerationProgress) -> Void
    ) throws {
        let tilesX = (image.width + self.tileSize - 1) / self.tileSize
        let tilesY = (image.height + self.tileSize - 1) / self.tileSize
        let totalMapCount = tilesX * tilesY
        let mapIDs = try allocateMapIDs(in: database, count: totalMapCount, report: report)
        var mapItems = [CompoundTag]()
        var writtenKeys = [LvDBKey]()
        do {
            for index in 0..<totalMapCount {
                try Task.checkCancellation()
                try autoreleasepool {
                    let bytes = try tileBytes(image: image, x: index % tilesX, y: index / tilesX)
                    report(.splittingImage(processedTileCount: index + 1, totalTileCount: totalMapCount))
                    let mapData = try generateMapDataTag(id: mapIDs[index], bytes: bytes)
                    let lvdbKey = LvDBKey.map(mapIDs[index])
                    let entryData = try mapData.toData()
                    report(.generatingMapData(processedMapCount: index + 1, totalMapCount: totalMapCount))
                    try database.putData(entryData, forKey: lvdbKey.data)
                    writtenKeys.append(lvdbKey)
                    try mapItems.append(ItemGenerator.generate(ItemGenerator.ItemMeta.map(
                        slot: 0, mapID: mapIDs[index], name: "Map [\(index + 1)/\(totalMapCount)]"
                    )))
                }
                report(.savingMapData(savedMapCount: index + 1, totalMapCount: totalMapCount))
            }
            try Task.checkCancellation()
            report(.injectingItem)
            let shulkerBox = try ShulkerNestingPacker.pack(items: mapItems, rootName: shulkerBoxName)
            try ItemInjector.giveItemToPlayer(item: shulkerBox, playerKey: playerKey, in: database)
        } catch is CancellationError {
            for lvdbKey in writtenKeys {
                try? autoreleasepool {
                    try database.removeValue(forKey: lvdbKey.data)
                }
            }
            throw CancellationError()
        } catch {
            for lvdbKey in writtenKeys {
                try? autoreleasepool {
                    try database.removeValue(forKey: lvdbKey.data)
                }
            }
            throw CBError.failedToSaveMapDataTag
        }
    }

    static func tileBytes(image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: tileSize * self.tileSize * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: tileSize, height: tileSize,
                bitsPerComponent: 8, bytesPerRow: tileSize * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { throw CBError.failedCreateImageContext }

            // The old full-image bitmap was traversed from its first row.
            // Translation preserves that ordering, including transparent edge padding.
            context.translateBy(
                x: CGFloat(-x * self.tileSize),
                y: CGFloat(self.tileSize - image.height + y * self.tileSize)
            )
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }

    private static func generateMapDataTag(id: Int64, bytes: [UInt8]) throws -> CompoundTag {
        try CompoundTag([
            LongTag(name: "mapId", id),
            LongTag(name: "parentMapId", -1),
            ByteArrayTag(name: "colors", bytes),
            ByteTag(name: "dimension", UInt8.max),
            IntTag(name: "xCenter", 0),
            IntTag(name: "zCenter", 0),
            ShortTag(name: "width", 128),
            ShortTag(name: "height", 128),
            ByteTag(name: "scale", 4),
            ByteTag(name: "fullyExplored", 1),
            ByteTag(name: "mapLocked", 1),
            ByteTag(name: "unlimitedTracking", 0),
        ])
    }

    private static func allocateMapIDs(
        in database: any KeyValueStore,
        count: Int,
        report: @Sendable @escaping (MapArtGenerationProgress) -> Void
    ) throws -> [Int64] {
        let iter = try database.makeIterator()
        iter.moveToFirst()
        defer {
            iter.close()
        }
        var currentID: Int64 = 0
        var ids = [Int64]()

        while ids.count < count {
            try Task.checkCancellation()
            let keyData = LvDBKey.map(currentID).data
            iter.move(to: keyData)
            if !(iter.isValid && iter.currentKey == keyData) {
                ids.append(currentID)
                report(.allocatingMapIDs(allocatedCount: ids.count, totalCount: count))
            }
            currentID += 1

            // Safety check to prevent infinite loop
            guard currentID < Int64.max - 1000 else {
                throw CBError.failedToAllocateMapIDs
            }
        }

        guard ids.count == count else {
            throw CBError.failedToAllocateMapIDs
        }

        return ids
    }
}
