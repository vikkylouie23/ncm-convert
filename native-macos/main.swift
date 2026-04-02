import AppKit
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate {
    private var window: NSWindow?
    private var server: LocalHTTPServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let resourceRoot = try bundledWebRoot()
            let server = LocalHTTPServer(
                rootURL: resourceRoot,
                saveHandler: { [weak self] data, suggestedFilename in
                    self?.saveFile(data: data, suggestedFilename: suggestedFilename) ?? .failed("应用窗口不可用。")
                }
            )
            let port = try server.start()
            self.server = server

            let config = WKWebViewConfiguration()
            let webView = WKWebView(frame: .zero, configuration: config)
            webView.uiDelegate = self
            webView.setValue(false, forKey: "drawsBackground")

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1280, height: 900),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.minSize = NSSize(width: 1024, height: 720)
            window.title = "NCM 本地转换工具"
            window.center()
            window.contentView = webView
            window.makeKeyAndOrderFront(nil)
            self.window = window

            let url = URL(string: "http://127.0.0.1:\(port)/index.html")!
            webView.load(URLRequest(url: url))
        } catch {
            let alert = NSAlert()
            alert.messageText = "应用启动失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    private func saveFile(data: Data, suggestedFilename: String) -> LocalHTTPServer.SaveResult {
        let semaphore = DispatchSemaphore(value: 0)
        var result: LocalHTTPServer.SaveResult = .cancelled

        DispatchQueue.main.async { [weak self] in
            let panel = NSSavePanel()
            panel.title = "保存转换后的文件"
            panel.message = "请选择保存位置"
            panel.prompt = "保存"
            panel.nameFieldStringValue = suggestedFilename
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false

            let completeSave: (NSApplication.ModalResponse) -> Void = { response in
                guard response == .OK, let destinationURL = panel.url else {
                    result = .cancelled
                    semaphore.signal()
                    return
                }

                do {
                    try data.write(to: destinationURL, options: .atomic)
                    result = .saved
                } catch {
                    result = .failed("写入文件失败：\(error.localizedDescription)")
                }

                semaphore.signal()
            }

            if let window = self?.window {
                panel.beginSheetModal(for: window, completionHandler: completeSave)
            } else {
                completeSave(panel.runModal())
            }
        }

        semaphore.wait()
        return result
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = "选择待转换的文件"
        panel.message = "支持多选"
        panel.prompt = "打开"
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.resolvesAliases = true

        if let window {
            panel.beginSheetModal(for: window) { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
        } else {
            let response = panel.runModal()
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    private func bundledWebRoot() throws -> URL {
        guard let resourcesURL = Bundle.main.resourceURL else {
            throw NSError(domain: "NCMApp", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到应用资源目录"])
        }

        let webRoot = resourcesURL.appendingPathComponent("web", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: webRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NSError(domain: "NCMApp", code: 2, userInfo: [NSLocalizedDescriptionKey: "缺少内置网页资源"])
        }

        return webRoot
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
