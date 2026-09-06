import Foundation

enum IconError: LocalizedError {
    case usage
    case missingFile(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: create-icns.swift <input.iconset> <output.icns>"
        case let .missingFile(name):
            "Missing iconset image: \(name)"
        }
    }
}

func bigEndianData(_ value: UInt32) -> Data {
    var value = value.bigEndian
    return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
}

func fourCharacterCode(_ value: String) -> Data {
    Data(value.utf8)
}

func createICNS(iconsetURL: URL, outputURL: URL) throws {
    let entries: [(type: String, file: String)] = [
        ("icp4", "icon_16x16.png"),
        ("icp5", "icon_32x32.png"),
        ("icp6", "icon_32x32@2x.png"),
        ("ic07", "icon_128x128.png"),
        ("ic08", "icon_256x256.png"),
        ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png")
    ]

    var chunks = Data()
    for entry in entries {
        let fileURL = iconsetURL.appendingPathComponent(entry.file)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw IconError.missingFile(entry.file)
        }
        let imageData = try Data(contentsOf: fileURL)
        chunks.append(fourCharacterCode(entry.type))
        chunks.append(bigEndianData(UInt32(imageData.count + 8)))
        chunks.append(imageData)
    }

    var result = Data()
    result.append(fourCharacterCode("icns"))
    result.append(bigEndianData(UInt32(chunks.count + 8)))
    result.append(chunks)
    try result.write(to: outputURL, options: .atomic)
}

do {
    guard CommandLine.arguments.count == 3 else { throw IconError.usage }
    try createICNS(
        iconsetURL: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true),
        outputURL: URL(fileURLWithPath: CommandLine.arguments[2])
    )
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
