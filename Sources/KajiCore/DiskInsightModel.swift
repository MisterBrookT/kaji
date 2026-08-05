import Foundation

public enum DiskFileCategory: String, CaseIterable, Codable, Sendable {
    case appsDeveloper
    case video
    case images
    case audio
    case documents
    case archives
    case caches
    case other

    public var label: String {
        switch self {
        case .appsDeveloper: "Apps / Developer"
        case .video: "Video"
        case .images: "Images"
        case .audio: "Audio"
        case .documents: "Documents"
        case .archives: "Archives"
        case .caches: "Caches"
        case .other: "Other"
        }
    }
}

public enum DiskFileCategoryLogic {
    private static let video = Set(["mov", "mp4", "m4v", "avi", "mkv", "webm"])
    private static let images = Set(["jpg", "jpeg", "png", "gif", "heic", "tif", "tiff", "webp", "svg", "raw"])
    private static let audio = Set(["mp3", "m4a", "aac", "wav", "flac", "aiff", "ogg"])
    private static let documents = Set(["pdf", "txt", "md", "rtf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key"])
    private static let archives = Set(["zip", "gz", "tgz", "bz2", "xz", "7z", "rar", "dmg", "pkg", "iso"])
    private static let developer = Set(["swift", "m", "mm", "h", "c", "cc", "cpp", "js", "jsx", "ts", "tsx", "py", "rb", "rs", "go", "java", "kt", "json", "yaml", "yml", "toml"])

    public static func category(path: String, pathExtension: String) -> DiskFileCategory {
        let normalizedPath = path.lowercased()
        let ext = pathExtension.lowercased()
        if normalizedPath.contains("/library/caches/") || normalizedPath.contains("/.cache/") {
            return .caches
        }
        if normalizedPath.contains("/library/developer/")
            || normalizedPath.contains("/applications/")
            || normalizedPath.contains(".app/") {
            return .appsDeveloper
        }
        if video.contains(ext) { return .video }
        if images.contains(ext) { return .images }
        if audio.contains(ext) { return .audio }
        if documents.contains(ext) { return .documents }
        if archives.contains(ext) { return .archives }
        if developer.contains(ext) { return .appsDeveloper }
        return .other
    }

    public static func normalizedTotals(_ totals: [DiskFileCategory: Int64]) -> [DiskFileCategory: Int64] {
        Dictionary(uniqueKeysWithValues: DiskFileCategory.allCases.map { ($0, max(0, totals[$0] ?? 0)) })
    }
}

public enum DiskInsightScanPolicy {
    public static let interval: TimeInterval = 24 * 60 * 60

    public static func shouldScan(
        lastSuccessfulAt: Date?,
        now: Date,
        force: Bool = false
    ) -> Bool {
        if force { return true }
        guard let lastSuccessfulAt else { return true }
        return now.timeIntervalSince(lastSuccessfulAt) >= interval
    }
}

