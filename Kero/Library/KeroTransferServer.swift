//
//  KeroTransferServer.swift
//  Kero
//
//  Copyright (c) 2026 Zexin Zou. All rights reserved.
//
//  Wi-Fi Transfer: a tiny HTTP server on the local network. A computer on the same Wi-Fi
//  opens the page, drops games on it, and each file is PUT straight to the iPhone.
//  Only runs while the Wi-Fi Transfer screen is open.
//

import Foundation
import Network

final class KeroTransferServer: @unchecked Sendable
{
    enum State: Equatable
    {
        case stopped
        case starting
        case running(port: UInt16)
        case failed(String)
    }

    /// Called on the main queue.
    var onStateChange: ((State) -> Void)?
    /// Called on the main queue with the received file (in a temporary folder) and its original name.
    var onFileReceived: ((URL, String) -> Void)?

    static let allowedExtensions: Set<String> = ["gba", "gbc", "gb", "zip"]
    static let maximumFileSize = 256 * 1024 * 1024

    let uploadsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("WiFiTransfer", isDirectory: true)

    private let queue = DispatchQueue(label: "com.jkeroro.Kero.transfer")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: KeroHTTPConnection] = [:]

    func start()
    {
        self.queue.async {
            self.startListener(fixedPort: true)
        }
    }

    /// On `queue`. Tries port 8080 first (easy to type), then any free port.
    private func startListener(fixedPort: Bool)
    {
        guard self.listener == nil else { return }
        self.report(.starting)

        try? FileManager.default.createDirectory(at: self.uploadsDirectory, withIntermediateDirectories: true)

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = false

        let listener: NWListener
        do
        {
            listener = fixedPort ? try NWListener(using: parameters, on: 8080) : try NWListener(using: parameters)
        }
        catch
        {
            if fixedPort { return self.startListener(fixedPort: false) }
            return self.report(.failed("Couldn't start the server."))
        }

        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener, self.listener === listener else { return }
            switch state
            {
            case .ready:
                self.report(.running(port: listener.port?.rawValue ?? 8080))
            case .failed(let error):
                listener.cancel()
                self.listener = nil
                if fixedPort
                {
                    self.startListener(fixedPort: false)
                }
                else
                {
                    self.report(.failed(error.localizedDescription))
                }
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            let handler = KeroHTTPConnection(connection: connection, server: self)
            self.connections[ObjectIdentifier(handler)] = handler
            handler.start(on: self.queue)
        }

        self.listener = listener
        listener.start(queue: self.queue)
    }

    func stop()
    {
        self.queue.async {
            self.listener?.cancel()
            self.listener = nil
            for connection in self.connections.values { connection.cancel() }
            self.connections.removeAll()
            self.report(.stopped)
        }
    }

    // MARK: Called by connections (on `queue`)

    fileprivate func connectionDidFinish(_ connection: KeroHTTPConnection)
    {
        self.connections[ObjectIdentifier(connection)] = nil
    }

    fileprivate func didReceive(_ url: URL, name: String)
    {
        DispatchQueue.main.async {
            self.onFileReceived?(url, name)
        }
    }

    private func report(_ state: State)
    {
        DispatchQueue.main.async {
            self.onStateChange?(state)
        }
    }

    // MARK: Address

    /// The iPhone's IPv4 address on Wi-Fi (or its own hotspot), for the URL shown to the user.
    static func localAddress() -> String?
    {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }

        var candidates: [String: String] = [:]
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = pointer?.pointee
        {
            defer { pointer = interface.ifa_next }

            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name.hasPrefix("bridge") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            {
                candidates[name] = String(cString: host)
            }
        }

        return candidates["en0"] ?? candidates.first(where: { $0.key.hasPrefix("bridge") })?.value
    }
}

// MARK: - Connection -

private final class KeroHTTPConnection
{
    private let connection: NWConnection
    private weak var server: KeroTransferServer?

    private var header = Data()
    private var isReadingBody = false
    private var isDone = false

    private var expectedLength = 0
    private var receivedLength = 0
    private var fileHandle: FileHandle?
    private var fileURL: URL?
    private var fileName = ""

    init(connection: NWConnection, server: KeroTransferServer)
    {
        self.connection = connection
        self.server = server
    }

    func start(on queue: DispatchQueue)
    {
        self.connection.stateUpdateHandler = { [weak self] state in
            switch state
            {
            case .failed, .cancelled: self?.cleanUp()
            default: break
            }
        }
        self.connection.start(queue: queue)
        self.receive()
    }

