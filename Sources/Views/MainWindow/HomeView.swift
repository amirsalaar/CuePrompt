import SwiftUI

/// Main window: content source selection and script editing.
struct HomeView: View {
    @Bindable var appState: AppState

    @State private var scriptText: String = ""
    @State private var showFileImporter = false
    @State private var isDragTargeted = false
    @State private var isEditing = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            contentArea
        }
        .frame(minWidth: 500, minHeight: 400)
        .overlay {
            if isDragTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .background(
                        Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12)
                    )
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                let ext = url.pathExtension.lowercased()
                guard ["md", "txt", "text", "markdown"].contains(ext) else { return }
                DispatchQueue.main.async {
                    try? appState.loadFile(at: url)
                    scriptText = appState.currentContent?.scriptText ?? ""
                    isEditing = false
                }
            }
            return true
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                try? appState.loadFile(at: url)
                scriptText = appState.currentContent?.scriptText ?? ""
                isEditing = false
            }
        }
        .alert(
            "Permissions Required",
            isPresented: $appState.showPermissionAlert
        ) {
            Button("Open System Settings") {
                appState.permissionManager.openSystemSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(permissionAlertMessage)
        }
    }

    private var permissionAlertMessage: String {
        var missing: [String] = []
        if appState.permissionManager.microphoneStatus != .granted {
            missing.append("Microphone")
        }
        if appState.permissionManager.speechRecognitionStatus != .granted {
            missing.append("Speech Recognition")
        }
        let list = missing.joined(separator: " and ")
        return
            "CuePrompt needs \(list) permission to present. Please grant access in System Settings."
    }

    private var headerBar: some View {
        HStack {
            Text("CuePrompt")
                .font(.title2.bold())

            Spacer()

            connectionIndicator

            Button("Present") {
                if !scriptText.isEmpty {
                    appState.loadText(scriptText)
                }
                appState.startPresenting()
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.currentContent == nil && scriptText.isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding()
    }

    private var contentArea: some View {
        VStack(alignment: .leading, spacing: 16) {
            sourceButtons

            if isEditing || appState.currentContent == nil {
                // Raw text editor for composing
                TextEditor(text: $scriptText)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topLeading) {
                        if scriptText.isEmpty {
                            Text(
                                "Type or paste your script here.\nUse ## headings to create section breaks."
                            )
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                        }
                    }
                    .onChange(of: scriptText) { _, newValue in
                        if !newValue.isEmpty {
                            appState.loadText(newValue)
                        }
                    }
            } else {
                // Rendered markdown view
                renderedContentView
            }
        }
        .padding()
    }

    private var renderedContentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(appState.scriptSections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        if let title = section.title {
                            Text(title)
                                .font(.system(size: 18, weight: .bold))
                        }
                        if let md = try? AttributedString(
                            markdown: section.text,
                            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                        ) {
                            Text(md)
                                .font(.system(size: 14))
                        } else {
                            Text(section.text)
                                .font(.system(size: 14))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(count: 2) {
            isEditing = true
        }
    }

    private var sourceButtons: some View {
        HStack(spacing: 12) {
            Button {
                showFileImporter = true
            } label: {
                Label("Open File", systemImage: "doc")
            }

            Button {
                scriptText = ""
                appState.clearContent()
                isEditing = true
            } label: {
                Label("New Script", systemImage: "square.and.pencil")
            }

            if appState.currentContent != nil {
                Button {
                    if isEditing {
                        // Commit edits
                        if !scriptText.isEmpty {
                            appState.loadText(scriptText)
                        }
                    } else {
                        // Switch to editing — sync the raw text
                        scriptText = appState.currentContent?.scriptText ?? ""
                    }
                    isEditing.toggle()
                } label: {
                    Label(
                        isEditing ? "Done" : "Edit", systemImage: isEditing ? "checkmark" : "pencil"
                    )
                }
            }
        }
    }

    private var connectionIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(connectionColor)
                .frame(width: 8, height: 8)
            Text(connectionLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var connectionColor: Color {
        switch appState.bridgeCoordinator.state {
        case .connected: .green
        case .listening: .yellow
        case .disconnected: .gray
        case .error: .red
        }
    }

    private var connectionLabel: String {
        switch appState.bridgeCoordinator.state {
        case .connected: "Extension connected"
        case .listening: "Waiting for extension..."
        case .disconnected: "Bridge off"
        case .error(let msg): "Error: \(msg)"
        }
    }
}
