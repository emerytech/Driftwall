import Cocoa
import AVKit
import AVFoundation

enum StockSource: Int {
    case pexels = 0
    case coverr = 1
    case pixabay = 2
    var label: String {
        switch self {
        case .pexels:  return "Pexels"
        case .coverr:  return "Coverr"
        case .pixabay: return "Pixabay"
        }
    }
}

/// Resolution floor for results. `minHeight` is exact client-side
/// filtering; `pexelsSize` is the coarse server-side tier.
enum ResFilter: Int, CaseIterable {
    case any = 0, uhd, qhd, fhd, hd

    var label: String {
        switch self {
        case .any: return "Any resolution"
        case .uhd: return "4K"
        case .qhd: return "1440p"
        case .fhd: return "1080p"
        case .hd:  return "720p"
        }
    }
    var minHeight: Int? {
        switch self {
        case .any: return nil
        case .uhd: return 2160
        case .qhd: return 1440
        case .fhd: return 1080
        case .hd:  return 720
        }
    }
    var pexelsSize: String? {
        switch self {
        case .uhd:        return "large"
        case .qhd, .fhd:  return "medium"
        case .hd:         return "small"
        case .any:        return nil
        }
    }
}

enum SortMode: Int, CaseIterable {
    case relevance = 0, resolution, longest, shortest
    var label: String {
        switch self {
        case .relevance:  return "Sort: Default"
        case .resolution: return "Sort: Resolution"
        case .longest:    return "Sort: Longest"
        case .shortest:   return "Sort: Shortest"
        }
    }
}

struct StockVideo {
    let id: String
    let title: String
    let thumb: URL
    let mp4: URL
    let width: Int
    let height: Int
    let seconds: Double

    var caption: String {
        var parts: [String] = []
        if width > 0, height > 0 { parts.append("\(width)×\(height)") }
        else if height > 0 { parts.append("\(height)p") }
        if seconds > 0 {
            let s = Int(seconds.rounded())
            parts.append(String(format: "%d:%02d", s / 60, s % 60))
        }
        let meta = parts.joined(separator: " · ")
        return title.isEmpty ? meta : (meta.isEmpty ? title : "\(title) — \(meta)")
    }
}

enum StockError: LocalizedError {
    case noKey(String), badResponse(String), http(String, Int)
    var errorDescription: String? {
        switch self {
        case .noKey(let p):
            return "Add your free \(p) API key in Settings, then reopen this window."
        case .badResponse(let p):
            return "Unexpected response from \(p)."
        case .http(let p, let c):
            return "\(p) returned HTTP \(c). Check your API key."
        }
    }
}

/// Pexels Videos API. `query == nil` → the curated Popular feed.
/// Landscape only — this is for wallpapers.
enum PexelsProvider {
    static func load(query: String?, key: String, res: ResFilter, page: Int,
                     completion: @escaping (Result<[StockVideo], Error>) -> Void) {
        guard !key.isEmpty else { return main(completion, .failure(StockError.noKey("Pexels"))) }
        let popular = (query?.isEmpty ?? true)
        let base = popular ? "https://api.pexels.com/videos/popular"
                           : "https://api.pexels.com/videos/search"
        var comps = URLComponents(string: base)!
        var items: [URLQueryItem] = [
            .init(name: "per_page", value: "30"),
            .init(name: "page", value: String(max(1, page))),
        ]
        if popular {
            if let mh = res.minHeight { items.append(.init(name: "min_height", value: String(mh))) }
        } else {
            items.append(.init(name: "query", value: query))
            items.append(.init(name: "orientation", value: "landscape"))
            if let size = res.pexelsSize { items.append(.init(name: "size", value: size)) }
        }
        comps.queryItems = items
        var req = URLRequest(url: comps.url!)
        req.setValue(key, forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err { return main(completion, .failure(err)) }
            if let code = (resp as? HTTPURLResponse)?.statusCode, code != 200 {
                return main(completion, .failure(StockError.http("Pexels", code)))
            }
            guard let data = data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let videos = root["videos"] as? [[String: Any]]
            else { return main(completion, .failure(StockError.badResponse("Pexels"))) }
            main(completion, .success(parse(videos, res: res)))
        }.resume()
    }