    func cancel()
    {
        self.connection.cancel()
    }

    private func receive()
    {
        self.connection.receive(minimumIncompleteLength: 1, maximumLength: 512 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty
            {
                self.handle(data)
            }

            if self.isDone { return }

            if isComplete || error != nil
            {
                self.connection.cancel()
            }
            else
            {
                self.receive()
            }
        }
    }

    private func handle(_ data: Data)
    {
        if self.isReadingBody
        {
            self.write(data)
            return
        }

        self.header.append(data)

        guard let end = self.header.range(of: Data("\r\n\r\n".utf8)) else {
            if self.header.count > 32 * 1024 { self.respond(400, "Bad Request") }
            return
        }

        let headerText = String(decoding: self.header[..<end.lowerBound], as: UTF8.self)
        let leftover = self.header[end.upperBound...]

        var lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return self.respond(400, "Bad Request") }

        let method = String(requestLine[0])
        let target = String(requestLine[1])

        var headers: [String: String] = [:]
        for line in lines
        {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        let components = URLComponents(string: target)
        let path = components?.path ?? target

        switch (method, path)
        {
        case ("GET", "/"), ("GET", "/index.html"):
            self.respond(200, KeroTransferPage.html, contentType: "text/html; charset=utf-8")

        case ("PUT", "/upload"), ("POST", "/upload"):
            let name = components?.queryItems?.first(where: { $0.name == "name" })?.value ?? ""
            let length = Int(headers["content-length"] ?? "") ?? -1
            self.beginUpload(name: name, length: length, initialBody: Data(leftover))

        default:
            self.respond(404, "Not Found")
        }
    }

    private func beginUpload(name: String, length: Int, initialBody: Data)
    {
        guard let server else { return self.respond(503, "Unavailable") }

        // Keep only a plain file name.
        let fileName = (name as NSString).lastPathComponent
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let pathExtension = (fileName as NSString).pathExtension.lowercased()

        guard !fileName.isEmpty, KeroTransferServer.allowedExtensions.contains(pathExtension) else {
            return self.respond(415, "Only .gba, .gbc, .gb and .zip files.")
        }
        guard length > 0, length <= KeroTransferServer.maximumFileSize else {
            return self.respond(413, "File is empty or too large.")
        }

        let folder = server.uploadsDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent(fileName)

        do
        {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            self.fileHandle = try FileHandle(forWritingTo: url)
        }
        catch
        {
            return self.respond(500, "Couldn't save the file.")
        }

        self.fileURL = url
        self.fileName = fileName
        self.expectedLength = length
        self.isReadingBody = true

        if !initialBody.isEmpty
        {
            self.write(initialBody)
        }
    }

    private func write(_ data: Data)
    {
        let remaining = self.expectedLength - self.receivedLength
        let chunk = data.count > remaining ? data.prefix(remaining) : data

        do
        {
            try self.fileHandle?.write(contentsOf: chunk)
        }
        catch
        {
            self.discardFile()
            return self.respond(500, "Couldn't save the file.")
        }

        self.receivedLength += chunk.count

        if self.receivedLength >= self.expectedLength
        {
            try? self.fileHandle?.close()
            self.fileHandle = nil
            self.isReadingBody = false

            if let url = self.fileURL
            {
                self.fileURL = nil
                self.server?.didReceive(url, name: self.fileName)
            }

            self.respond(200, "{\"ok\":true}", contentType: "application/json")
        }
    }

    private func respond(_ status: Int, _ body: String, contentType: String = "text/plain; charset=utf-8")
    {
        guard !self.isDone else { return }
        self.isDone = true

        let reason: String
        switch status
        {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        case 413: reason = "Payload Too Large"
        case 415: reason = "Unsupported Media Type"
        case 503: reason = "Service Unavailable"
        default: reason = "Error"
        }

        let bodyData = Data(body.utf8)
        var response = "HTTP/1.1 \(status) \(reason)\r\n"
        response += "Content-Type: \(contentType)\r\n"
        response += "Content-Length: \(bodyData.count)\r\n"
        response += "Cache-Control: no-store\r\n"
        response += "Connection: close\r\n\r\n"

        var data = Data(response.utf8)
        data.append(bodyData)

        self.connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            self?.connection.cancel()
        })
    }

    private func discardFile()
    {
        try? self.fileHandle?.close()
        self.fileHandle = nil
        if let url = self.fileURL
        {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        self.fileURL = nil
    }

    private func cleanUp()
    {
        // An upload that didn't finish leaves nothing behind.
        if self.isReadingBody { self.discardFile() }
        self.server?.connectionDidFinish(self)
    }
}

