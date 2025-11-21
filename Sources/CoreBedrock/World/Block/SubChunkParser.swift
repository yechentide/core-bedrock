//
// Created by yechentide on 2025/09/18
//

import Foundation

// enum PaletteMetaType: UInt8 {
//     case persistence = 0
//     case runtime = 1
// }

// swiftlint:disable line_length
/*
 Decode sub chunk data

 ref.
 - [Block Protocol in Beta 1.2.13](https://gist.github.com/Tomcc/a96af509e275b1af483b25c543cfbf37)
 - [Bedrock Edition level format](https://minecraft.fandom.com/wiki/Bedrock_Edition_level_format/History#LevelDB_based_format)
 */
// swiftlint:enable line_length

public struct SubChunkParser {
    private let binaryReader: CBBinaryReader
    private let chunkY: Int8

    public init(data: Data, chunkY: Int8) {
        self.binaryReader = CBBinaryReader(data: data)
        self.chunkY = chunkY
    }

    public func parsePackedLayer() throws -> PackedSubChunk? {
        let storageVersion = try binaryReader.readUInt8()
        return switch storageVersion {
        case 9: try self.parseV9Packed()
        case 8: try self.parseV8Packed()
        default: nil
        }
    }

    private func parseV9Packed() throws -> PackedSubChunk? {
        let layerCount = try binaryReader.readUInt8()
        let chunkY = try binaryReader.readInt8()
        guard chunkY == self.chunkY, layerCount > 0 else {
            return nil
        }

        let (blockIndicesData, blockBitWidth, _) = try binaryReader.readIndicesData()
        let blockPalette = try binaryReader.readBlockPalette()
        guard !blockPalette.isEmpty, !blockIndicesData.isEmpty else {
            return nil
        }
        guard layerCount > 1 else {
            return .init(
                version: 9,
                chunkY: self.chunkY,
                blockLayer: .init(
                    bitWidth: blockBitWidth,
                    palette: blockPalette,
                    indicesBytes: blockIndicesData
                ),
                liquidLayer: nil
            )
        }

        var liquidBitWidth = 1
        var liquidPalette: [CompoundTag] = []
        var liquidIndicesData: [UInt8] = []
        if layerCount > 1 {
            (liquidIndicesData, liquidBitWidth, _) = try self.binaryReader.readIndicesData()
            liquidPalette = try self.binaryReader.readBlockPalette()
            guard !liquidPalette.isEmpty, !liquidIndicesData.isEmpty else {
                return nil
            }
        }

        return .init(
            version: 9,
            chunkY: self.chunkY,
            blockLayer: .init(
                bitWidth: blockBitWidth,
                palette: blockPalette,
                indicesBytes: blockIndicesData
            ),
            liquidLayer: .init(
                bitWidth: liquidBitWidth,
                palette: liquidPalette,
                indicesBytes: liquidIndicesData
            )
        )
    }

    private func parseV8Packed() throws -> PackedSubChunk? {
        let layerCount = try binaryReader.readUInt8()
        guard layerCount > 0 else {
            return nil
        }

        let (blockIndicesData, blockBitWidth, _) = try binaryReader.readIndicesData()
        let blockPalette = try binaryReader.readBlockPalette()
        guard !blockPalette.isEmpty, !blockIndicesData.isEmpty else {
            return nil
        }
        guard layerCount > 1 else {
            return .init(
                version: 9,
                chunkY: self.chunkY,
                blockLayer: .init(
                    bitWidth: blockBitWidth,
                    palette: blockPalette,
                    indicesBytes: blockIndicesData
                ),
                liquidLayer: nil
            )
        }

        var liquidBitWidth = 1
        var liquidPalette: [CompoundTag] = []
        var liquidIndicesData: [UInt8] = []
        if layerCount > 1 {
            (liquidIndicesData, liquidBitWidth, _) = try self.binaryReader.readIndicesData()
            liquidPalette = try self.binaryReader.readBlockPalette()
            guard !liquidPalette.isEmpty, !liquidIndicesData.isEmpty else {
                return nil
            }
        }

        return .init(
            version: 9,
            chunkY: self.chunkY,
            blockLayer: .init(
                bitWidth: blockBitWidth,
                palette: blockPalette,
                indicesBytes: blockIndicesData
            ),
            liquidLayer: .init(
                bitWidth: liquidBitWidth,
                palette: liquidPalette,
                indicesBytes: liquidIndicesData
            )
        )
    }

