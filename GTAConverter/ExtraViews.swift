import SwiftUI
import CryptoKit
import UIKit

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
    @State private var searchText = ""
    @State private var selectedCategory = "الكل"

    private let categories = ["الكل", "الملفات", "السيارات", "PS4", "PlayStation", "الذكاء الاصطناعي", "الإدارة"]
    private let items: [FeatureCatalogItem] = [
        .init(id:1,title:"محلل المودات الذكي",category:"الملفات",icon:"doc.text.magnifyingglass",status:"متاح",detail:"تحليل الأرشيفات والملفات واكتشاف مكونات المود. افتح شاشة الاستيراد والتحليل من الصفحة الرئيسية.",live:true),
        .init(id:2,title:"مختبر YTD",category:"الملفات",icon:"photo.stack.fill",status:"فحص متاح",detail:"اختيار ملفات YTD وفحص الحجم وترويسة RSC7. استخراج DDS وإعادة بناء YTD والتحويل الفعلي تحتاج محرك معالجة مختبراً.",route:"ytd"),
        .init(id:3,title:"عارض YDR وYFT",category:"السيارات",icon:"cube.transparent",status:"قيد التطوير",detail:"معاينة المجسمات والخامات تتطلب قارئ صيغ RAGE وتحويلها إلى نموذج قابل للعرض."),
        .init(id:4,title:"محرر Hex",category:"الملفات",icon:"chevron.left.forwardslash.chevron.right",status:"مخطط",detail:"عارض ومحرر بيانات ثنائية مع حماية من تعديل الملفات الأصلية بالخطأ."),
        .init(id:5,title:"كاشف أخطاء المودات",category:"الملفات",icon:"stethoscope",status:"جزئي",detail:"التحليل الحالي يكشف بعض الملفات والمكونات. فحص الاعتماديات والتوافق الشامل يحتاج قواعد إضافية."),
        .init(id:6,title:"منشئ DLC سيارات",category:"السيارات",icon:"car.side.fill",status:"تجهيز متاح",detail:"تجهيز هيكل DLC ومسارات Orbx وملف dlclist. تحويل محتوى PC نفسه يحتاج محرك التحويل السحابي.",route:"dlc"),
        .init(id:7,title:"فاحص ملفات السيارة",category:"السيارات",icon:"car.rear.fill",status:"جزئي",detail:"فحص وجود الملفات المعروفة ممكن ضمن التحليل. التحقق من صحة كل بنية YFT/YTD يحتاج محللات متخصصة."),
        .init(id:8,title:"استوديو ألوان السيارات",category:"السيارات",icon:"paintpalette.fill",status:"مخطط",detail:"معاينة وتعديل ألوان الخامات تتطلب فك YTD ومحرر خامات."),
        .init(id:9,title:"محلل Handling",category:"السيارات",icon:"gauge.with.dots.needle.67percent",status:"مخطط",detail:"قراءة وعرض قيم handling.meta مع مقارنة القيم وتفسيرها."),
        .init(id:10,title:"معرض موداتك",category:"السيارات",icon:"rectangle.stack.fill",status:"مخطط",detail:"مكتبة منظمة للسيارات والمودات مع صور وأسماء وبيانات كل مشروع."),
        .init(id:11,title:"AI Mod Scanner",category:"الذكاء الاصطناعي",icon:"sparkles",status:"مخطط",detail:"تحليل وصف المود وملفاته وتقديم تقرير مفهوم. يحتاج ربط خدمة ذكاء اصطناعي وموافقة المستخدم على إرسال الملفات."),
        .init(id:12,title:"AI Error Fixer",category:"الذكاء الاصطناعي",icon:"wrench.and.screwdriver.fill",status:"مخطط",detail:"تحليل سجلات الأخطاء واقتراح إصلاحات قابلة للمراجعة قبل تطبيقها."),
        .init(id:13,title:"AI XML Builder",category:"الذكاء الاصطناعي",icon:"curlybraces",status:"مخطط",detail:"إنشاء XML من أسماء الحزم والتحقق من صياغته ومسارات Orbx."),
        .init(id:14,title:"AI DLC Assistant",category:"الذكاء الاصطناعي",icon:"shippingbox.fill",status:"مخطط",detail:"مساعد يشرح بنية DLC وينبه إلى المكونات الناقصة."),
        .init(id:15,title:"AI Vehicle Finder",category:"الذكاء الاصطناعي",icon:"car.side",status:"مخطط",detail:"تخمين نوع السيارة من أسماء الملفات والبيانات والصور، مع توضيح نسبة الثقة."),
        .init(id:16,title:"AI Texture Inspector",category:"الذكاء الاصطناعي",icon:"eye.fill",status:"مخطط",detail:"تحليل أبعاد الخامات وصيغها بعد استخراجها وعرض المشكلات المحتملة."),
        .init(id:17,title:"AI Mod Translator",category:"الذكاء الاصطناعي",icon:"character.bubble",status:"مخطط",detail:"ترجمة ملفات Readme وأوصاف المود مع الحفاظ على أسماء الملفات."),
        .init(id:18,title:"AI Compatibility",category:"الذكاء الاصطناعي",icon:"checkmark.shield.fill",status:"مخطط",detail:"تقييم توافق الملفات مع إصدار اللعبة بناءً على قواعد موثقة ونتائج فحص فعلية."),
        .init(id:19,title:"PS4 Package Studio",category:"PS4",icon:"shippingbox",status:"مخطط",detail:"تنظيم مخرجات التحويل في حزم واضحة مع تقرير محتوياتها."),
        .init(id:20,title:"XML Studio",category:"PS4",icon:"list.bullet.rectangle",status:"جزئي",detail:"مولد dlclist موجود ضمن تجهيز Orbx. محرر XML تفاعلي شامل ما زال يحتاج بناء.",route:"dlc"),
        .init(id:21,title:"Cloud Converter",category:"PS4",icon:"cloud.gear.fill",status:"متاح يدوياً",detail:"محرك Ps4tools موجود في GitHub Actions. تشغيله حالياً يتم من GitHub يدوياً برابط تنزيل مباشر.",route:"cloud"),
        .init(id:22,title:"مقارنة إصدارات المود",category:"الملفات",icon:"arrow.left.arrow.right",status:"مخطط",detail:"مقارنة قائمتين من الملفات وإظهار الملفات الجديدة والمعدلة والمحذوفة."),
        .init(id:23,title:"مدير DLC",category:"PS4",icon:"folder.badge.gearshape",status:"تجهيز متاح",detail:"إدارة مخرجات DLC ومسارات Orbx وملف dlclist.",route:"dlc"),
        .init(id:24,title:"Mod Marketplace",category:"الإدارة",icon:"storefront",status:"مخطط",detail:"كتالوج مودات وروابطها ومعلومات التوافق. لن يستضيف ملفات محمية أو يعيد توزيعها دون إذن."),
        .init(id:25,title:"Mod Cloud Library",category:"الإدارة",icon:"cloud.fill",status:"مخطط",detail:"مزامنة مكتبة المشاريع والملفات عبر تخزين سحابي يختاره المستخدم."),
        .init(id:26,title:"One Click Build",category:"PS4",icon:"bolt.fill",status:"مخطط",detail:"تشغيل سلسلة فحوص وتجهيز وتحويل وتغليف بعد ربط كل مراحل المحرك."),
        .init(id:27,title:"Mod Timeline",category:"الإدارة",icon:"timeline.selection",status:"مخطط",detail:"سجل زمني لكل تعديل وعملية تحويل ونتيجة بناء."),
        .init(id:28,title:"Batch Converter",category:"PS4",icon:"square.stack.3d.up.fill",status:"مخطط",detail:"إرسال عدة مودات إلى طابور معالجة سحابي مع تقرير منفصل لكل مود."),
        .init(id:29,title:"Mod Preview",category:"الملفات",icon:"play.rectangle",status:"جزئي",detail:"معاينة الصور والملفات المدعومة. معاينة المجسمات تتطلب عارضاً ثلاثي الأبعاد."),
        .init(id:30,title:"Auto DLC Naming",category:"PS4",icon:"tag.fill",status:"مخطط",detail:"اقتراح أسماء مجلدات DLC آمنة وفريدة مع فحص التعارض."),
        .init(id:31,title:"Smart Folder",category:"الملفات",icon:"folder.badge.plus",status:"مخطط",detail:"ترتيب الملفات حسب نوعها وبنيتها مع إبقاء نسخة المصدر دون تغيير."),
        .init(id:32,title:"Build History",category:"الإدارة",icon:"clock.arrow.circlepath",status:"جزئي",detail:"سجل عمليات GitHub Actions متاح من صفحة التشغيل. سجل داخل التطبيق يحتاج ربط API.",route:"cloud"),
        .init(id:33,title:"Mod Report PDF",category:"الإدارة",icon:"doc.richtext",status:"مخطط",detail:"تصدير تقرير تحليل وفحص شامل بصيغة PDF."),
        .init(id:34,title:"PS4 Compatibility Score",category:"PS4",icon:"chart.bar.xaxis",status:"مخطط",detail:"درجة مبنية على اختبارات واضحة، وليست ضماناً للتشغيل على الجهاز."),
        .init(id:35,title:"Mod Backup",category:"الإدارة",icon:"externaldrive.fill",status:"جزئي",detail:"يمكن حفظ الملفات الناتجة في تطبيق الملفات. نسخ احتياطي بإصدارات واستعادة تلقائية ما زال مخططاً."),
        .init(id:36,title:"Project Templates",category:"الإدارة",icon:"square.grid.2x2.fill",status:"مخطط",detail:"قوالب جاهزة لمشاريع السيارات والخرائط والشخصيات والملفات العامة."),
        .init(id:37,title:"Dependency Checker",category:"الملفات",icon:"point.3.connected.trianglepath.dotted",status:"مخطط",detail:"كشف الملفات التي تشير إلى ملفات أخرى وتحديد الاعتماديات الناقصة."),
        .init(id:38,title:"RPF Explorer",category:"الملفات",icon:"archivebox.fill",status:"مخطط",detail:"استعراض شجرة RPF واستخراج الملفات باستخدام أدوات متوافقة."),
        .init(id:39,title:"Texture Converter",category:"الملفات",icon:"photo.artframe",status:"مخطط",detail:"تحويل الخامات بين الصيغ المدعومة بعد استخراجها مع الحفاظ على الجودة والأبعاد."),
        .init(id:40,title:"Mod Installer Guide",category:"PS4",icon:"book.closed.fill",status:"مخطط",detail:"دليل تركيب مرتب يوضح المسارات والمتطلبات وخطوات التحقق."),
        .init(id:41,title:"Chiaki Remote Play",category:"PlayStation",icon:"gamecontroller.fill",status:"دليل وتجهيز",detail:"مركز Chiaki لمشروع Remote Play ومعلومات دعم iOS وروابط المشروع الرسمية.",route:"chiaki"),
        .init(id:42,title:"File Hash Inspector",category:"الملفات",icon:"number.square",status:"متاح",detail:"حساب بصمة SHA-256 للملفات محلياً على الآيباد للتحقق من تطابق النسخ وسلامة النقل.",route:"hash"),
        .init(id:43,title:"Orbx DLC Validator",category:"PS4",icon:"checkmark.seal.fill",status:"متاح",detail:"فحص أسماء حزم DLC وكشف التكرار والأسماء غير الصالحة وإنشاء مسارات Orbx بصيغة PS4 المطلقة.",route:"dlcvalidator")
    ]

    private var filteredItems: [FeatureCatalogItem] {
        items.filter { item in
            (selectedCategory == "الكل" || item.category == selectedCategory) &&
            (searchText.isEmpty || item.title.localizedCaseInsensitiveContains(searchText) || item.detail.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        ZStack {
            extraBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "square.grid.3x3.fill").font(.title2).foregroundStyle(.purple)
                            Text("مركز الميزات").font(.title2.bold()).foregroundStyle(.white)
                            Spacer()
                            Text("40 أداة").font(.caption.bold()).foregroundStyle(.purple)
                        }
                        Text("كل أفكار الاستوديو في مكان واحد. الحالة توضّح الموجود فعلياً والمخطط له.")
                            .font(.caption).foregroundStyle(.white.opacity(0.62))
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 18))

                    HStack(spacing: 8) {
                        catalogStat("جاهز", value: "5", color: .green)
                        catalogStat("جزئي / تجريبي", value: "8", color: .orange)
                        catalogStat("مخطط", value: "27", color: .gray)
                    }

                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.55))
                        TextField("ابحث عن ميزة...", text: $searchText)
                            .foregroundStyle(.white).autocorrectionDisabled()
                    }.padding(12).background(.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 12))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(categories, id: \.self) { category in
                                Button { selectedCategory = category } label: {
                                    Text(category).font(.caption.bold()).padding(.horizontal, 13).padding(.vertical, 9)
                                        .background(selectedCategory == category ? Color.purple : Color.white.opacity(0.08))
                                        .foregroundStyle(.white).clipShape(Capsule())
                                }.buttonStyle(.plain)
                            }
                        }
                    }

                    LazyVStack(spacing: 9) {
                        ForEach(filteredItems) { item in
                            NavigationLink(destination: destination(for: item)) {
                                HStack(spacing: 12) {
                                    Image(systemName: item.icon).font(.title3).foregroundStyle(.purple)
                                        .frame(width: 43, height: 43)
                                        .background(.purple.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 12))
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack {
                                            Text(String(format: "%02d", item.id)).font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.35))
                                            Text(item.title).font(.subheadline.bold()).foregroundStyle(.white)
                                            Spacer(minLength: 4)
                                            Text(item.status).font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(statusColor(item.status))
                                        }
                                        Text(item.detail).font(.caption).foregroundStyle(.white.opacity(0.58)).lineLimit(2)
                                    }
                                    Image(systemName: "chevron.left").font(.caption2).foregroundStyle(.white.opacity(0.35))
                                }.padding(12).background(.white.opacity(0.055)).clipShape(RoundedRectangle(cornerRadius: 15))
                            }.buttonStyle(.plain)
                        }
                    }
                    if filteredItems.isEmpty {
                        Text("ما لقيت ميزة بهذا الاسم.").font(.caption).foregroundStyle(.white.opacity(0.6)).frame(maxWidth: .infinity).padding(24)
                    }
                }.padding(16)
            }
        }
        .navigationTitle("الميزات")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
    }

    @ViewBuilder private func destination(for item: FeatureCatalogItem) -> some View {
        switch item.route {
        case "ytd": YTDTextureLabView()
        case "cloud": CloudConversionView()
        case "chiaki": ChiakiRemotePlayView()
        case "hash": FileHashInspectorView()
        case "dlcvalidator": OrbxDLCValidatorView()
        case "dlc": FeatureInfoView(item: item)
        default: FeatureInfoView(item: item)
        }
    }

    private func catalogStat(_ title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.bold()).foregroundStyle(color)
            Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.6))
        }.frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statusColor(_ status: String) -> Color {
        if status == "متاح" || status == "تجهيز متاح" { return .green }
        if status == "فحص متاح" || status == "متاح يدوياً" || status == "جزئي" { return .orange }
        return .gray
    }
}

