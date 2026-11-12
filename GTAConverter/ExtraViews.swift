import SwiftUI

private let extraBackground = Color(red: 0.035, green: 0.025, blue: 0.065)

struct AppearanceSettingsView: View {
    @AppStorage("gta_cover_style") private var coverStyle = "neon"
    @AppStorage("gta_accent_color") private var accentColor = "purple"

    private var selectedColor: Color {
        switch accentColor {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        default: return .purple
        }
    }

    var body: some View {
        ZStack {
            extraBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("مظهر GTA Converter").font(.title2.bold()).foregroundStyle(.white)
                        Text("غيّر ألوان الواجهة والغلاف الداخلي للتطبيق.").font(.caption).foregroundStyle(.white.opacity(0.6))
                        coverPreview
                    }.padding(17).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 20))

                    settingsGroup("لون التطبيق", icon: "paintpalette.fill") {
                        colorChoice("بنفسجي", value: "purple", color: .purple)
                        colorChoice("أزرق", value: "blue", color: .blue)
                        colorChoice("أخضر", value: "green", color: .green)
                        colorChoice("برتقالي", value: "orange", color: .orange)
                        colorChoice("أحمر", value: "red", color: .red)
                    }

                    settingsGroup("الغلاف الداخلي", icon: "rectangle.portrait.fill") {
                        coverChoice("نيون", value: "neon", detail: "تدرج لوني واضح")
                        coverChoice("داكن", value: "dark", detail: "أسود مع لمسة من اللون المختار")
                        coverChoice("بسيط", value: "minimal", detail: "خلفية هادئة")
                    }

                    Text("هذا يغيّر غلاف الصفحة الرئيسية داخل التطبيق. تغيير أيقونة التطبيق الفعلية من شاشة iPad يحتاج إعداد أيقونات بديلة داخل مشروع iOS، وليس مجرد تغيير لون من الإعدادات.")
                        .font(.caption).foregroundStyle(.white.opacity(0.52))
                        .padding(13).background(.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 12))
                }.padding(16)
            }
        }
        .navigationTitle("التصميم والغلاف")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var coverPreview: some View {
        HStack(spacing: 13) {
            Image(systemName: "car.side.fill").font(.system(size: 28)).foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(LinearGradient(colors: [selectedColor, selectedColor.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 4) {
                Text("GTA CONVERTER").font(.headline.bold()).foregroundStyle(.white)
                Text("MODS • TOOLS • CONVERTER").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Image(systemName: "checkmark.seal.fill").foregroundStyle(selectedColor)
        }
        .padding(15)
        .background(coverStyle == "minimal" ? Color.white.opacity(0.08) : coverStyle == "dark" ? Color.black.opacity(0.55) : selectedColor.opacity(0.24))
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(selectedColor.opacity(0.35)))
    }

    private func settingsGroup<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(.white)
            content()
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func colorChoice(_ title: String, value: String, color: Color) -> some View {
        Button { accentColor = value } label: {
            HStack {
                Circle().fill(color).frame(width: 20, height: 20)
                Text(title).foregroundStyle(.white)
                Spacer()
                if accentColor == value { Image(systemName: "checkmark.circle.fill").foregroundStyle(color) }
            }.padding(.vertical, 4)
        }.buttonStyle(.plain)
    }

    private func coverChoice(_ title: String, value: String, detail: String) -> some View {
        Button { coverStyle = value } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).foregroundStyle(.white)
                    Text(detail).font(.caption2).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                if coverStyle == value { Image(systemName: "checkmark.circle.fill").foregroundStyle(selectedColor) }
            }.padding(.vertical, 4)
        }.buttonStyle(.plain)
    }
}

struct FeatureHubView: View {
    var body: some View {
        ZStack {
            extraBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("مركز الميزات").font(.title2.bold()).foregroundStyle(.white)
                        Text("الأدوات الموجودة في النسخة الحالية.").font(.caption).foregroundStyle(.white.opacity(0.55))
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(17)
                    feature("فك ZIP وRAR", detail: "استخراج الملفات محلياً مع فحص المسارات.", icon: "archivebox.fill", state: "متاح")
                    feature("Auto وتصنيف يدوي", detail: "تحديد مسار السيارات أو الخرائط أو الشخصيات أو الملفات العامة.", icon: "arrow.triangle.2.circlepath", state: "متاح")
                    feature("تحليل المود", detail: "عدّ الملفات واكتشاف dlc.rpf وملفات Readme والأسماء المكررة.", icon: "doc.text.magnifyingglass", state: "متاح")
                    feature("مولّد dlclist.xml", detail: "إنشاء المسارات بصيغة Orbx المطلقة المطلوبة.", icon: "list.bullet.rectangle", state: "متاح")
                    feature("مستكشف الملفات", detail: "تصفح الملفات الناتجة ومشاركتها أو حذفها.", icon: "folder.fill", state: "متاح")
                    feature("تغيير الغلاف والألوان", detail: "تخصيص واجهة التطبيق من صفحة التصميم.", icon: "paintbrush.pointed.fill", state: "متاح")
                    feature("محرك تحويل PC إلى PS4", detail: "محرك Ps4tools السحابي مضاف. يحتاج تشغيل Workflow برابط تنزيل مباشر، والربط التلقائي من التطبيق ما زال قيد التطوير.", icon: "cloud.gear.fill", state: "تجريبي")
                }.padding(16)
            }
        }
        .navigationTitle("الميزات")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func feature(_ title: String, detail: String, icon: String, state: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(.purple)
                .frame(width: 43, height: 43).background(.purple.opacity(0.16)).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.subheadline.bold()).foregroundStyle(.white)
                    Spacer()
                    Text(state).font(.system(size: 10, weight: .bold))
                        .foregroundStyle(state == "متاح" ? .green : .orange)
                }
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.55))
            }
        }.padding(14).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 16))
    }
}


