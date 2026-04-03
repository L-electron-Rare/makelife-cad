import Foundation

// MARK: - CommandRunner

/// Async Process wrapper — streams stdout/stderr line by line.
@MainActor
final class CommandRunner: ObservableObject {

    struct OutputLine: Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    @Published private(set) var lines: [OutputLine] = []
    @Published private(set) var isRunning = false
    @Published private(set) var exitCode: Int32?

    private var process: Process?

    // MARK: - Public

    func run(_ executable: String, args: [String] = [], cwd: URL? = nil) {
        guard !isRunning else { return }
        lines = []
        exitCode = nil
        isRunning = true

        let proc = Process()
        self.process = proc
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args
        if let cwd { proc.currentDirectoryURL = cwd }

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError  = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.lines.append(OutputLine(text: str, isError: false))
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.lines.append(OutputLine(text: str, isError: true))
            }
        }

        Task.detached { [weak self] in
            do {
                try proc.run()
                proc.waitUntilExit()
            } catch {
                await MainActor.run { [weak self] in
                    self?.lines.append(OutputLine(text: "Error: \(error.localizedDescription)", isError: true))
                }
            }
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            await MainActor.run { [weak self] in
                self?.exitCode = proc.terminationStatus
                self?.isRunning = false
                self?.process = nil
            }
        }
    }

    func stop() {
        process?.terminate()
    }

    func clear() {
        lines = []
        exitCode = nil
    }
}