    private static func parse(_ videos: [[String: Any]], res: ResFilter) -> [StockVideo] {
        videos.compactMap { v in
            guard let id = v["id"] as? Int,
                  let imageStr = v["image"] as? String,
                  let thumb = URL(string: imageStr),
                  let files = v["video_files"] as? [[String: Any]]
            else { return nil }
            let mp4s = files.filter { ($0["file_type"] as? String) == "video/mp4" }
            func h(_ f: [String: Any]) -> Int { f["height"] as? Int ?? 0 }
            func w(_ f: [String: Any]) -> Int { f["width"] as? Int ?? 0 }
            let chosen: [String: Any]?
            if let minH = res.minHeight {
                chosen = mp4s.filter { h($0) >= minH }.min { h($0) < h($1) }
            } else {
                chosen = mp4s.filter { w($0) <= 3840 }
                    .max { w($0) * h($0) < w($1) * h($1) } ?? mp4s.first
            }
            guard let best = chosen,
                  let linkStr = best["link"] as? String,
                  let mp4 = URL(string: linkStr) else { return nil }
            let dur = (v["duration"] as? Double) ?? Double(v["duration"] as? Int ?? 0)
            return StockVideo(id: String(id), title: "", thumb: thumb, mp4: mp4,
                              width: w(best), height: h(best), seconds: dur)
        }
    }

    static func main(_ c: @escaping (Result<[StockVideo], Error>) -> Void,
                     _ r: Result<[StockVideo], Error>) {
        DispatchQueue.main.async { c(r) }
    }
}

/// Coverr API (documented v1 shape). No server-side resolution filter;
/// mostly ≤1080p. `query == nil` → default listing.
enum CoverrProvider {
    static func load(query: String?, key: String, res: ResFilter, page: Int,
                     completion: @escaping (Result<[StockVideo], Error>) -> Void) {
        guard !key.isEmpty else { return PexelsProvider.main(completion, .failure(StockError.noKey("Coverr"))) }
        var comps = URLComponents(string: "https://api.coverr.co/videos")!
        var items: [URLQueryItem] = [
            .init(name: "page_size", value: "30"),
            .init(name: "page", value: String(max(1, page))),
            .init(name: "urls", value: "true"),
        ]
        if let q = query, !q.isEmpty { items.append(.init(name: "query", value: q)) }
        comps.queryItems = items
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err { return PexelsProvider.main(completion, .failure(err)) }
            if let code = (resp as? HTTPURLResponse)?.statusCode, code != 200 {
                return PexelsProvider.main(completion, .failure(StockError.http("Coverr", code)))
            }
            guard let data = data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return PexelsProvider.main(completion, .failure(StockError.badResponse("Coverr"))) }
            let hits = (root["hits"] as? [[String: Any]])
                    ?? (root["videos"] as? [[String: Any]]) ?? []

            let parsed: [StockVideo] = hits.compactMap { v in
                let id = (v["id"] as? String) ?? String(describing: v["id"] ?? "")
                let urls = v["urls"] as? [String: Any] ?? [:]
                let mp4Str = (urls["mp4_download"] as? String)
                          ?? (urls["mp4"] as? String)
                          ?? (urls["mp4_preview"] as? String)
                let thumbStr = (v["thumbnail"] as? String) ?? (v["poster"] as? String)
                guard let mp4Str, let mp4 = URL(string: mp4Str),
                      let thumbStr, let thumb = URL(string: thumbStr)
                else { return nil }
                let height = (v["max_height"] as? Int)
                          ?? (v["height"] as? Int)
                          ?? ((v["dimensions"] as? [String: Any])?["height"] as? Int)
                          ?? 0
                if let minH = res.minHeight, height > 0, height < minH { return nil }
                let dur = (v["duration"] as? Double) ?? Double(v["duration"] as? Int ?? 0)
                let title = (v["title"] as? String) ?? "Coverr clip"
                return StockVideo(id: id, title: title, thumb: thumb, mp4: mp4,
                                  width: 0, height: height, seconds: dur)
            }
            PexelsProvider.main(completion, .success(parsed))
        }.resume()
    }
}