    // TODO: create MCBlock from block ID and block data // swiftlint:disable:this todo
    private func parseClassicPacked() throws -> PackedSubChunk? {
        var blockIDList = [UInt8]()
        var blockDataList = [UInt8]()
        // 4096 bytes for block ids
        for _ in 0..<MCSubChunk.totalBlockCount {
            let id = try binaryReader.readUInt8()
            blockIDList.append(id)
        }
        // Each byte contains 2 blocks: 4 bits per block
        for _ in 0..<(MCSubChunk.totalBlockCount / 2) {
            let twoBlockData = try binaryReader.readUInt8()
            let firstBlockData = twoBlockData & 0x0F
            let secondBlockData = (twoBlockData >> 4) & 0x0F
            blockDataList.append(firstBlockData)
            blockDataList.append(secondBlockData)
        }

        var blockPalette = [CompoundTag]()
        var blockIndicesData = [UInt8]()
        // swiftlint:disable:next identifier_name
        for i in 0..<MCSubChunk.totalBlockCount {
            // TODO: create CompoundTag from block ID and block data // swiftlint:disable:this todo
            // let blockID = blockIDList[i]
            // let blockData = blockDataList[i]
            let block = CompoundTag()
            blockPalette.append(block)

            let word = UInt32(truncatingIfNeeded: i)
            let bytes: [UInt8] = withUnsafeBytes(of: word) { Array($0) }
            blockIndicesData.append(contentsOf: bytes)
        }

        return .init(
            version: 9,
            chunkY: self.chunkY,
            blockLayer: .init(
                bitWidth: CBBinaryReader.wordBitSize,
                palette: blockPalette,
                indicesBytes: blockIndicesData
            ),
            liquidLayer: nil
        )
    }

    // swiftlint:disable line_length
    // MARK: - Skip indices parsing for better performance

//    private func parseBlockIndicesUnsafe(from rawData: [UInt8], bitsPerBlock: Int, blocksPerWord: Int) throws -> [UInt16]? {
//        var result = [UInt16](repeating: 0, count: MCSubChunk.totalBlockCount)
//        let mask: UInt32 = (1 << bitsPerBlock) - 1
//        rawData.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
//            let wordPointer = rawBuffer.bindMemory(to: UInt32.self)
//            let wordCount = wordPointer.count
//            result.withUnsafeMutableBufferPointer { resultBuffer in
//                var outputPtr = resultBuffer.baseAddress!
//                var remaining = MCSubChunk.totalBlockCount
//                for w in 0..<wordCount {
//                    let word = UInt32(littleEndian: wordPointer[w])
//                    for i in 0..<blocksPerWord {
//                        guard remaining > 0 else { break }
//                        let shift = i * bitsPerBlock
//                        let value = (word >> shift) & mask
//                        outputPtr.pointee = UInt16(truncatingIfNeeded: value)
//                        outputPtr += 1
//                        remaining -= 1
//                    }
//                }
//            }
//        }
//        return result
//    }
//
//    @available(*, deprecated, renamed: "parseBlockIndicesUnsafe", message: "")
//    private func readBlockIndices(bitsPerBlock: Int) throws -> [UInt16]? {
//        let blocksPerWord = Self.wordBitSize / bitsPerBlock
//        let totalWords = Int(ceil(   Double(MCSubChunk.totalBlockCount) / Double(blocksPerWord)   ))
//        let totalBytes = totalWords * 4
//        guard binaryReader.remainingByteCount >= totalBytes else {
//            return nil
//        }
//
//        let mask: UInt32 = ~(UInt32(0xFFFF) << bitsPerBlock)
//        var elements = [UInt16]()
//
//        for _ in 0 ..< totalWords {
//            let word = try binaryReader.readUInt32()
//            for i in 0 ..< blocksPerWord {
//                guard elements.count < MCSubChunk.totalBlockCount else { break }
//                let element: UInt32 = mask & (word >> (i * bitsPerBlock))
//                elements.append(UInt16(truncatingIfNeeded: element))
//            }
//        }
//
//        return elements.count == MCSubChunk.totalBlockCount ? elements : nil
//    }
    // swiftlint:enable line_length
}
