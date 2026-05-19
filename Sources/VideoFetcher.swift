import Foundation

enum FetchError: LocalizedError {
    case badURL
    case ytdlpMissing
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "That doesn't look like a valid http(s) URL."
        case .ytdlpMissing:
            return "This looks like a streaming page rather than a direct video file. "
                 + "Install yt-dlp (brew install yt-dlp) and try again — "
                 + "Driftwall will use it automatically."
        case .failed(let m):
            return m
        }
    }
}

/// Downloads a video from a direct URL (URLSession) or, for streaming
/// pages, via yt-dlp if it's installed. GUI apps don't inherit a shell
/// PATH, so tool paths are resolved explicitly.
final class VideoFetcher {
    static let shared = VideoFetcher()

    private let directExts: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv", "avi"]
    private var progressObs: NSKeyValueObservation?
    private weak var currentTask: URLSessionTask?
    private var currentProc: Process?

    private var ytdlpPath: String? {
        ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/opt/local/bin/yt-dlp"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var destinationDir: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Wallpapers")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// `progress` reports 0...1, or nil for indeterminate. Both callbacks
    /// fire on the main queue.
    func fetch(_ raw: String,
               progress: @escaping (Double?) -> Void,
               completion: @escaping (Result<URL, Error>) -> Void) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return finish(completion, .failure(FetchError.badURL))
        }

        if directExts.contains(url.pathExtension.lowercased()) {
            downloadDirect(url, progress: progress, completion: completion)
            return
        }

        // Unknown extension — probe the content type before deciding.
        var head = URLRequest(url: url)
        head.httpMethod = "HEAD"
        URLSession.shared.dataTask(with: head) { [weak self] _, resp, _ in
            guard let self else { return }
            let type = (resp as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            if type.hasPrefix("video/") {
                self.downloadDirect(url, progress: progress, completion: completion)
            } else {
                self.downloadViaYtdlp(trimmed, progress: progress, completion: completion)
            }
        }.resume()
    }

    func cancel() {
        currentTask?.cancel()
        currentProc?.terminate()
    }

    private func downloadDirect(_ url: URL,
                                progress: @escaping (Double?) -> Void,
                                completion: @escaping (Result<URL, Error>) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { [weak self] temp, _, err in
            guard let self else { return }
            self.progressObs = nil
            if let err = err {
                return self.finish(completion, .failure(err))
            }
            guard let temp = temp else {
                return self.finish(completion, .failure(FetchError.failed("No data received.")))
            }
            let raw = url.lastPathComponent.isEmpty ? "video.mp4" : url.lastPathComponent
            let dest = self.uniqueDestination(self.safeName(raw))
            do {
                try FileManager.default.moveItem(at: temp, to: dest)
                self.finish(completion, .success(dest))
            } catch {
                self.finish(completion, .failure(error))
            }
        }
        currentTask = task
        progressObs = task.progress.observe(\.fractionCompleted) { p, _ in
            DispatchQueue.main.async { progress(p.fractionCompleted) }
        }
        task.resume()
    }

    private func downloadViaYtdlp(_ urlString: String,
                                  progress: @escaping (Double?) -> Void,
                                  completion: @escaping (Result<URL, Error>) -> Void) {
        guard let ytdlp = ytdlpPath else {
            return finish(completion, .failure(FetchError.ytdlpMissing))
        }
        DispatchQueue.main.async { progress(nil) }   // indeterminate

        DispatchQueue.global(qos: .userInitiated).async {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("driftwall-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: ytdlp)
            proc.arguments = [
                "--no-playlist",
                "--restrict-filenames",
                "-f", "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/b",
                "--merge-output-format", "mp4",
                "-o", tmp.appendingPathComponent("%(title).80B.%(ext)s").path,
                urlString,
            ]
            // yt-dlp needs ffmpeg on PATH to merge streams.
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            proc.environment = env
            let errPipe = Pipe()
            proc.standardError = errPipe
            proc.standardOutput = Pipe()

            self.currentProc = proc
            do {
                try proc.run()
            } catch {
                try? FileManager.default.removeItem(at: tmp)
                return self.finish(completion, .failure(error))
            }
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            self.currentProc = nil

            if proc.terminationStatus != 0 {
                let msg = String(data: errData, encoding: .utf8) ?? ""
                let tail = msg.split(separator: "\n").suffix(3).joined(separator: " ")
                try? FileManager.default.removeItem(at: tmp)
                return self.finish(completion,
                    .failure(FetchError.failed(tail.isEmpty ? "yt-dlp failed." : tail)))
            }

            let files = (try? FileManager.default.contentsOfDirectory(
                at: tmp, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            let produced = files.max { (self.size(of: $0) < self.size(of: $1)) }
            guard let produced else {
                try? FileManager.default.removeItem(at: tmp)
                return self.finish(completion,
                    .failure(FetchError.failed("yt-dlp produced no file.")))
            }
            let dest = self.uniqueDestination(self.safeName(produced.lastPathComponent))
            do {
                try FileManager.default.moveItem(at: produced, to: dest)
                try? FileManager.default.removeItem(at: tmp)
                self.finish(completion, .success(dest))
            } catch {
                self.finish(completion, .failure(error))
            }
        }
    }

    private func size(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private func safeName(_ raw: String) -> String {
        let base = raw.components(separatedBy: CharacterSet(charactersIn: "/\\")).last ?? ""
        let cleaned = base.replacingOccurrences(of: "..", with: "")
        return cleaned.isEmpty ? "video.mp4" : cleaned
    }

    private func uniqueDestination(_ name: String) -> URL {
        let dir = destinationDir
        var candidate = dir.appendingPathComponent(name)
        let ext = candidate.pathExtension
        let stem = candidate.deletingPathExtension().lastPathComponent
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent(ext.isEmpty ? "\(stem)-\(n)" : "\(stem)-\(n).\(ext)")
            n += 1
        }
        return candidate
    }

    private func finish(_ completion: @escaping (Result<URL, Error>) -> Void,
                        _ result: Result<URL, Error>) {
        DispatchQueue.main.async { completion(result) }
    }
}