/// Pixabay video API — well-documented + stable: GET /api/videos/ with
/// the key as a query param. `query == nil` → popular feed.
enum PixabayProvider {
    static func load(query: String?, key: String, res: ResFilter, page: Int,
                     completion: @escaping (Result<[StockVideo], Error>) -> Void) {
        guard !key.isEmpty else { return PexelsProvider.main(completion, .failure(StockError.noKey("Pixabay"))) }
        var comps = URLComponents(string: "https://pixabay.com/api/videos/")!
        var items: [URLQueryItem] = [
            .init(name: "key", value: key),
            .init(name: "per_page", value: "30"),
            .init(name: "page", value: String(max(1, page))),
            .init(name: "safesearch", value: "true"),
            .init(name: "order", value: "popular"),
        ]
        if let q = query, !q.isEmpty { items.append(.init(name: "q", value: q)) }
        comps.queryItems = items

        URLSession.shared.dataTask(with: comps.url!) { data, resp, err in
            if let err = err { return PexelsProvider.main(completion, .failure(err)) }
            if let code = (resp as? HTTPURLResponse)?.statusCode, code != 200 {
                return PexelsProvider.main(completion, .failure(StockError.http("Pixabay", code)))
            }
            guard let data = data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hits = root["hits"] as? [[String: Any]]
            else { return PexelsProvider.main(completion, .failure(StockError.badResponse("Pixabay"))) }

            let parsed: [StockVideo] = hits.compactMap { v in
                guard let id = v["id"] as? Int,
                      let sizes = v["videos"] as? [String: [String: Any]]
                else { return nil }
                func hh(_ s: [String: Any]) -> Int { s["height"] as? Int ?? 0 }
                func ww(_ s: [String: Any]) -> Int { s["width"] as? Int ?? 0 }
                let variants = ["large", "medium", "small", "tiny"].compactMap { sizes[$0] }
                let pick: [String: Any]?
                if let minH = res.minHeight {
                    pick = variants.filter { hh($0) >= minH }.min { hh($0) < hh($1) }
                } else {
                    pick = variants.max { ww($0) * hh($0) < ww($1) * hh($1) }
                }
                guard let chosen = pick,
                      let urlStr = chosen["url"] as? String,
                      let mp4 = URL(string: urlStr) else { return nil }
                let thumbStr = (chosen["thumbnail"] as? String)
                            ?? (variants.compactMap { $0["thumbnail"] as? String }.first)
                guard let thumbStr, let thumb = URL(string: thumbStr) else { return nil }
                let dur = (v["duration"] as? Double) ?? Double(v["duration"] as? Int ?? 0)
                return StockVideo(id: String(id), title: "", thumb: thumb, mp4: mp4,
                                  width: ww(chosen), height: hh(chosen), seconds: dur)
            }
            PexelsProvider.main(completion, .success(parsed))
        }.resume()
    }
}

