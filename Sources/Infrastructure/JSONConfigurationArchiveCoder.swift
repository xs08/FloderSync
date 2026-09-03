import Foundation

actor JSONConfigurationArchiveCoder: ConfigurationArchiveCoding {
    private let maximumFileSize = 10 * 1_024 * 1_024

    func read(from url: URL) async throws -> ConfigurationArchive {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = values.fileSize, fileSize > maximumFileSize {
            throw ConfigurationArchiveError.fileTooLarge
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= maximumFileSize else {
            throw ConfigurationArchiveError.fileTooLarge
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(ConfigurationArchive.self, from: data)
        } catch is DecodingError {
            throw ConfigurationArchiveError.invalidFile
        }
    }

    func write(_ archive: ConfigurationArchive, to url: URL) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(archive).write(to: url, options: .atomic)
    }
}
