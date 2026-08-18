import Foundation
import Network

/// Local WebSocket server that receives messages from the Chrome extension.
/// Listens on ws://localhost:19876.
final class WebSocketServer {
    private var listener: NWListener?
    private var connection: NWConnection?
    private var messageHandler: ((Data) -> Void)?

    var isConnected: Bool { connection != nil }

    func start(onMessage: @escaping (Data) -> Void) throws {
        self.messageHandler = onMessage

        let params = NWParameters(tls: nil)
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: AppConstants.websocketPort)!)
        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[WebSocket] Server listening on port \(AppConstants.websocketPort)")
            case .failed(let error):
                print("[WebSocket] Server failed: \(error)")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] newConnection in
            self?.handleNewConnection(newConnection)
        }

        listener?.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        connection?.cancel()
        connection = nil
        listener?.cancel()
        listener = nil
    }

    private func handleNewConnection(_ newConnection: NWConnection) {
        // Only allow one client at a time
        connection?.cancel()
        connection = newConnection

        newConnection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("[WebSocket] Client connected")
                self?.receiveMessage()
            case .failed(let error):
                print("[WebSocket] Connection failed: \(error)")
                self?.connection = nil
            case .cancelled:
                self?.connection = nil
            default:
                break
            }
        }

        newConnection.start(queue: .global(qos: .userInitiated))
    }

    private func receiveMessage() {
        guard let connection else { return }

        connection.receiveMessage { [weak self] content, _, _, error in
            if let error {
                print("[WebSocket] Receive error: \(error)")
                return
            }

            // Check if this is a WebSocket text message
            if let data = content, !data.isEmpty {
                self?.messageHandler?(data)
            }

            // Continue receiving
            self?.receiveMessage()
        }
    }
}
