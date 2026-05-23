import SwiftUI
import Photos

// MARK: - Model

struct TikTokVideoInfo: Codable {
    let code: Int
    let data: VideoData?

    struct VideoData: Codable {
        let id: String
        let title: String
        let cover: String
        let play: String        // watermark-free
        let wmplay: String      // with watermark
        let author: AuthorInfo

        struct AuthorInfo: Codable {
            let nickname: String
            let avatar: String
        }
    }
}

// MARK: - ViewModel

@MainActor
class TikDownViewModel: ObservableObject {
    @Published var urlInput: String = ""
    @Published var videoInfo: TikTokVideoInfo.VideoData? = nil
    @Published var isLoading = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var errorMessage: String? = nil
    @Published var showSuccess = false
    @Published var thumbnailImage: UIImage? = nil

    func fetchVideoInfo() async {
        let trimmed = urlInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { errorMessage = "Please paste a TikTok link."; return }
        guard trimmed.contains("tiktok.com") else { errorMessage = "Doesn't look like a TikTok link."; return }

        isLoading = true
        errorMessage = nil
        videoInfo = nil
        thumbnailImage = nil

        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        let apiURL = "https://www.tikwm.com/api/?url=\(encoded)"

        do {
            guard let url = URL(string: apiURL) else { throw URLError(.badURL) }
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try JSONDecoder().decode(TikTokVideoInfo.self, from: data)

            if result.code == 0, let info = result.data {
                videoInfo = info
                if let thumbURL = URL(string: info.cover) {
                    let (imgData, _) = try await URLSession.shared.data(from: thumbURL)
                    thumbnailImage = UIImage(data: imgData)
                }
            } else {
                errorMessage = "Couldn't fetch video. Check the link and try again."
            }
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func downloadVideo(withWatermark: Bool = false) async {
        guard let info = videoInfo else { return }
        let videoURLString = withWatermark ? info.wmplay : info.play
        guard let videoURL = URL(string: videoURLString) else { return }

        isDownloading = true
        downloadProgress = 0
        errorMessage = nil

        do {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                errorMessage = "Allow Photos access in Settings to save videos."
                isDownloading = false
                return
            }

            let localURL = try await downloadFile(from: videoURL)

            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: localURL)
            }
            showSuccess = true
        } catch {
            errorMessage = "Download failed: \(error.localizedDescription)"
        }
        isDownloading = false
    }

    private func downloadFile(from url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: url) { tmpURL, _, error in
                if let error = error { continuation.resume(throwing: error); return }
                guard let tmpURL else { continuation.resume(throwing: URLError(.badServerResponse)); return }
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".mp4")
                try? FileManager.default.moveItem(at: tmpURL, to: dest)
                continuation.resume(returning: dest)
            }
            let observation = task.progress.observe(\.fractionCompleted) { p, _ in
                Task { @MainActor in self.downloadProgress = p.fractionCompleted }
            }
            objc_setAssociatedObject(task, "obs", observation, .OBJC_ASSOCIATION_RETAIN)
            task.resume()
        }
    }

    func reset() {
        urlInput = ""; videoInfo = nil; thumbnailImage = nil; errorMessage = nil; downloadProgress = 0
    }
}

// MARK: - App Entry

@main
struct TikDownApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView().preferredColorScheme(.dark)
        }
    }
}

// MARK: - Root View

struct ContentView: View {
    @StateObject private var vm = TikDownViewModel()
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "0D0D0D"), Color(hex: "1A0A2E"), Color(hex: "0D0D0D")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    HeaderView()
                    InputCard(vm: vm, focused: $focused)

                    if let info = vm.videoInfo {
                        VideoCard(vm: vm, info: info)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if let err = vm.errorMessage {
                        ErrorBanner(message: err).transition(.opacity)
                    }
                }
                .padding(20)
            }
        }
        .animation(.spring(response: 0.4), value: vm.videoInfo != nil)
        .animation(.easeInOut, value: vm.errorMessage)
        .alert("Saved!", isPresented: $vm.showSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Video saved to Photos without watermark.")
        }
    }
}

struct HeaderView: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: "FF2D55"), Color(hex: "FF6B9D")],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("TikDown")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
            Text("Save TikToks without watermark")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.top, 8)
    }
}

struct InputCard: View {
    @ObservedObject var vm: TikDownViewModel
    @FocusState.Binding var focused: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "link").foregroundColor(Color(hex: "FF2D55"))
                TextField("Paste TikTok link...", text: $vm.urlInput)
                    .foregroundColor(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit { Task { await vm.fetchVideoInfo() } }
                if !vm.urlInput.isEmpty {
                    Button { vm.reset(); focused = false } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.4))
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1)))

            Button {
                if let s = UIPasteboard.general.string { vm.urlInput = s }
            } label: {
                Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }

            Button {
                focused = false
                Task { await vm.fetchVideoInfo() }
            } label: {
                HStack(spacing: 8) {
                    if vm.isLoading { ProgressView().tint(.white) }
                    else { Image(systemName: "magnifyingglass") }
                    Text(vm.isLoading ? "Fetching..." : "Get Video").fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(vm.isLoading
                    ? LinearGradient(colors: [.gray.opacity(0.4)], startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [Color(hex: "FF2D55"), Color(hex: "C9184A")], startPoint: .leading, endPoint: .trailing)
                )
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 13))
            }
            .disabled(vm.isLoading)
        }
    }
}

struct VideoCard: View {
    @ObservedObject var vm: TikDownViewModel
    let info: TikTokVideoInfo.VideoData

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let img = vm.thumbnailImage {
                Image(uiImage: img)
                    .resizable().aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity).frame(height: 200)
                    .clipped().clipShape(RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("@\(info.author.nickname)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "FF2D55"))
                Text(info.title)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(2)
            }

            if vm.isDownloading {
                VStack(spacing: 6) {
                    ProgressView(value: vm.downloadProgress).tint(Color(hex: "FF2D55"))
                    Text("Downloading \(Int(vm.downloadProgress * 100))%")
                        .font(.caption).foregroundColor(.white.opacity(0.5))
                }
            } else {
                HStack(spacing: 10) {
                    DLButton(label: "No Watermark", icon: "checkmark.shield.fill", primary: true) {
                        Task { await vm.downloadVideo(withWatermark: false) }
                    }
                    DLButton(label: "With Watermark", icon: "arrow.down.circle", primary: false) {
                        Task { await vm.downloadVideo(withWatermark: true) }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: "FF2D55").opacity(0.2)))
    }
}

struct DLButton: View {
    let label: String; let icon: String; let primary: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(label).font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(primary
                ? LinearGradient(colors: [Color(hex: "FF2D55"), Color(hex: "C9184A")], startPoint: .leading, endPoint: .trailing)
                : LinearGradient(colors: [Color.white.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
            )
            .foregroundColor(primary ? .white : .white.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(primary ? nil : RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12)))
        }
    }
}

struct ErrorBanner: View {
    let message: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Color(hex: "FF2D55"))
            Text(message).font(.system(size: 14)).foregroundColor(.white.opacity(0.85))
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "FF2D55").opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "FF2D55").opacity(0.25)))
    }
}

// MARK: - Hex Color Helper
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(
            red: Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8) & 0xFF) / 255,
            blue: Double(int & 0xFF) / 255
        )
    }
}
