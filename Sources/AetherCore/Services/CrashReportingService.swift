import Foundation
import os.log

/// Crash report information.
public struct CrashReport: Identifiable, Codable, Sendable {
    public let id: UUID
    public var timestamp: Date
    public var appVersion: String
    public var osVersion: String
    public var deviceModel: String
    public var errorMessage: String
    public var stackTrace: String
    public var userDescription: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        appVersion: String,
        osVersion: String,
        deviceModel: String,
        errorMessage: String,
        stackTrace: String,
        userDescription: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.errorMessage = errorMessage
        self.stackTrace = stackTrace
        self.userDescription = userDescription
    }

    /// Format as text for export.
    public var formattedText: String {
        var text = """
        AETHER CRASH REPORT
        ===================

        Timestamp: \(timestamp.formatted())
        App Version: \(appVersion)
        OS Version: \(osVersion)
        Device: \(deviceModel)

        ERROR MESSAGE
        -------------
        \(errorMessage)

        STACK TRACE
        -----------
        \(stackTrace)

        """

        if let desc = userDescription {
            text += """

            USER DESCRIPTION
            ----------------
            \(desc)

            """
        }

        return text
    }
}

/// Service for crash reporting and logging.
@MainActor
public final class CrashReportingService: ObservableObject {
    @Published public private(set) var crashReports: [CrashReport] = []

    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.aether.iptv", category: "CrashReporting")
    private var crashLogDirectory: URL

    public init() {
        // Setup crash log directory
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        crashLogDirectory = appSupport.appendingPathComponent("Aether/CrashLogs")

        try? fileManager.createDirectory(at: crashLogDirectory, withIntermediateDirectories: true)

        // Load existing crash reports
        loadCrashReports()

        // Setup crash handler
        setupCrashHandler()
    }

    // MARK: - Crash Handling

    private func setupCrashHandler() {
        NSSetUncaughtExceptionHandler { exception in
            Task { @MainActor in
                let service = CrashReportingService.shared
                service.logCrash(
                    errorMessage: exception.reason ?? "Unknown error",
                    stackTrace: exception.callStackSymbols.joined(separator: "\n")
                )
            }
        }
    }

    /// Log a crash.
    public func logCrash(errorMessage: String, stackTrace: String) {
        let report = CrashReport(
            appVersion: getAppVersion(),
            osVersion: getOSVersion(),
            deviceModel: getDeviceModel(),
            errorMessage: errorMessage,
            stackTrace: stackTrace
        )

        crashReports.append(report)
        saveCrashReport(report)

        logger.error("Crash logged: \(errorMessage)")
    }

    /// Log an error (non-fatal).
    public func logError(_ error: Error, context: String? = nil) {
        let message = context.map { "\($0): \(error.localizedDescription)" } ?? error.localizedDescription
        logger.error("\(message)")

        // Save to error log file
        let errorLog = """
        [\(Date().formatted())] \(message)
        \(error)

        """

        let errorLogFile = crashLogDirectory.appendingPathComponent("errors.log")
        if let data = errorLog.data(using: .utf8) {
            if fileManager.fileExists(atPath: errorLogFile.path) {
                if let handle = try? FileHandle(forWritingTo: errorLogFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: errorLogFile)
            }
        }
    }

    // MARK: - Report Management

    private func loadCrashReports() {
        guard let files = try? fileManager.contentsOfDirectory(at: crashLogDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let report = try? JSONDecoder().decode(CrashReport.self, from: data) {
                crashReports.append(report)
            }
        }

        // Sort by timestamp (newest first)
        crashReports.sort { $0.timestamp > $1.timestamp }
    }

    private func saveCrashReport(_ report: CrashReport) {
        let fileName = "crash_\(report.id.uuidString).json"
        let fileURL = crashLogDirectory.appendingPathComponent(fileName)

        if let data = try? JSONEncoder().encode(report) {
            try? data.write(to: fileURL)
        }
    }

    /// Delete a crash report.
    public func deleteCrashReport(_ reportId: UUID) {
        crashReports.removeAll { $0.id == reportId }

        let fileName = "crash_\(reportId.uuidString).json"
        let fileURL = crashLogDirectory.appendingPathComponent(fileName)
        try? fileManager.removeItem(at: fileURL)
    }

    /// Delete all crash reports.
    public func deleteAllCrashReports() {
        for report in crashReports {
            let fileName = "crash_\(report.id.uuidString).json"
            let fileURL = crashLogDirectory.appendingPathComponent(fileName)
            try? fileManager.removeItem(at: fileURL)
        }

        crashReports.removeAll()
    }

    /// Export crash report to file.
    public func exportCrashReport(_ report: CrashReport, to url: URL) throws {
        let text = report.formattedText
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - System Info

    private func getAppVersion() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    private func getOSVersion() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    private func getDeviceModel() -> String {
        #if os(macOS)
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
        #else
        return "iOS Device"
        #endif
    }

    // MARK: - Singleton

    public static let shared = CrashReportingService()
}