private struct FeatureCatalogItem: Identifiable {
    let id: Int
    let title: String
    let category: String
    let icon: String
    let status: String
    let detail: String
    var live = false
    var route: String? = nil
}

private struct FeatureInfoView: View {
    let item: FeatureCatalogItem
    var body: some View {
        ZStack {
            extraBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: item.icon).font(.system(size: 42)).foregroundStyle(.purple)
                Text(item.title).font(.title2.bold()).foregroundStyle(.white)
                Text(item.category).font(.caption.bold()).foregroundStyle(.purple)
                Text(item.status).font(.subheadline.bold()).foregroundStyle(item.status == "مخطط" ? .gray : .orange)
                Text(item.detail).font(.body).foregroundStyle(.white.opacity(0.75))
                Text("هذه الميزة مدرجة في خارطة الطريق. لن تظهر كميزة مكتملة حتى تتم برمجتها واختبارها.")
                    .font(.caption).foregroundStyle(.orange)
                    .padding(13).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12))
                Spacer()
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("تفاصيل الميزة")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
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
                        Text("يشغّل أدوات بناء وتحويل GTA V على خوادم GitHub Actions بدلاً من تحميل المعالجة على الآيباد.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 12) {
                        Label("FiveM إلى PS4 DLC", systemImage: "car.side.fill")
                            .font(.title3.bold()).foregroundStyle(.white)
                        Text("مسار مخصص لموارد FiveM التي تحتوي مودات سيارات وملفات META. المحرك يجمع ملفات السيارات وبياناتها ويبني DLC بصيغة RPF، ثم يحوّل الموارد الناتجة إلى بنية PS4.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.72))
                        VStack(alignment: .leading, spacing: 7) {
                            Label("المجلد المتوقع", systemImage: "folder.fill")
                                .font(.caption.bold()).foregroundStyle(.purple)
                            Text("resource/stream/ و resource/data/، مع مجلد مستقل لكل سيارة داخل stream ومجلد META مطابق لها داخل data.")
                                .font(.caption).foregroundStyle(.white.opacity(0.65))
                            Label("الملفات المطلوبة لكل سيارة", systemImage: "doc.text.fill")
                                .font(.caption.bold()).foregroundStyle(.purple)
                            Text("YFT وملفات META الأساسية: vehicles.meta و handling.meta و carvariations.meta. قد تحتاج ملفات إضافية حسب المود.")
                                .font(.caption).foregroundStyle(.white.opacity(0.65))
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.22)).clipShape(RoundedRectangle(cornerRadius: 13))
                        Link(destination: workflowURL) {
                            Label("فتح تحويل FiveM إلى DLC", systemImage: "arrow.up.right.square")
                                .font(.headline.bold()).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(15)
                                .background(Color.purple.opacity(0.88))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        Text("في GitHub اختر Run workflow ثم: «تحويل مود FiveM متعدد السيارات إلى DLC للسوني». ضع رابط ZIP/RAR مباشر في خانة URL، أو ارفع المورد داخل مجلد input. بعد نجاح التشغيل نزّل Artifact وافحص التقرير قبل تثبيته.")
                            .font(.caption).foregroundStyle(.white.opacity(0.68))
                        Text("تنبيه توافق: هذا المسار مخصص لحزم السيارات ذات البنية المذكورة، وليس كل موارد FiveM. سكربتات Lua وواجهات NUI والاعتماديات الخاصة بسيرفر FiveM لا تتحول تلقائياً إلى DLC للعبة PS4.")
                            .font(.caption.bold()).foregroundStyle(.orange)
                            .padding(11).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.09)).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(16).background(.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("التحويلات الأخرى").font(.headline).foregroundStyle(.white)
                        cloudStep("1", title: "جهّز رابط المود", detail: "ارفع ZIP أو RAR إلى مساحة ملفات تعطيك رابط تنزيل مباشر يمكن للخادم الوصول إليه.")
                        cloudStep("2", title: "اختر نوع التحويل", detail: "من صفحة GitHub اختر Run workflow، ثم حدد العملية المناسبة والصق رابط الملف في خانة URL.")
                        cloudStep("3", title: "نزّل الناتج", detail: "بعد انتهاء التشغيل افتح Artifacts ونزّل ملف النتيجة والتقرير.")
                        Link(destination: workflowURL) {
                            Label("فتح جميع خيارات محرك التحويل", systemImage: "arrow.up.right.square")
                                .font(.headline.bold()).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(16)
                                .background(Color.white.opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(16).background(.white.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 17))

                    Text("ملاحظة: التشغيل السحابي الحالي يبدأ من GitHub Actions يدوياً، ولا يرفع الملف المحلي من التطبيق تلقائياً. لا تعتبر النتيجة جاهزة إلا إذا انتهى التشغيل بنجاح وظهر Artifact صالح.")
                        .font(.caption).foregroundStyle(.white.opacity(0.52))
                        .padding(13).background(.black.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }.padding(16)
            }
        }
        .navigationTitle("التحويل السحابي")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\\.layoutDirection, .rightToLeft)
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


