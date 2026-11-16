import SwiftUI
import PhotosUI
import UIKit

struct GTAOnboardingView: View {
    let onComplete: () -> Void
    @AppStorage("gta_language") private var language = "ar"
    @AppStorage("gta_accent_color") private var accent = "purple"
    @AppStorage("gta_background_color") private var background = "midnight"
    @AppStorage("gta_welcome_message") private var welcome = "حيّاك في GTA Converter"
    @State private var page = 0

    private var tint: Color {
        switch accent {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        default: return .purple
        }
    }

    var body: some View {
        ZStack {
            GTASetupBackground(style: background).ignoresSafeArea()
            VStack(spacing: 22) {
                HStack {
                    Text("GTA CONVERTER").font(.system(size: 13, weight: .black, design: .rounded)).tracking(2)
                    Spacer()
                    Text("1.80").font(.caption.monospaced()).foregroundStyle(.white.opacity(0.55))
                }.foregroundStyle(.white)
                Spacer()
                Group {
                    if page == 0 { languagePage }
                    else if page == 1 { appearancePage }
                    else { welcomePage }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                Spacer()
                HStack(spacing: 7) {
                    ForEach(0..<3) { index in
                        Capsule().fill(index == page ? tint : .white.opacity(0.2)).frame(width: index == page ? 25 : 7, height: 7)
                    }
                }
                Button {
                    withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) {
                        if page < 2 { page += 1 } else { onComplete() }
                    }
                } label: {
                    HStack {
                        Text(page == 2 ? (language == "ar" ? "ابدأ الاستخدام" : "Start using the app") : (language == "ar" ? "متابعة" : "Continue"))
                        Image(systemName: language == "ar" ? "arrow.left" : "arrow.right")
                    }
                    .font(.headline.bold()).foregroundStyle(.white).frame(maxWidth: .infinity).padding(17)
                    .background(LinearGradient(colors: [tint, tint.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 17))
                }.buttonStyle(.plain)
            }.padding(24)
        }.preferredColorScheme(.dark)
    }

    private var languagePage: some View {
        VStack(spacing: 18) {
            Image(systemName: "globe").font(.system(size: 48, weight: .light)).foregroundStyle(tint)
            Text(language == "ar" ? "اختر لغتك" : "Choose your language").font(.largeTitle.bold()).foregroundStyle(.white)
            Text(language == "ar" ? "تقدر تغيّرها لاحقاً من الإعدادات." : "You can change it later in Settings.").font(.subheadline).foregroundStyle(.white.opacity(0.65))
            choice("العربية", detail: "Arabic · RTL", selected: language == "ar") { language = "ar" }
            choice("English", detail: "English · LTR", selected: language == "en") { language = "en" }
        }
    }

    private var appearancePage: some View {
        VStack(alignment: .leading, spacing: 17) {
            Image(systemName: "slider.horizontal.3").font(.system(size: 42)).foregroundStyle(tint)
            Text(language == "ar" ? "صمّم واجهتك" : "Make it yours").font(.largeTitle.bold()).foregroundStyle(.white)
            Text(language == "ar" ? "اختر لون التطبيق والخلفية." : "Choose the app accent and background.").foregroundStyle(.white.opacity(0.65))
            Text(language == "ar" ? "لون الواجهة" : "Accent color").font(.headline).foregroundStyle(.white)
            HStack(spacing: 13) {
                ForEach(["purple","blue","green","orange","red"], id: \.self) { item in
                    Button { accent = item } label: {
                        Circle().fill(color(item)).frame(width: 39, height: 39)
                            .overlay(Circle().stroke(.white, lineWidth: accent == item ? 3 : 0).padding(-4))
                    }.buttonStyle(.plain)
                }
            }
            Text(language == "ar" ? "خلفية التطبيق" : "App background").font(.headline).foregroundStyle(.white)
            ForEach([("midnight","ليلي","Midnight"),("black","أسود","Black"),("navy","كحلي","Navy"),("graphite","فحمي","Graphite")], id: \.0) { item in
                choice(language == "ar" ? item.1 : item.2, detail: "", selected: background == item.0) { background = item.0 }
            }
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 17) {
            Image(systemName: "sparkles.rectangle.stack").font(.system(size: 50)).foregroundStyle(tint)
            Text(language == "ar" ? "رسالة الترحيب" : "Welcome message").font(.largeTitle.bold()).foregroundStyle(.white)
            Text(language == "ar" ? "اكتب العبارة اللي تظهر لك عند دخول البرنامج." : "Write the message shown when you open the app.").font(.subheadline).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center)
            TextField(language == "ar" ? "اكتب رسالتك..." : "Write your message...", text: $welcome, axis: .vertical)
                .lineLimit(2...4).padding(15).background(.white.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white)
            Text(welcome.isEmpty ? (language == "ar" ? "مرحباً بك في GTA Converter" : "Welcome to GTA Converter") : welcome)
                .font(.headline).foregroundStyle(.white).padding(18).frame(maxWidth: .infinity)
                .background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func choice(_ title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.white.opacity(0.55)) }
                }
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(tint) }
            }.foregroundStyle(.white).padding(15).frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.12)))
        }.buttonStyle(.plain)
    }

    private func color(_ value: String) -> Color {
        switch value { case "blue": return .blue; case "green": return .green; case "orange": return .orange; case "red": return .red; default: return .purple }
    }
}

