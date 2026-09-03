import SwiftUI
import AppKit

/// 스프라이트는 PokeTokenBar 가 이미 받아둔 것을 먼저 쓰고,
/// 없으면 (상대 포켓몬 등) PokeAPI 스프라이트 저장소에서 받아 캐시한다.
@MainActor
final class SpriteLoader: ObservableObject {
    static let shared = SpriteLoader()
    private var cache: [String: NSImage] = [:]
    private var inFlight: Set<String> = []

    private let dir: URL = {
        let d = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/PokeBattleBar/sprites")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// 폼 이름으로 스프라이트를 가져온다 (메가·거다이맥스·로토무 히트 등).
    /// PokeAPI 스프라이트 저장소에는 폼별 이미지가 다 있다.
    func image(form: String, shiny: Bool) -> NSImage? {
        let key = "form-\(form)-\(shiny ? "shiny" : "normal")"
        if let img = cache[key] { return img }
        let disk = dir.appending(path: key + ".png")
        if let img = NSImage(contentsOf: disk) { cache[key] = img; return img }
        downloadForm(form, shiny: shiny, key: key, to: disk)
        return nil
    }

    private func downloadForm(_ form: String, shiny: Bool, key: String, to disk: URL) {
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)
        Task { [weak self] in
            defer { Task { @MainActor in self?.inFlight.remove(key) } }
            // 폼 스프라이트 URL 은 pokemon/{form} 응답에 들어 있다
            guard let api = URL(string: "https://pokeapi.co/api/v2/pokemon/\(form)"),
                  let (d, _) = try? await URLSession.shared.data(from: api),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let sprites = j["sprites"] as? [String: Any] else { return }
            var urlString = sprites[shiny ? "front_shiny" : "front_default"] as? String
            if urlString == nil { urlString = sprites["front_default"] as? String }
            guard let us = urlString, let u = URL(string: us),
                  let (img, _) = try? await URLSession.shared.data(from: u),
                  let image = NSImage(data: img) else { return }
            try? img.write(to: disk)
            await MainActor.run {
                self?.cache[key] = image
                self?.objectWillChange.send()
            }
        }
    }

    func image(speciesID: Int, shiny: Bool) -> NSImage? {
        let key = "\(speciesID)-\(shiny ? "shiny" : "normal")"
        if let img = cache[key] { return img }

        // 1) PokeTokenBar 가 받아둔 애니메이션 GIF
        if let local = CompanionStore.spriteURL(speciesID: speciesID, shiny: shiny),
           let img = NSImage(contentsOf: local) {
            cache[key] = img
            return img
        }
        // 2) 우리 캐시
        let disk = dir.appending(path: key + ".png")
        if let img = NSImage(contentsOf: disk) {
            cache[key] = img
            return img
        }
        // 3) 내려받기
        download(speciesID: speciesID, shiny: shiny, key: key, to: disk)
        return nil
    }

    private func download(speciesID: Int, shiny: Bool, key: String, to disk: URL) {
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)
        let path = shiny ? "shiny/\(speciesID).png" : "\(speciesID).png"
        guard let url = URL(string: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/\(path)") else {
            inFlight.remove(key); return
        }
        Task { [weak self] in
            defer { Task { @MainActor in self?.inFlight.remove(key) } }
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let img = NSImage(data: data) else { return }
            try? data.write(to: disk)
            await MainActor.run {
                self?.cache[key] = img
                self?.objectWillChange.send()
            }
        }
    }
}

/// GIF 애니메이션을 그대로 재생하는 뷰 (PokeTokenBar 스프라이트가 GIF 다).
struct SpriteView: View {
    let speciesID: Int
    let shiny: Bool
    var size: CGFloat = 96
    /// 폼 이름이 있으면 그 폼 스프라이트를 쓴다 (메가·거다이맥스·로토무 히트 등)
    var form: String? = nil
    /// 다이맥스는 별도 스프라이트가 없으므로 크기로 표현한다
    var scale: CGFloat = 1.0
    @ObservedObject private var loader = SpriteLoader.shared

    private var image: NSImage? {
        if let form, let img = loader.image(form: form, shiny: shiny) { return img }
        return loader.image(speciesID: speciesID, shiny: shiny)
    }

    var body: some View {
        Group {
            if let img = image {
                AnimatedImage(image: img)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .frame(width: size * scale, height: size * scale)
    }
}

private struct AnimatedImage: NSViewRepresentable {
    let image: NSImage
    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.imageScaling = .scaleProportionallyUpOrDown
        v.animates = true
        v.image = image
        return v
    }
    func updateNSView(_ v: NSImageView, context: Context) {
        if v.image !== image { v.image = image }
        v.animates = true
    }
}