struct ChiakiRemotePlayView: View {
    private let projectURL = URL(string: "https://github.com/chiaki-ng/chiaki-ng")!
    private let releaseURL = URL(string: "https://github.com/chiaki-ng/chiaki-ng/releases")!
    private let sonyURL = URL(string: "https://apps.apple.com/app/ps-remote-play/id1436192460")!

    var body: some View {
        ZStack {
            extraBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 38)).foregroundStyle(.purple)
                        Text("Chiaki Remote Play")
                            .font(.title2.bold()).foregroundStyle(.white)
                        Text("مركز PlayStation Remote Play داخل GTA Converter")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 8) {
                        Label("حالة دعم iPadOS", systemImage: "info.circle.fill")
                            .font(.headline).foregroundStyle(.white)
                        Text("مشروع Chiaki-ng أضاف دعم تجميع iOS/tvOS، لكن هذا لا يعني وجود تطبيق iOS جاهز أو محرك بث مدمج داخل GTA Converter. دمج البث فعلياً يحتاج بناء واجهة iOS وربط الفيديو والصوت والتحكم والتسجيل.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.72))
                        Text("لن أعرض زر اتصال وهمي أو أوهمك أن مشاركة الشاشة تعمل قبل دمج المحرك واختباره.")
                            .font(.caption.bold()).foregroundStyle(.orange)
                            .padding(11).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.09))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(16).background(.white.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 17))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("مصادر المشروع")
                            .font(.headline).foregroundStyle(.white)
                        Link(destination: projectURL) {
                            Label("مستودع Chiaki-ng الرسمي", systemImage: "chevron.left.forwardslash.chevron.right")
                                .font(.subheadline.bold()).foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                                .background(.purple.opacity(0.25))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        Link(destination: releaseURL) {
                            Label("إصدارات المشروع", systemImage: "arrow.down.circle")
                                .font(.subheadline.bold()).foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                                .background(.white.opacity(0.07))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        Link(destination: sonyURL) {
                            Label("PS Remote Play الرسمي للآيفون والآيباد", systemImage: "play.rectangle")
                                .font(.subheadline.bold()).foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                                .background(.white.opacity(0.07))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(16).background(.white.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 17))

                    Text("ملاحظة: روابط المشروع خارجية. هذه الصفحة لا تنشئ اتصالاً بجهاز PlayStation ولا تطلب بيانات حساب PSN.")
                        .font(.caption).foregroundStyle(.white.opacity(0.48))
                        .padding(.horizontal, 3)
                }.padding(16)
            }
        }
        .navigationTitle("Chiaki")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
    }
}