struct CloudConversionView: View {
    private let workflowURL = URL(string: "https://github.com/tmoath07-svg/ChatGPT-all-access-ios-/actions/workflows/convert-pc-to-ps4.yml")!
    var body: some View {
        ZStack {
            extraBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    VStack(alignment: .leading, spacing: 9) {
                        Image(systemName: "cloud.gear.fill").font(.system(size: 34)).foregroundStyle(.purple)
                        Text("محرك التحويل السحابي").font(.title2.bold()).foregroundStyle(.white)
                        Text("يشغّل أدوات Ps4tools الفعلية على خوادم GitHub Actions، لأن أدوات Windows وWine لا تعمل مباشرة داخل iPadOS.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 20))

                    cloudStep("1", title: "جهّز رابط المود", detail: "ارفع ملف ZIP أو RAR إلى مساحة ملفات تعطيك رابط تنزيل مباشر يمكن للخادم الوصول إليه.")
                    cloudStep("2", title: "اختر نوع التحويل", detail: "من صفحة GitHub اختر Run workflow، ثم حدد نوع العملية المناسب والصق رابط الملف في خانة URL.")
                    cloudStep("3", title: "نزّل الناتج", detail: "بعد انتهاء التشغيل افتح Artifacts ونزّل ملف النتيجة. ستجد ملفات PS4 والتقرير إذا نجحت العملية.")

                    Link(destination: workflowURL) {
                        Label("فتح محرك التحويل على GitHub", systemImage: "arrow.up.right.square")
                            .font(.headline.bold()).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(16)
                            .background(Color.purple.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Text("ملاحظة: هذه أول وصلة تشغيل للمحرك السحابي، وليست إرسالاً تلقائياً للملف المحلي من التطبيق. يلزم رابط تنزيل مباشر وتشغيل الـWorkflow يدوياً. لن نعرض التحويل كأنه مكتمل قبل نجاح تشغيل فعلي وفحص ملف الناتج.")
                        .font(.caption).foregroundStyle(.orange.opacity(0.9))
                        .padding(13).background(.orange.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12))
                }.padding(16)
            }
        }
        .navigationTitle("التحويل السحابي")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func cloudStep(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.headline.bold()).foregroundStyle(.white)
                .frame(width: 34, height: 34).background(.purple).clipShape(Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.bold()).foregroundStyle(.white)
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.58))
            }
            Spacer(minLength: 0)
        }.padding(14).background(.white.opacity(0.055)).clipShape(RoundedRectangle(cornerRadius: 15))
    }
}


struct CreatorPageView: View {
    private let creatorHandle = "Moa_sa7"
    private let tiktokURL = URL(string: "https://www.tiktok.com/@Moa_sa7")!

    var body: some View {
        ZStack {
            extraBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle().fill(
                                LinearGradient(colors: [.purple, Color(red: 0.22, green: 0.08, blue: 0.48)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                            ).frame(width: 104, height: 104)
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 65)).foregroundStyle(.white)
                        }
                        Text("المبدع").font(.title2.bold()).foregroundStyle(.white)
                        Text(creatorHandle).font(.title3.bold()).foregroundStyle(.purple)
                        Text("صاحب ومطوّر GTA Converter")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 28)
                    .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 24))

                    Link(destination: tiktokURL) {
                        HStack(spacing: 12) {
                            Image(systemName: "music.note").font(.title2)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("TikTok").font(.headline.bold())
                                Text("@\(creatorHandle)").font(.caption).opacity(0.75)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.headline)
                        }
                        .foregroundStyle(.white).padding(16)
                        .background(Color.purple.opacity(0.28))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("حقوق التطبيق", systemImage: "c.circle.fill")
                            .font(.headline).foregroundStyle(.white)
                        Text("© 2026 Moa_sa7. جميع الحقوق محفوظة.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.72))
                        Text("GTA Converter مشروع مستقل. العلامات التجارية وأسماء الألعاب المذكورة تعود لأصحابها.")
                            .font(.caption).foregroundStyle(.white.opacity(0.48))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16).background(.white.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 17))
                }.padding(16)
            }
        }
        .navigationTitle("المبدع")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
    }
}