struct GTASetupSettingsView: View {
    @AppStorage("gta_language") private var language = "ar"
    @AppStorage("gta_accent_color") private var accent = "purple"
    @AppStorage("gta_background_color") private var background = "midnight"
    @AppStorage("gta_welcome_message") private var welcome = "حيّاك في GTA Converter"

    var body: some View {
        ZStack {
            GTASetupBackground(style: background).ignoresSafeArea()
            Form {
                Section(language == "ar" ? "اللغة" : "Language") {
                    Picker(language == "ar" ? "لغة التطبيق" : "App language", selection: $language) {
                        Text("العربية").tag("ar")
                        Text("English").tag("en")
                    }.pickerStyle(.segmented)
                }
                Section(language == "ar" ? "لون التطبيق" : "Accent color") {
                    Picker(language == "ar" ? "اللون" : "Color", selection: $accent) {
                        Text(language == "ar" ? "بنفسجي" : "Purple").tag("purple")
                        Text(language == "ar" ? "أزرق" : "Blue").tag("blue")
                        Text(language == "ar" ? "أخضر" : "Green").tag("green")
                        Text(language == "ar" ? "برتقالي" : "Orange").tag("orange")
                        Text(language == "ar" ? "أحمر" : "Red").tag("red")
                    }
                }
                Section(language == "ar" ? "الخلفية" : "Background") {
                    Picker(language == "ar" ? "الخلفية" : "Background", selection: $background) {
                        Text(language == "ar" ? "ليلي" : "Midnight").tag("midnight")
                        Text(language == "ar" ? "أسود" : "Black").tag("black")
                        Text(language == "ar" ? "كحلي" : "Navy").tag("navy")
                        Text(language == "ar" ? "فحمي" : "Graphite").tag("graphite")
                    }
                }
                Section(language == "ar" ? "رسالة الترحيب" : "Welcome message") {
                    TextField(language == "ar" ? "رسالتك" : "Your message", text: $welcome, axis: .vertical)
                }
            }
            .scrollContentBackground(.hidden)
            .foregroundStyle(.white)
            .tint(accent == "blue" ? .blue : accent == "green" ? .green : accent == "orange" ? .orange : accent == "red" ? .red : .purple)
        }
        .navigationTitle(language == "ar" ? "التخصيص واللغة" : "Appearance & Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GTASetupBackground: View {
    let style: String
    var body: some View {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    private var colors: [Color] {
        switch style {
        case "black": return [.black, Color(white: 0.035), .black]
        case "navy": return [Color(red: 0.015, green: 0.04, blue: 0.13), .black]
        case "graphite": return [Color(white: 0.12), Color(white: 0.025)]
        default: return [Color(red: 0.06, green: 0.025, blue: 0.12), .black]
        }
    }
}
