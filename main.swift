// NetSpeed — affiche la vitesse réseau (upload / download) dans la barre des menus.
import AppKit
import Darwin
import ServiceManagement
import SystemConfiguration

// MARK: - Lecture des compteurs réseau

struct Counters {
    var inBytes: UInt64 = 0
    var outBytes: UInt64 = 0
    var interface: String = "—"
}

/// Interface principale utilisée par macOS (ex. en0 pour le Wi-Fi).
func primaryInterface() -> String? {
    guard let store = SCDynamicStoreCreate(nil, "NetSpeed" as CFString, nil, nil),
          let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
    else { return nil }
    return dict["PrimaryInterface"] as? String
}

/// Interfaces qui ont une adresse IPv4, donc réellement connectées à un réseau (pour l'affichage).
func interfacesWithIPv4() -> Set<String> {
    var names = Set<String>()
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0 else { return names }
    var p = list
    while let ifa = p {
        if let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
            names.insert(String(cString: ifa.pointee.ifa_name))
        }
        p = ifa.pointee.ifa_next
    }
    freeifaddrs(list)
    return names
}

/// Lit les octets reçus / envoyés (compteurs 64 bits).
/// - allInterfaces = false : interface principale seulement.
/// - allInterfaces = true (ou pas d'interface principale) : additionne toutes les interfaces
///   physiques Wi-Fi / Ethernet (en0, en31…), sans les VPN ni les interfaces internes,
///   pour ne pas compter deux fois le même trafic.
func readCounters(allInterfaces: Bool = false) -> Counters {
    var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
    var len = 0
    guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return Counters() }
    var buf = [UInt8](repeating: 0, count: len)
    guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return Counters() }

    let primary = allInterfaces ? nil : primaryInterface()
    var result = Counters(interface: primary ?? "toutes")
    var active: [String] = []
    let connected = allInterfaces ? interfacesWithIPv4() : []
    let msgSize = MemoryLayout<if_msghdr2>.size

    buf.withUnsafeBytes { raw in
        var off = 0
        while off + MemoryLayout<if_msghdr>.size <= len {
            let hdr = raw.loadUnaligned(fromByteOffset: off, as: if_msghdr.self)
            let msgLen = Int(hdr.ifm_msglen)
            if msgLen == 0 { break }
            if Int32(hdr.ifm_type) == RTM_IFINFO2, off + msgSize + 8 <= len {
                let m = raw.loadUnaligned(fromByteOffset: off, as: if_msghdr2.self)
                // Le nom de l'interface suit l'en-tête, dans une structure sockaddr_dl.
                let sdl = off + msgSize
                let nameLen = Int(raw[sdl + 5])
                var name = ""
                if nameLen > 0, sdl + 8 + nameLen <= len {
                    name = String(decoding: raw[(sdl + 8)..<(sdl + 8 + nameLen)], as: UTF8.self)
                }
                let isLoopback = (m.ifm_flags & IFF_LOOPBACK) != 0
                let isEther = m.ifm_data.ifi_type == 6 // IFT_ETHER
                let isPhysical = isEther && !isLoopback && name.hasPrefix("en")
                let counts = primary != nil ? (name == primary) : isPhysical
                if counts {
                    result.inBytes += m.ifm_data.ifi_ibytes
                    result.outBytes += m.ifm_data.ifi_obytes
                    if primary == nil, connected.contains(name) { active.append(name) }
                }
            }
            off += msgLen
        }
    }
    if primary == nil { result.interface = "toutes (" + active.joined(separator: ", ") + ")" }
    return result
}

// MARK: - Mise en forme

func formatSpeed(_ bytesPerSec: Double) -> String {
    switch bytesPerSec {
    case ..<1_000_000:     return String(format: "%.0f Ko/s", bytesPerSec / 1_000)
    case ..<1_000_000_000: return String(format: "%.1f Mo/s", bytesPerSec / 1_000_000)
    default:               return String(format: "%.2f Go/s", bytesPerSec / 1_000_000_000)
    }
}

func formatTotal(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .decimal)
}