// MARK: - Page -

private enum KeroTransferPage
{
    static let html = """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Kero Wi-Fi Transfer</title>
    <style>
      :root { color-scheme: dark; }
      * { box-sizing: border-box; }
      body { margin: 0; min-height: 100vh; background: #0b0c10; color: #f2f2f2;
             font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
             display: flex; justify-content: center; padding: 48px 16px; }
      main { width: 100%; max-width: 560px; }
      h1 { font-size: 22px; font-weight: 600; margin: 0 0 4px; letter-spacing: .2px; }
      p.sub { margin: 0 0 24px; color: rgba(255,255,255,.55); }
      #drop { border: 1.5px dashed rgba(255,255,255,.22); border-radius: 16px; padding: 44px 20px;
              text-align: center; background: rgba(255,255,255,.04); cursor: pointer; transition: .15s; }
      #drop.over { border-color: #fff; background: rgba(255,255,255,.09); }
      #drop strong { display: block; font-size: 17px; margin-bottom: 6px; }
      #drop span { color: rgba(255,255,255,.5); font-size: 13px; }
      ul { list-style: none; padding: 0; margin: 20px 0 0; }
      li { background: rgba(255,255,255,.05); border-radius: 12px; padding: 12px 14px; margin-bottom: 8px; }
      .row { display: flex; justify-content: space-between; gap: 12px; }
      .name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      .state { color: rgba(255,255,255,.5); flex: none; }
      .ok { color: #5cf08c; } .err { color: #ff6b6b; }
      .bar { height: 3px; background: rgba(255,255,255,.1); border-radius: 2px; margin-top: 8px; overflow: hidden; }
      .bar div { height: 100%; width: 0; background: #fff; transition: width .1s; }
      footer { margin-top: 28px; color: rgba(255,255,255,.35); font-size: 12px; }
    </style>
    </head>
    <body>
    <main>
      <h1>Kero Wi-Fi Transfer</h1>
      <p class="sub">Send games to your iPhone. Keep Kero open on the Wi-Fi Transfer screen.</p>
      <label id="drop">
        <strong>Drop games here</strong>
        <span>or click to choose · .gba .gbc .gb .zip</span>
        <input id="pick" type="file" multiple accept=".gba,.gbc,.gb,.zip" hidden>
      </label>
      <ul id="list"></ul>
      <footer>Only send games you own.</footer>
    </main>
    <script>
      const drop = document.getElementById('drop');
      const list = document.getElementById('list');
      const queue = [];
      let busy = false;

      function add(files) {
        for (const file of files) {
          const li = document.createElement('li');
          li.innerHTML = '<div class="row"><span class="name"></span><span class="state">Waiting</span></div><div class="bar"><div></div></div>';
          li.querySelector('.name').textContent = file.name;
          list.prepend(li);
          queue.push({ file, li });
        }
        next();
      }

      function next() {
        if (busy || queue.length === 0) return;
        busy = true;
        const { file, li } = queue.shift();
        const state = li.querySelector('.state');
        const bar = li.querySelector('.bar div');
        const xhr = new XMLHttpRequest();
        xhr.open('PUT', '/upload?name=' + encodeURIComponent(file.name));
        xhr.upload.onprogress = e => { if (e.lengthComputable) { bar.style.width = (100 * e.loaded / e.total) + '%'; state.textContent = Math.round(100 * e.loaded / e.total) + '%'; } };
        xhr.onload = () => {
          if (xhr.status === 200) { state.textContent = 'Sent'; state.className = 'state ok'; bar.style.width = '100%'; }
          else { state.textContent = xhr.responseText || ('Error ' + xhr.status); state.className = 'state err'; }
          busy = false; next();
        };
        xhr.onerror = () => { state.textContent = 'Connection lost'; state.className = 'state err'; busy = false; next(); };
        xhr.send(file);
      }

      document.getElementById('pick').addEventListener('change', e => { add(e.target.files); e.target.value = ''; });
      drop.addEventListener('dragover', e => { e.preventDefault(); drop.classList.add('over'); });
      drop.addEventListener('dragleave', () => drop.classList.remove('over'));
      drop.addEventListener('drop', e => { e.preventDefault(); drop.classList.remove('over'); add(e.dataTransfer.files); });
    </script>
    </body>
    </html>
    """
}
