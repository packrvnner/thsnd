//
//  SocketFactory.swift
//  Thousand
//
//  URLSession-backed WebSocket for the WalletConnect relay — avoids a
//  Starscream dependency. Conforms to Reown's WebSocketConnecting /
//  WebSocketFactory protocols (from WalletConnectRelay).
//
//  If a Reown release adjusts these protocol requirements, the compiler
//  will point here; this file and WalletService.swift are the only two
//  files that touch the SDK.
//

import Foundation
import WalletConnectRelay

final class URLSessionWebSocket: NSObject, WebSocketConnecting {

    var isConnected: Bool = false
    var onConnect: (() -> Void)?
    var onDisconnect: ((Error?) -> Void)?
    var onText: ((String) -> Void)?
    var request: URLRequest

    private var task: URLSessionWebSocketTask?
    private lazy var session: URLSession = URLSession(
        configuration: .default,
        delegate: self,
        delegateQueue: OperationQueue()
    )

    init(url: URL) {
        self.request = URLRequest(url: url)
        super.init()
    }

    func connect() {
        task = session.webSocketTask(with: request)
        task?.resume()
        receiveLoop()
    }

    func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        isConnected = false
    }

    func write(string: String, completion: (() -> Void)?) {
        task?.send(.string(string)) { _ in completion?() }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self.onText?(text)
                } else if case .data(let data) = message, let text = String(data: data, encoding: .utf8) {
                    self.onText?(text)
                }
                self.receiveLoop()
            case .failure(let error):
                let wasConnected = self.isConnected
                self.isConnected = false
                if wasConnected { self.onDisconnect?(error) }
            }
        }
    }
}

extension URLSessionWebSocket: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        isConnected = true
        onConnect?()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isConnected = false
        onDisconnect?(nil)
    }
}

struct URLSessionSocketFactory: WebSocketFactory {
    func create(with url: URL) -> WebSocketConnecting {
        URLSessionWebSocket(url: url)
    }
}