/// Reused looping video preview window.
final class PreviewController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let playerView = AVPlayerView()
    private var looper: AVPlayerLooper?

    func show(_ url: URL, title: String) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
                             styleMask: [.titled, .closable, .resizable],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.delegate = self
            playerView.controlsStyle = .floating
            playerView.videoGravity = .resizeAspect
            playerView.translatesAutoresizingMaskIntoConstraints = false
            w.contentView?.addSubview(playerView)
            if let c = w.contentView {
                NSLayoutConstraint.activate([
                    playerView.topAnchor.constraint(equalTo: c.topAnchor),
                    playerView.bottomAnchor.constraint(equalTo: c.bottomAnchor),
                    playerView.leadingAnchor.constraint(equalTo: c.leadingAnchor),
                    playerView.trailingAnchor.constraint(equalTo: c.trailingAnchor),
                ])
            }
            window = w
        }
        let qp = AVQueuePlayer()
        qp.isMuted = true
        looper = AVPlayerLooper(player: qp, templateItem: AVPlayerItem(url: url))
        playerView.player = qp
        window?.title = "Preview — \(title)"
        if let window { Appearance.register(window) }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        qp.play()
    }

    func windowWillClose(_ notification: Notification) {
        playerView.player?.pause()
        playerView.player = nil
        looper = nil
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Search a stock provider, preview thumbnails, pick one. `onPick`
/// receives the remote mp4 URL — the caller downloads + applies it.
final class StockBrowserWindowController: NSWindowController, NSSearchFieldDelegate {
    var keyFor: (StockSource) -> String = { _ in "" }
    var onPick: (URL) -> Void = { _ in }

    private let providerControl = NSSegmentedControl(
        labels: ["Pexels", "Coverr", "Pixabay"], trackingMode: .selectOne,
        target: nil, action: nil)
    private let resolutionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sortPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let searchField = NSSearchField()
    private let refreshButton = NSButton(title: "↻ Refresh", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let resultsStack = NSStackView()
    private var rowActions: [ButtonAction] = []
    private let preview = PreviewController()

    private var lastResults: [StockVideo] = []
    private var page = 1
    private var thumbCache: [URL: NSImage] = [:]

    private var source: StockSource {
        StockSource(rawValue: providerControl.selectedSegment) ?? .pexels
    }
    private var resolution: ResFilter {
        ResFilter(rawValue: resolutionPopup.indexOfSelectedItem) ?? .any
    }
    private var sortMode: SortMode {
        SortMode(rawValue: sortPopup.indexOfSelectedItem) ?? .relevance
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Stock Videos"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        providerControl.selectedSegment = 0
        providerControl.target = self
        providerControl.action = #selector(criteriaChanged)
        providerControl.translatesAutoresizingMaskIntoConstraints = false

        resolutionPopup.addItems(withTitles: ResFilter.allCases.map { $0.label })
        resolutionPopup.target = self
        resolutionPopup.action = #selector(criteriaChanged)
        resolutionPopup.translatesAutoresizingMaskIntoConstraints = false

        sortPopup.addItems(withTitles: SortMode.allCases.map { $0.label })
        sortPopup.target = self
        sortPopup.action = #selector(sortChanged)
        sortPopup.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = "type to search, or browse popular below"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        refreshButton.bezelStyle = .rounded
        refreshButton.target = self
        refreshButton.action = #selector(refreshTapped)
        refreshButton.toolTip = "Load a different set of videos"
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        resultsStack.orientation = .vertical
        resultsStack.alignment = .leading
        resultsStack.spacing = 10
        resultsStack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(resultsStack)
        scroll.documentView = doc

        [providerControl, resolutionPopup, sortPopup, searchField,
         refreshButton, statusLabel, scroll].forEach { content.addSubview($0) }

        NSLayoutConstraint.activate([
            providerControl.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            providerControl.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),

            resolutionPopup.centerYAnchor.constraint(equalTo: providerControl.centerYAnchor),
            resolutionPopup.leadingAnchor.constraint(equalTo: providerControl.trailingAnchor, constant: 10),

            searchField.centerYAnchor.constraint(equalTo: providerControl.centerYAnchor),
            searchField.leadingAnchor.constraint(equalTo: resolutionPopup.trailingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            sortPopup.topAnchor.constraint(equalTo: providerControl.bottomAnchor, constant: 10),
            sortPopup.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),

            refreshButton.centerYAnchor.constraint(equalTo: sortPopup.centerYAnchor),
            refreshButton.leadingAnchor.constraint(equalTo: sortPopup.trailingAnchor, constant: 10),

            statusLabel.centerYAnchor.constraint(equalTo: sortPopup.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: refreshButton.trailingAnchor, constant: 14),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -16),

            scroll.topAnchor.constraint(equalTo: sortPopup.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),

            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),

            resultsStack.topAnchor.constraint(equalTo: doc.topAnchor, constant: 4),
            resultsStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 4),
            resultsStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -4),
            resultsStack.bottomAnchor.constraint(lessThanOrEqualTo: doc.bottomAnchor, constant: -4),
        ])
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window { Appearance.register(window) }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        searchField.becomeFirstResponder()
        if resultsStack.arrangedSubviews.isEmpty { performLoad(page: 1) }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if let mv = obj.userInfo?["NSTextMovement"] as? Int,
           mv == NSTextMovement.return.rawValue {
            performLoad(page: 1)
        }
    }

    @objc private func criteriaChanged() { performLoad(page: 1) }

    @objc private func sortChanged() { renderResults() }   // no refetch

    @objc private func refreshTapped() { performLoad(page: page + 1) }

    private func performLoad(page requested: Int) {
        thumbCache.removeAll()   // new query/page/criteria — old thumbs won't recur
        let q = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let src = source
        let res = resolution
        let scope = q.isEmpty ? "Popular on \(src.label)" : "\(src.label) “\(q)”"
        statusLabel.stringValue = "Loading \(scope)…"

        let handler: (Result<[StockVideo], Error>) -> Void = { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let e):
                self.statusLabel.stringValue = e.localizedDescription
            case .success(let vids):
                if vids.isEmpty {
                    if requested > 1 {
                        // Past the end — wrap back to the first page.
                        self.performLoad(page: 1)
                    } else {
                        self.statusLabel.stringValue = "No results for \(scope) at \(res.label)."
                        self.lastResults = []
                        self.renderResults()
                    }
                } else {
                    self.page = requested
                    self.lastResults = vids
                    self.renderResults()
                    let pg = requested > 1 ? " · page \(requested)" : ""
                    self.statusLabel.stringValue = "\(scope)\(pg) — Preview, or Use to apply."
                }
            }
        }
        let query: String? = q.isEmpty ? nil : q
        switch src {
        case .pexels: PexelsProvider.load(query: query, key: keyFor(.pexels), res: res,
                                          page: requested, completion: handler)
        case .coverr: CoverrProvider.load(query: query, key: keyFor(.coverr), res: res,
                                          page: requested, completion: handler)
        case .pixabay: PixabayProvider.load(query: query, key: keyFor(.pixabay), res: res,
                                            page: requested, completion: handler)
        }
    }

    private func sorted(_ vids: [StockVideo]) -> [StockVideo] {
        switch sortMode {
        case .relevance:  return vids
        case .resolution: return vids.sorted { ($0.height, $0.width) > ($1.height, $1.width) }
        case .longest:    return vids.sorted { $0.seconds > $1.seconds }
        case .shortest:   return vids.sorted { $0.seconds < $1.seconds }
        }
    }

    private static let cardWidth: CGFloat = 240
    private static let cardSpacing: CGFloat = 14

    private func columnCount() -> Int {
        let avail = (window?.contentView?.bounds.width ?? 720) - 32   // side margins
        let per = Self.cardWidth + Self.cardSpacing
        return max(1, Int((avail + Self.cardSpacing) / per))
    }

    private func renderResults() {
        rowActions.removeAll()
        resultsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let vids = sorted(lastResults)
        let cols = columnCount()
        var i = 0
        while i < vids.count {
            let rowVids = Array(vids[i ..< min(i + cols, vids.count)])
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = Self.cardSpacing
            rowVids.forEach { row.addArrangedSubview(card($0)) }
            resultsStack.addArrangedSubview(row)
            i += cols
        }
    }

    private func card(_ v: StockVideo) -> NSView {
        let cell = NSStackView()
        cell.orientation = .vertical
        cell.alignment = .leading
        cell.spacing = 6
        cell.translatesAutoresizingMaskIntoConstraints = false
        cell.widthAnchor.constraint(equalToConstant: Self.cardWidth).isActive = true

        let thumb = NSImageView()
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.backgroundColor = NSColor.black.cgColor
        thumb.layer?.cornerRadius = 6
        thumb.layer?.masksToBounds = true
        thumb.translatesAutoresizingMaskIntoConstraints = false
        thumb.widthAnchor.constraint(equalToConstant: Self.cardWidth).isActive = true
        thumb.heightAnchor.constraint(equalToConstant: Self.cardWidth * 9 / 16).isActive = true

        let label = NSTextField(wrappingLabelWithString: v.caption)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: 11)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: Self.cardWidth).isActive = true

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let previewBtn = NSButton(title: "Preview", target: nil, action: nil)
        previewBtn.bezelStyle = .rounded
        let previewAction = ButtonAction { [weak self] in
            self?.preview.show(v.mp4, title: v.caption)
        }
        rowActions.append(previewAction)
        previewBtn.target = previewAction
        previewBtn.action = #selector(ButtonAction.fire)

        let use = NSButton(title: "Use", target: nil, action: nil)
        use.bezelStyle = .rounded
        let useAction = ButtonAction { [weak self] in self?.onPick(v.mp4) }
        rowActions.append(useAction)
        use.target = useAction
        use.action = #selector(ButtonAction.fire)

        buttons.addArrangedSubview(previewBtn)
        buttons.addArrangedSubview(use)

        [thumb, label, buttons].forEach { cell.addArrangedSubview($0) }

        if let cached = thumbCache[v.thumb] {
            thumb.image = cached
        } else {
            URLSession.shared.dataTask(with: v.thumb) { [weak self] data, _, _ in
                guard let data = data, let img = NSImage(data: data) else { return }
                DispatchQueue.main.async {
                    self?.thumbCache[v.thumb] = img
                    thumb.image = img
                }
            }.resume()
        }
        return cell
    }
}

/// Lets a plain closure be a target/action (no per-row subclassing).
private final class ButtonAction: NSObject {
    let block: () -> Void
    init(_ block: @escaping () -> Void) { self.block = block }
    @objc func fire() { block() }
}
