//
// Created by yechentide on 2024/07/14
//

import Foundation

public enum CBError: Error, Equatable, LocalizedError {
    case invalidWorldDirectory(URL)
    case failedOpenWorld(URL)
    case failedParseLevelData(URL?)
    case failedExtractKeys(URL)
    case unhandledLevelDBKey(String)
    case failedSaveImage(URL)
    case invalidDataLength(Int)
    case failedParseSubchunk
    case invalidSubChunkVersion(Int)
    case failedCreateImageContext
    case failedToAllocateMapIDs
    case failedToSaveMapDataTag
}