struct FileHashInspectorView: View {
    @State private var showingPicker = false
    @State private var isBusy = false
    @State private var report = "اختر ملفاً أو عدة ملفات لحساب بصمة SHA-256."
    
    var body: some View {
        ZStack {
            extraBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    VStack(alignment: .leading, spacing: 9) {
                        Image(systemName: "number.square").font(.system(size: 38)).foregroundStyle(.purple)
                        Text("فاحص بصمة الملفات").font(.title2.bold()).foregroundStyle(.white)
                        Text("احسب SHA-256 محلياً على جهازك، بدون رفع الملفات إلى أي خادم.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 20))
                    
                    Button { showingPicker = true } label: {
                        Label("اختيار ملفات للفحص", systemImage: "doc.badge.magnifyingglass")
                            .font(.headline.bold()).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(16)
                            .background(Color.purple.opacity(0.82))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }.disabled(isBusy)
                    
                    if isBusy {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("جاري حساب البصمات...").font(.subheadline.bold()).foregroundStyle(.white)
                        }.padding(14)
                    }
                    
                    VStack(alignment: .leading, spacing: 9) {
                        Text("نتيجة الفحص").font(.headline).foregroundStyle(.white)
                        Text(report).font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.78))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(15).background(.white.opacity(0.055))
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                    
                    Text("معلومة: إذا تطابقت بصمة SHA-256 لملفين، فهذا مؤشر قوي أن محتواهما متطابق. البصمة لا تصلح الملف التالف، لكنها تساعدك تكتشف اختلاف النسخ.")
                        .font(.caption).foregroundStyle(.white.opacity(0.5))
                }.padding(16)
            }
        }
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): calculateHashes(urls)
            case .failure(let error): report = "تعذر اختيار الملفات: \(error.localizedDescription)"
            }
        }
        .navigationTitle("File Hash")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
    }
    
    private func calculateHashes(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isBusy = true
        report = "تم اختيار \(urls.count) ملف. جاري الفحص..."
        DispatchQueue.global(qos: .userInitiated).async {
            var lines: [String] = []
            for url in urls {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    var hasher = SHA256()
                    var byteCount: Int64 = 0
                    while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                        hasher.update(data: chunk)
                        byteCount += Int64(chunk.count)
                    }
                    let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
                    let sizeMB = Double(byteCount) / 1_048_576.0
                    lines.append("الملف: \(url.lastPathComponent)\nالحجم: \(String(format: "%.2f", sizeMB)) MB\nSHA-256: \(digest)")
                } catch {
                    lines.append("الملف: \(url.lastPathComponent)\nفشل الفحص: \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                report = lines.joined(separator: "\n\n--------------------\n\n")
                isBusy = false
            }
        }
    }
}


