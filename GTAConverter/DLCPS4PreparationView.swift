import SwiftUI

struct DLCPS4PreparationView: View {
    let root: URL
    let dlcFiles: [String]
    let packNames: [String]

    @State private var packageURL: URL?
    @State private var status = "سيجمع ملفات DLC المكتشفة داخل بنية Orbx المطلوبة للـPS4."
    @State private var isError = false
    @State private var isBusy = false

    private let background = Color(red: 0.035, green: 0.025, blue: 0.065)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 34)).foregroundStyle(.purple)
                        Text("تجهيز حزم Orbx للـPS4")
                            .font(.title2.bold()).foregroundStyle(.white)
                        Text("سيتم نسخ كل مجلد يحتوي على dlc.rpf إلى مسار Orbx المطلق، وإنشاء dlclist.xml بأسماء الحزم المكتشفة.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 9) {
                        Label("الحزم المكتشفة: \(packNames.count)", systemImage: "checkmark.circle.fill")
                            .font(.headline).foregroundStyle(.green)
                        ForEach(packNames, id: \.self) { name in
                            HStack {
                                Image(systemName: "folder.fill").foregroundStyle(.purple)
                                Text(name).font(.subheadline.monospaced()).foregroundStyle(.white)
                                Spacer()
                                Text("DLC").font(.caption2.bold()).foregroundStyle(.white.opacity(0.45))
                            }.padding(10).background(.black.opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(16).background(.white.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                    Button(action: buildPackage) {
                        Label(isBusy ? "جاري تجهيز الحزم..." : "تجهيز حزم PS4 وملف XML",
                              systemImage: "shippingbox.and.arrow.down.fill")
                            .font(.headline.bold()).frame(maxWidth: .infinity).padding(16)
                            .background(Color.purple.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    .disabled(isBusy || dlcFiles.isEmpty || packNames.isEmpty)
                    .opacity(isBusy || dlcFiles.isEmpty || packNames.isEmpty ? 0.5 : 1)

                    if let packageURL {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("تم إنشاء حزمة Orbx", systemImage: "checkmark.seal.fill")
                                .font(.headline).foregroundStyle(.green)
                            Text(packageURL.lastPathComponent).font(.caption).foregroundStyle(.white.opacity(0.65))
                            ShareLink(item: packageURL) {
                                Label("تصدير مجلد الحزم", systemImage: "square.and.arrow.up")
                                    .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(13)
                                    .background(.white.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(15).background(.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    Text(status)
                        .font(.caption).foregroundStyle(isError ? .red : .white.opacity(0.68))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(13).background(.white.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 7) {
                        Label("مهم للتوافق الفعلي", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.bold()).foregroundStyle(.orange)
                        Text("هذه الخطوة تجهّز بنية Orbx وملف dlclist.xml فقط. لا تحوّل محتوى dlc.rpf من PC إلى PS4 ولا تغيّر صيغ الملفات الداخلية. إذا كانت ملفات RPF أصلها PC، فلا تعتبر الحزمة متوافقة مع PS4 حتى تمر بمرحلة تحويل Ps4tools الفعلية ثم فحص الناتج.")
                            .font(.caption).foregroundStyle(.white.opacity(0.68))
                    }
                    .padding(14).background(.orange.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }.padding(16)
            }
        }
        .navigationTitle("حزم PS4")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func buildPackage() {
        isBusy = true
        isError = false
        status = "جاري التحقق من ملفات DLC ونسخها..."
        Task.detached(priority: .userInitiated) {
            do {
                let fm = FileManager.default
                let safeNames = packNames.filter {
                    $0.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil
                }
                guard safeNames.count == packNames.count,
                      Set(safeNames).count == safeNames.count else {
                    throw NSError(domain: "GTAConverter.DLC", code: 10,
                                  userInfo: [NSLocalizedDescriptionKey: "أسماء الحزم غير صالحة أو مكررة."])
                }
                guard dlcFiles.count == safeNames.count else {
                    throw NSError(domain: "GTAConverter.DLC", code: 11,
                                  userInfo: [NSLocalizedDescriptionKey: "عدد ملفات dlc.rpf لا يطابق عدد أسماء الحزم."])
                }

                let ready = try fm.url(for: .documentDirectory, in: .userDomainMask,
                                       appropriateFor: nil, create: true)
                    .appendingPathComponent("GTA Converter/Ready", isDirectory: true)
                try fm.createDirectory(at: ready, withIntermediateDirectories: true)
                let output = ready.appendingPathComponent("PS4-Orbx-\(UUID().uuidString)", isDirectory: true)
                let addonRoot = output.appendingPathComponent("data/orbx/gta/rpf/dlc_addon", isDirectory: true)
                try fm.createDirectory(at: addonRoot, withIntermediateDirectories: true)

                var copied = Set<String>()
                for (index, rawPath) in dlcFiles.enumerated() {
                    let normalized = rawPath.replacingOccurrences(of: "\\", with: "/")
                    let parts = normalized.split(separator: "/", omittingEmptySubsequences: true)
                    guard !normalized.hasPrefix("/"), !parts.contains(".."), !parts.contains("."),
                          parts.last?.lowercased() == "dlc.rpf", parts.count >= 2 else {
                        throw NSError(domain: "GTAConverter.DLC", code: 12,
                                      userInfo: [NSLocalizedDescriptionKey: "مسار DLC غير آمن أو غير صالح: \(rawPath)"])
                    }
                    let sourceFile = root.appendingPathComponent(parts.map(String.init).joined(separator: "/"))
                    let sourceFolder = sourceFile.deletingLastPathComponent()
                    var isDirectory: ObjCBool = false
                    guard fm.fileExists(atPath: sourceFile.path),
                          fm.fileExists(atPath: sourceFolder.path, isDirectory: &isDirectory),
                          isDirectory.boolValue else {
                        throw NSError(domain: "GTAConverter.DLC", code: 13,
                                      userInfo: [NSLocalizedDescriptionKey: "ملف DLC غير موجود بعد الفك: \(rawPath)"])
                    }
                    let name = safeNames[index]
                    guard !copied.contains(name) else {
                        throw NSError(domain: "GTAConverter.DLC", code: 14,
                                      userInfo: [NSLocalizedDescriptionKey: "اسم حزمة مكرر: \(name)"])
                    }
                    let destination = addonRoot.appendingPathComponent(name, isDirectory: true)
                    try fm.copyItem(at: sourceFolder, to: destination)
                    copied.insert(name)
                }

                let entries = safeNames.map {
                    "        <Item>/data/orbx/gta/rpf/dlc_addon/\($0)/</Item>"
                }.joined(separator: "\n")
                let xml = """
                <?xml version="1.0" encoding="UTF-8"?>
                <SMandatoryPacksData>
                  <Paths>
                \(entries)
                  </Paths>
                </SMandatoryPacksData>
                """
                try xml.write(to: output.appendingPathComponent("dlclist.xml"),
                              atomically: true, encoding: .utf8)

                let note = """
                GTA Converter - PS4 Orbx Package
                Creator: Moa_sa7

                Copy the data/orbx/gta/rpf/dlc_addon folders into the matching Orbx path on PS4.
                Merge the entries from dlclist.xml into the PS4 dlclist.xml.

                IMPORTANT:
                This package step only arranges files and creates Orbx paths.
                It does NOT convert PC RPF archives or internal game assets to PS4 format.
                Run the actual PC-to-PS4 conversion engine and validate its output first.
                """
                try note.write(to: output.appendingPathComponent("INSTALL-PS4.txt"),
                               atomically: true, encoding: .utf8)

                await MainActor.run {
                    packageURL = output
                    status = "اكتمل تجهيز \(copied.count) حزم وملف dlclist.xml. لم يتم تحويل محتوى RPF."
                    isBusy = false
                    isError = false
                }
            } catch {
                await MainActor.run {
                    status = "فشل تجهيز الحزم: \(error.localizedDescription)"
                    isBusy = false
                    isError = true
                }
            }
        }
    }
}