/// Image à deux lignes (↑ en haut, ↓ en bas), en mode « template » pour suivre le thème clair / sombre.
func makeImage(up: String, down: String) -> NSImage {
    let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
    let para = NSMutableParagraphStyle()
    para.alignment = .right
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: para, .foregroundColor: NSColor.black]
    let size = NSSize(width: 64, height: 22)
    let image = NSImage(size: size, flipped: false) { rect in
        let lineH: CGFloat = 10.5
        ("↑ " + up as NSString).draw(in: NSRect(x: 0, y: rect.height / 2 - 0.5, width: rect.width, height: lineH), withAttributes: attrs)
        ("↓ " + down as NSString).draw(in: NSRect(x: 0, y: rect.height / 2 - lineH, width: rect.width, height: lineH), withAttributes: attrs)
        return true
    }
    image.isTemplate = true
    return image
}

// MARK: - Application

final class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: 66)
    // Choix mémorisé entre deux lancements.
    var allInterfaces = UserDefaults.standard.bool(forKey: "allInterfaces")
    lazy var last = readCounters(allInterfaces: allInterfaces)
    var lastTime = Date()
    var sessionIn: UInt64 = 0
    var sessionOut: UInt64 = 0

    let interfaceItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let totalItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let primaryModeItem = NSMenuItem(title: "Interface principale", action: #selector(selectPrimary), keyEquivalent: "")
    let allModeItem = NSMenuItem(title: "Toutes les interfaces", action: #selector(selectAll), keyEquivalent: "")
    let loginItem = NSMenuItem(title: "Lancer à l'ouverture de session", action: #selector(toggleLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.image = makeImage(up: formatSpeed(0), down: formatSpeed(0))

        let menu = NSMenu()
        interfaceItem.isEnabled = false
        totalItem.isEnabled = false
        menu.addItem(interfaceItem)
        menu.addItem(totalItem)
        menu.addItem(.separator())
        primaryModeItem.target = self
        allModeItem.target = self
        menu.addItem(primaryModeItem)
        menu.addItem(allModeItem)
        menu.addItem(.separator())
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(NSMenuItem(title: "Quitter NetSpeed", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        refreshModeState()
        refreshLoginState()
        updateMenuText()

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common) // continue même quand le menu est ouvert
    }

    func tick() {
        let now = Date()
        let cur = readCounters(allInterfaces: allInterfaces)
        let dt = now.timeIntervalSince(lastTime)
        var down = 0.0, up = 0.0
        // Si l'interface change ou si un compteur repart à zéro, on repart d'une nouvelle base.
        if cur.interface == last.interface, cur.inBytes >= last.inBytes, cur.outBytes >= last.outBytes, dt > 0 {
            let dIn = cur.inBytes - last.inBytes
            let dOut = cur.outBytes - last.outBytes
            sessionIn += dIn
            sessionOut += dOut
            down = Double(dIn) / dt
            up = Double(dOut) / dt
        }
        last = cur
        lastTime = now
        statusItem.button?.image = makeImage(up: formatSpeed(up), down: formatSpeed(down))
        updateMenuText()
    }

    func updateMenuText() {
        interfaceItem.title = "Interface : \(last.interface)"
        totalItem.title = "Depuis le lancement : ↓ \(formatTotal(sessionIn))  ↑ \(formatTotal(sessionOut))"
    }

    @objc func selectPrimary() { setMode(all: false) }
    @objc func selectAll() { setMode(all: true) }

    func setMode(all: Bool) {
        allInterfaces = all
        UserDefaults.standard.set(all, forKey: "allInterfaces")
        // Nouvelle base de mesure pour ne pas afficher un faux pic au changement.
        last = readCounters(allInterfaces: all)
        lastTime = Date()
        refreshModeState()
        updateMenuText()
    }

    func refreshModeState() {
        primaryModeItem.state = allInterfaces ? .off : .on
        allModeItem.state = allInterfaces ? .on : .off
    }

    func refreshLoginState() {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Impossible de modifier le lancement automatique"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refreshLoginState()
    }
}

// Mode test : `NetSpeed --test` affiche 3 mesures dans le terminal puis quitte.
// Ajouter `--all` pour tester le mode « Toutes les interfaces ».
if CommandLine.arguments.contains("--test") {
    let all = CommandLine.arguments.contains("--all")
    var prev = readCounters(allInterfaces: all)
    print("Interface : \(prev.interface)")
    for _ in 0..<3 {
        Thread.sleep(forTimeInterval: 1)
        let cur = readCounters(allInterfaces: all)
        print("↓ \(formatSpeed(Double(cur.inBytes &- prev.inBytes)))   ↑ \(formatSpeed(Double(cur.outBytes &- prev.outBytes)))")
        prev = cur
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // pas d'icône dans le Dock
app.run()