struct OrbxDLCValidatorView: View {
    @State private var input = ""
    @State private var copied = false

    private var candidates: [String] {
        input.split(whereSeparator: { $0.isNewline || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var validNames: [String] {
        candidates.filter {
            $0.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil
        }
    }

    private var uniqueNames: [String] {
        var seen = Set<String>()
        return validNames.filter { seen.insert($0.lowercased()).inserted }
    }

    private var duplicateNames: [String] {
        var seen = Set<String>()
        var duplicates = Set<String>()
        for name in validNames {
            if !seen.insert(name.lowercased()).inserted { duplicates.insert(name) }
        }
        return duplicates.sorted()
    }

    private var invalidCount: Int { candidates.count - validNames.count }

    private var xmlOutput: String {
        let entries = uniqueNames.map {
            "        <Item>/data/orbx/gta/rpf/dlc_addon/" + $0 + "/</Item>"
        }.joined(separator: "\n")
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<SMandatoryPacksData>\n    <Paths>\n" + entries + "\n    </Paths>\n</SMandatoryPacksData>"
    }

    var body: some View {
        ZStack {
            extraBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 36)).foregroundStyle(.purple)
                        Text("مدقق حزم Orbx DLC").font(.title2.bold()).foregroundStyle(.white)
                        Text("اكتب اسم كل مجلد DLC في سطر مستقل، وسيتم فحصه وإنشاء مسارات PS4 المطلقة.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                    }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 18))

                    TextEditor(text: $input)
                        .frame(minHeight: 160)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(.black.opacity(0.28))
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                        .foregroundStyle(.white)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    HStack(spacing: 8) {
                        validatorStat("الإجمالي", value: "\(candidates.count)", color: .white)
                        validatorStat("صالح", value: "\(uniqueNames.count)", color: .green)
                        validatorStat("مكرر", value: "\(duplicateNames.count)", color: .orange)
                        validatorStat("غير صالح", value: "\(invalidCount)", color: .red)
                    }

                    if !duplicateNames.isEmpty || invalidCount > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ملاحظات الفحص").font(.subheadline.bold()).foregroundStyle(.white)
                            if !duplicateNames.isEmpty {
                                Text("أسماء مكررة: " + duplicateNames.joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            if invalidCount > 0 {
                                Text("تم استبعاد \(invalidCount) اسم. المسموح: أحرف إنجليزية وأرقام وشرطة وشرطة سفلية، حتى 64 خانة.")
                                    .font(.caption).foregroundStyle(.red.opacity(0.9))
                            }
                        }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.055)).clipShape(RoundedRectangle(cornerRadius: 13))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ناتج dlclist.xml").font(.headline).foregroundStyle(.white)
                        Text(xmlOutput).font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.78))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12).background(.black.opacity(0.25))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Button {
                            UIPasteboard.general.string = xmlOutput
                            copied = true
                        } label: {
                            Label(copied ? "تم النسخ" : "نسخ XML", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .font(.subheadline.bold()).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(14)
                                .background(Color.purple.opacity(0.8))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }.disabled(uniqueNames.isEmpty)
                    }.padding(15).background(.white.opacity(0.055))
                        .clipShape(RoundedRectangle(cornerRadius: 15))

                    Text("الصيغة المستخدمة: /data/orbx/gta/rpf/dlc_addon/NAME/ . لا يتم إدراج الأسماء المكررة أو غير الصالحة.")
                        .font(.caption).foregroundStyle(.white.opacity(0.5))
                }.padding(16)
            }
        }
        .navigationTitle("Orbx DLC Validator")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func validatorStat(_ title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline.bold()).foregroundStyle(color)
            Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.55))
        }.frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 11))
    }
}
