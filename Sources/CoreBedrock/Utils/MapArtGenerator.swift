//
// Created by yechentide on 2025/11/21
//

import CoreGraphics

public enum MapArtGenerator {
    private static let tileSize = 128

    /// Generates map art from an image and places it in a shulker box chest at the specified location.
    /// - Parameters:
    ///   - database: The level database to store map data and chest
    ///   - image: The source image to convert to map art
    ///   - x: X coordinate for the chest placement
    ///   - y: Y coordinate for the chest placement
    ///   - z: Z coordinate for the chest placement
    ///   - shulkerBoxName: Optional name for the shulker box containing maps
    /// - Throws: If image processing, map data generation, or placement fails
    public static func generateAndPlace(
        database: LevelKeyValueStore,
        image: CGImage,
        x: Int32,
        y: Int32,
        z: Int32,
        shulkerBoxName: String? = nil
    ) throws {
        let (mapItems, mapDataDict) = try buildMapItemsAndData(image: image, database: database)

        do {
            for (lvdbKey, mapData) in mapDataDict {
                let entryData = try mapData.toData()
                try database.putData(entryData, forKey: lvdbKey.data)
            }
            let shulkerBox = try ShulkerNestingPacker.pack(items: mapItems, rootName: shulkerBoxName)
            try ChestEntityGenerator.place(database: database, x: x, y: y, z: z, items: [shulkerBox])
        } catch {
            // Rollback map data on failure
            for lvdbKey in mapDataDict.keys {
                try? database.removeValue(forKey: lvdbKey.data)
            }
            throw CBError.failedToSaveMapDataTag
        }
    }

    /// Builds map items and data from an image.
    /// - Parameters:
    ///   - image: The source image to convert
    ///   - database: The database to allocate map IDs from
    /// - Returns: A tuple containing map item tags and a dictionary of map data tags keyed by LvDBKey
    /// - Throws: If image processing or map generation fails
    private static func buildMapItemsAndData(
        image: CGImage,
        database: LevelKeyValueStore
    ) throws -> (items: [CompoundTag], data: [LvDBKey: CompoundTag]) {
        var mapItemTagList = [CompoundTag]()
        var mapDataTagDict = [LvDBKey: CompoundTag]()

        try autoreleasepool {
            let tiles = try split(image: image)
            let mapIDList = try allocateMapIDs(in: database, count: tiles.count)

            for (index, tilePixels) in tiles.enumerated() {
                let mapID = mapIDList[index]
                let mapDataTag = try generateMapDataTag(id: mapID, from: tilePixels)
                let mapItemTag = try ItemGenerator.generate(ItemGenerator.ItemMeta.map(
                    slot: 0, mapID: mapID, name: "Map [\(index + 1)/\(tiles.count)]"
                ))
                mapItemTagList.append(mapItemTag)
                mapDataTagDict[LvDBKey.map(mapID)] = mapDataTag
            }
        }

        return (mapItemTagList, mapDataTagDict)
    }

    /// Generates a map data tag from pixel data.
    /// - Parameters:
    ///   - id: The map ID
    ///   - pixels: Array of CGColor pixel data
    /// - Returns: A CompoundTag representing the map data
    /// - Throws: If tag creation fails
    private static func generateMapDataTag(id: Int64, from pixels: [CGColor]) throws -> CompoundTag {
        var bytes = [UInt8]()
        bytes.reserveCapacity(pixels.count * 4)
        for color in pixels {
            guard let components = color.components else {
                bytes.append(contentsOf: [0, 0, 0, 0])
                continue
            }

            let r = UInt8((!components.isEmpty ? components[0] : 0) * 255)
            let g = UInt8((components.count > 1 ? components[1] : 0) * 255)
            let b = UInt8((components.count > 2 ? components[2] : 0) * 255)
            let a = UInt8((components.count > 3 ? components[3] : 1) * 255)

            bytes.append(r)
            bytes.append(g)
            bytes.append(b)
            bytes.append(a)
        }
        return try CompoundTag([
            LongTag(name: "mapId", id),
            LongTag(name: "parentMapId", -1),
            ByteArrayTag(name: "colors", bytes),
            ByteTag(name: "dimension", 0),
            IntTag(name: "xCenter", 0),
            IntTag(name: "zCenter", 0),
            ShortTag(name: "width", 0),
            ShortTag(name: "height", 0),
            ByteTag(name: "scale", 4),
            ByteTag(name: "fullyExplored", 1),
            ByteTag(name: "mapLocked", 1),
            ByteTag(name: "unlimitedTracking", 0),
        ])
    }

    /// Allocates available map IDs from the database.
    /// - Parameters:
    ///   - database: The database to check for existing map IDs
    ///   - count: Number of map IDs to allocate
    /// - Returns: Array of allocated map IDs
    /// - Throws: If unable to allocate the requested number of IDs
    private static func allocateMapIDs(in database: LevelKeyValueStore, count: Int) throws -> [Int64] {
        let iter = try database.makeIterator()
        defer {
            iter.close()
        }
        var currentID: Int64 = 0
        var ids = [Int64]()

        while ids.count < count {
            let keyData = LvDBKey.map(currentID).data
            iter.move(to: keyData)
            if iter.currentKey != keyData {
                ids.append(currentID)
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

    /// Splits an image into tiles for map art generation.
    /// - Parameter image: The image to split
    /// - Returns: Array of tile pixel data, where each tile is an array of CGColor
    /// - Throws: If image context creation fails
    private static func split(image: CGImage) throws -> [[CGColor]] {
        // Calculate number of tiles needed (round up)
        let rgbSpace = CGColorSpaceCreateDeviceRGB()
        let tilesX = (image.width + self.tileSize - 1) / self.tileSize
        let tilesY = (image.height + self.tileSize - 1) / self.tileSize

        var tiles: [[CGColor]] = []

        // Create context to read pixel data
        let bytesPerPixel = 4
        var pixelData = [UInt8](repeating: 0, count: image.width * image.height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerPixel * image.width,
            space: rgbSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CBError.failedCreateImageContext
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        // Process each tile
        for tileY in 0..<tilesY {
            for tileX in 0..<tilesX {
                var tilePixels: [CGColor] = []
                tilePixels.reserveCapacity(self.tileSize * self.tileSize)

                // Process each pixel in the tile
                for y in 0..<self.tileSize {
                    for x in 0..<self.tileSize {
                        let sourceX = tileX * self.tileSize + x
                        let sourceY = tileY * self.tileSize + y

                        if sourceX < image.width, sourceY < image.height {
                            let pixelIndex = (sourceY * image.width + sourceX) * bytesPerPixel

                            // Convert UInt8 → CGFloat (0–1)
                            let r = CGFloat(pixelData[pixelIndex]) / 255.0
                            let g = CGFloat(pixelData[pixelIndex + 1]) / 255.0
                            let b = CGFloat(pixelData[pixelIndex + 2]) / 255.0
                            let a = CGFloat(pixelData[pixelIndex + 3]) / 255.0

                            if let color = CGColor(colorSpace: rgbSpace, components: [r, g, b, a]) {
                                tilePixels.append(color)
                            }
                        } else {
                            // Padding: transparent
                            if let color = CGColor(colorSpace: rgbSpace, components: [0, 0, 0, 0]) {
                                tilePixels.append(color)
                            }
                        }
                    }
                }

                tiles.append(tilePixels)
            }
        }

        return tiles
    }
}
