import SwiftUI
import CryptoKit
import UIKit
import PhotosUI

private let extraBackground = Color(red: 0.035, green: 0.025, blue: 0.065)

struct AppearanceSettingsView: View {
    @AppStorage("gta_cover_style") private var coverStyle = "neon"
    @AppStorage("gta_accent_color") private var accentColor = "purple"
    @AppStorage("gta_home_density") private var homeDensity = "comfortable"
    @AppStorage("gta_motion_enabled") private var motionEnabled = true

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

                    settingsGroup("الشاشة الرئيسية", icon: "rectangle.3.group.fill") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("كثافة ترتيب العناصر").font(.subheadline.bold()).foregroundStyle(.white)
                            Picker("كثافة ترتيب العناصر", selection: $homeDensity) {
                                Text("مريحة").tag("comfortable")
                                Text("مضغوطة").tag("compact")
                            }
                            .pickerStyle(.segmented)
                            .tint(selectedColor)
                        }
                        Toggle(isOn: $motionEnabled) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("موشن وانتقالات قوية").foregroundStyle(.white)
                                Text("حركة Spring ناعمة عند تحديث الشاشة والتنقل").font(.caption2).foregroundStyle(.white.opacity(0.55))
                            }
                        }
                        .tint(selectedColor)
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
            .background(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.14)))
            .clipShape(RoundedRectangle(cornerRadius: 18))
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

    private let categories = ["الكل", "FiveM", "الملفات", "السيارات", "PS4", "PlayStation", "الذكاء الاصطناعي", "الإدارة"]
    private let items: [FeatureCatalogItem] = [
        .init(id:1,title:"محلل المودات الذكي",category:"الملفات",icon:"doc.text.magnifyingglass",status:"متاح",detail:"تحليل الأرشيفات والملفات واكتشاف مكونات المود. افتح شاشة الاستيراد والتحليل من الصفحة الرئيسية.",live:true),
        .init(id:2,title:"مختبر YTD",category:"الملفات",icon:"photo.stack.fill",status:"فحص متاح",detail:"اختيار ملفات YTD وفحص الحجم وترويسة RSC7. استخراج DDS وإعادة بناء YTD والتحويل الفعلي تحتاج محرك معالجة مختبراً.",route:"ytd"),
        .init(id:3,title:"عارض YDR وYFT",category:"السيارات",icon:"cube.transparent",status:"قيد التطوير",detail:"معاينة المجسمات والخامات تتطلب قارئ صيغ RAGE وتحويلها إلى نموذج قابل للعرض."),
        .init(id:4,title:"محرر Hex",category:"الملفات",icon:"chevron.left.forwardslash.chevron.right",status:"متاح",detail:"عرض وتعديل بايتات الملف بصيغة Hex مع حفظ نسخة جديدة دون المساس بالأصل."),
        .init(id:5,title:"كاشف أخطاء المودات",category:"الملفات",icon:"stethoscope",status:"جزئي",detail:"التحليل الحالي يكشف بعض الملفات والمكونات. فحص الاعتماديات والتوافق الشامل يحتاج قواعد إضافية."),
        .init(id:6,title:"منشئ DLC سيارات",category:"السيارات",icon:"car.side.fill",status:"تجهيز متاح",detail:"تجهيز هيكل DLC ومسارات Orbx وملف dlclist. تحويل محتوى PC نفسه يحتاج محرك التحويل السحابي.",route:"dlc"),
        .init(id:7,title:"فاحص ملفات السيارة",category:"السيارات",icon:"car.rear.fill",status:"جزئي",detail:"فحص وجود الملفات المعروفة ممكن ضمن التحليل. التحقق من صحة كل بنية YFT/YTD يحتاج محللات متخصصة."),
        .init(id:8,title:"استوديو ألوان السيارات",category:"السيارات",icon:"paintpalette.fill",status:"مخطط",detail:"معاينة وتعديل ألوان الخامات تتطلب فك YTD ومحرر خامات."),
        .init(id:9,title:"محلل Handling",category:"السيارات",icon:"gauge.with.dots.needle.67percent",status:"متاح",detail:"قراءة قيم handling.meta من النص وخصائص value في XML، مع دعم تكرار الحقول لعدة مركبات. العرض للقراءة فقط.",route:"handling"),
        .init(id:10,title:"معرض موداتك",category:"السيارات",icon:"rectangle.stack.fill",status:"متاح",route:"library",detail:"استعراض وتحليل ومشاركة المودات التي استوردتها داخل مساحة INRPF المحلية."),
        .init(id:11,title:"AI Mod Scanner",category:"الذكاء الاصطناعي",icon:"sparkles",status:"محلي",detail:"افحص تقرير المود محلياً واكتشف الملفات الناقصة والتعارضات المحتملة، مع توضيح الأدلة."",route:"ai"),
        .init(id:12,title:"AI Error Fixer",category:"الذكاء الاصطناعي",icon:"wrench.and.screwdriver.fill",status:"محلي",detail:"حلّل سجل الخطأ واقترح خطوات إصلاح قابلة للمراجعة. لا تعدّل الملفات تلقائياً."",route:"ai"),
        .init(id:13,title:"AI XML Builder",category:"الذكاء الاصطناعي",icon:"curlybraces",status:"محلي",detail:"أنشئ مسودة XML بناءً على الطلب والبيانات، ثم تحقق من صلاحية XML قبل استخدامه."",route:"ai"),
        .init(id:14,title:"AI DLC Assistant",category:"الذكاء الاصطناعي",icon:"shippingbox.fill",status:"محلي",detail:"اشرح بنية DLC والمسارات والملفات المطلوبة اعتماداً على تقرير المود."",route:"ai"),
        .init(id:15,title:"AI Vehicle Finder",category:"الذكاء الاصطناعي",icon:"car.side",status:"محلي",detail:"استنتج اسم السيارة المحتمل من أسماء الملفات وبيانات META، واذكر مستوى الثقة."",route:"ai"),
        .init(id:16,title:"AI Texture Inspector",category:"الذكاء الاصطناعي",icon:"eye.fill",status:"محلي",detail:"فسّر تقرير الخامات والامتدادات والأحجام، ولا تخمّن خصائص غير موجودة."",route:"ai"),
        .init(id:17,title:"AI Mod Translator",category:"الذكاء الاصطناعي",icon:"character.bubble",status:"محلي",detail:"ترجم نصوص README والأوصاف مع إبقاء أسماء الملفات والمسارات كما هي."",route:"ai"),
        .init(id:18,title:"AI Compatibility",category:"الذكاء الاصطناعي",icon:"checkmark.shield.fill",status:"محلي",detail:"قيّم مؤشرات التوافق مع PS4 اعتماداً على الأدلة، ولا تدّعِ ضمان التشغيل."",route:"ai"),
        .init(id:19,title:"PS4 Package Studio",category:"PS4",icon:"shippingbox",status:"جزئي",route:"dlc",detail:"تجهيز ونقل حزم Orbx ودمج dlclist.xml. لا ينشئ هذا وحده محتوى DLC متوافقاً مع PS4."),
        .init(id:20,title:"XML Studio",category:"PS4",icon:"list.bullet.rectangle",status:"جزئي",detail:"محرر XML محلي مع فحص الصياغة وحفظ نسخة جديدة من dlclist.xml.",route:"xml"),
        .init(id:21,title:"Cloud Converter",category:"PS4",icon:"cloud.gear.fill",status:"متاح يدوياً",detail:"محرك Ps4tools موجود في GitHub Actions. تشغيله حالياً يتم من GitHub يدوياً برابط تنزيل مباشر.",route:"cloud"),
        .init(id:22,title:"مقارنة إصدارات المود",category:"الملفات",icon:"arrow.left.arrow.right",status:"متاح",detail:"مقارنة مجلدين محلياً ببصمات SHA-256 وكشف الملفات الجديدة والمحذوفة والمتغيرة والمتطابقة.",route:"compare"),
        .init(id:23,title:"مدير DLC",category:"PS4",icon:"folder.badge.gearshape",status:"تجهيز متاح",detail:"إدارة مخرجات DLC ومسارات Orbx وملف dlclist.",route:"dlc"),
        .init(id:24,title:"Mod Marketplace",category:"الإدارة",icon:"storefront",status:"مخطط",detail:"كتالوج مودات وروابطها ومعلومات التوافق. لن يستضيف ملفات محمية أو يعيد توزيعها دون إذن."),
        .init(id:25,title:"Mod Library المحلية",category:"الإدارة",icon:"cloud.fill",status:"متاح",route:"library",detail:"مكتبة ملفات محلية تعمل دون سيرفر أو مزامنة سحابية، مع استعراض وتحليل ومشاركة العناصر المستوردة."),
        .init(id:26,title:"One Click Build",category:"PS4",icon:"bolt.fill",status:"مخطط",detail:"تشغيل سلسلة فحوص وتجهيز وتحويل وتغليف بعد ربط كل مراحل المحرك."),
        .init(id:27,title:"Mod Timeline",category:"الإدارة",icon:"timeline.selection",status:"متاح",route:"timeline",detail:"سجل محلي لعمليات التحليل والتجهيز والنسخ والذكاء الاصطناعي على هذا الجهاز."),
        .init(id:28,title:"Batch Converter",category:"PS4",icon:"square.stack.3d.up.fill",status:"جزئي",route:"rpf",detail:"تحويل مجلد موارد Y* المدعومة دفعة واحدة عبر المحرك المحلي. لا يعني ذلك إنشاء DLC PS4 كامل."),
        .init(id:29,title:"Mod Preview",category:"الملفات",icon:"play.rectangle",status:"جزئي",detail:"معاينة الصور والملفات المدعومة. معاينة المجسمات تتطلب عارضاً ثلاثي الأبعاد."),
        .init(id:30,title:"Auto DLC Naming",category:"PS4",icon:"tag.fill",status:"متاح",route:"utility",detail:"توليد اسم مجلد DLC آمن وفريد بصيغة ASCII مع فحص التعارض."),
        .init(id:31,title:"Smart Folder",category:"الملفات",icon:"folder.badge.plus",status:"متاح",route:"utility",detail:"نسخ ملفات المود إلى مجلدات مصنفة حسب الامتداد مع الحفاظ على بنية المسارات والمصدر دون تغيير."),
        .init(id:32,title:"Build History",category:"الإدارة",icon:"clock.arrow.circlepath",status:"جزئي",detail:"سجل عمليات GitHub Actions متاح من صفحة التشغيل. سجل داخل التطبيق يحتاج ربط API.",route:"cloud"),
        .init(id:33,title:"Mod Report PDF",category:"الإدارة",icon:"doc.richtext",status:"متاح",route:"utility",detail:"إنشاء تقرير PDF محلي من تحليل المود ومشاركته من الجهاز."),
        .init(id:34,title:"PS4 Compatibility Score",category:"PS4",icon:"chart.bar.xaxis",status:"متاح",route:"utility",detail:"حساب مؤشر جاهزية بنيوي من الملفات المكتشفة، وليس ضمان توافق أو تشغيل على PS4."),
        .init(id:35,title:"Mod Backup",category:"الإدارة",icon:"externaldrive.fill",status:"متاح",route:"utility",detail:"إنشاء نسخة احتياطية مؤرخة من مجلد المود دون تعديل المصدر."),
        .init(id:36,title:"Project Templates",category:"الإدارة",icon:"square.grid.2x2.fill",status:"متاح",route:"utility",detail:"إنشاء قوالب مشاريع FiveM وOrbx ومساحة عمل عامة محلياً."),
        .init(id:37,title:"Dependency Checker",category:"الملفات",icon:"point.3.connected.trianglepath.dotted",status:"متاح",route:"utility",detail:"قراءة اعتماديات FiveM وملفات manifest والتحقق من مراجع الملفات المحلية."),
        .init(id:38,title:"RPF Explorer",category:"الملفات",icon:"archivebox.fill",status:"متاح",route:"rpf",detail:"فحص أرشيفات RPF7 واستخراج الأرشيفات غير المشفرة عبر المحرك المحلي."),
        .init(id:39,title:"Texture Converter",category:"الملفات",icon:"photo.artframe",status:"جزئي",route:"ytd",detail:"استخراج خامات YTD المدعومة إلى DDS وبناء بعض القواميس. التحويل الكامل بين كل الصيغ غير متاح."),
        .init(id:40,title:"Mod Installer Guide",category:"PS4",icon:"book.closed.fill",status:"متاح",route:"utility",detail:"دليل خطوات Orbx وPS4 مع تنبيهات المسارات والنسخ الاحتياطي والتحقق."),
        .init(id:41,title:"Chiaki Remote Play",category:"PlayStation",icon:"gamecontroller.fill",status:"دليل وتجهيز",detail:"مركز Chiaki لمشروع Remote Play ومعلومات دعم iOS وروابط المشروع الرسمية.",route:"chiaki"),
        .init(id:42,title:"File Hash Inspector",category:"الملفات",icon:"number.square",status:"متاح",detail:"حساب بصمة SHA-256 للملفات محلياً على الآيباد للتحقق من تطابق النسخ وسلامة النقل.",route:"hash"),
        .init(id:43,title:"Orbx DLC Validator",category:"PS4",icon:"checkmark.seal.fill",status:"متاح",detail:"فحص أسماء حزم DLC وكشف التكرار والأسماء غير الصالحة وإنشاء مسارات Orbx بصيغة PS4 المطلقة.",route:"dlcvalidator"),
        .init(id:44,title:"FiveM Resource Studio",category:"FiveM",icon:"car.side.3.fill",status:"تحليل محلي",detail:"استيراد مجلد مورد FiveM، فحص fxmanifest وstream وdata وملفات YFT/YTD/META، ثم فتح مسار التحويل السحابي للموارد المدعومة.",route:"fivem")
    ]

    private var filteredItems: [FeatureCatalogItem] {
        items.filter { item in
            (selectedCategory == "الكل" || item.category == selectedCategory) &&
            (searchText.isEmpty || item.title.localizedCaseInsensitiveContains(searchText) || item.detail.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var readyCount: Int {
        items.filter { $0.status == "متاح" || $0.status == "تجهيز متاح" }.count
    }

    private var partialCount: Int {
        let states = ["فحص متاح", "متاح يدوياً", "جزئي", "دليل وتجهيز", "تحليل محلي", "قيد التطوير"]
        return items.filter { states.contains($0.status) }.count
    }

    private var plannedCount: Int {
        items.count - readyCount - partialCount
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
                            Text("40 ميزة + FiveM").font(.caption.bold()).foregroundStyle(.purple)
                        }
                        Text("40 ميزة أساسية مع استوديو FiveM. الحالة توضّح ما يعمل فعلياً وما لا يزال مخططاً.")
                            .font(.caption).foregroundStyle(.white.opacity(0.62))
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 18))

                    HStack(spacing: 8) {
                        catalogStat("جاهز", value: String(readyCount), color: .green)
                        catalogStat("جزئي / تجريبي", value: String(partialCount), color: .orange)
                        catalogStat("مخطط", value: String(plannedCount), color: .gray)
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
        case "handling": HandlingAnalyzerView()
        case "compare": ModComparisonView()
        case "ai": LocalAIAssistantView(featureID: item.id)
        case "utility": LocalUtilityFeatureView(featureID: item.id)
        case "library": LocalModLibraryView(featureID: item.id)
        case "timeline": LocalTimelineView()
        case "xml": DLClistEditorView()
        case "rpf": LocalEngineView()
        case "cloud": CloudConversionView()
        case "chiaki": ChiakiRemotePlayView()
        case "hash": FileHashInspectorView()
        case "dlcvalidator": OrbxDLCValidatorView()
        case "fivem": FiveMStudioView()
        case "dlc": OrbxPS4TransferView()
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
        if status == "متاح" || status == "تجهيز متاح" || status == "محلي" { return .green }
        if status == "فحص متاح" || status == "متاح يدوياً" || status == "جزئي" || status == "تحليل محلي" || status == "دليل وتجهيز" { return .orange }
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
    private let releaseURL = URL(string: "https://github.com/tmoath07-svg/Ps4tools/releases/tag/25")!

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

                    VStack(alignment: .leading, spacing: 10) {
                        Label("ملف التجربة جاهز في Ps4tools", systemImage: "shippingbox.fill")
                            .font(.headline.bold()).foregroundStyle(.white)
                        Text("جهزت إعداد التشغيل على Release Tag رقم 25، وفيه الملف rb3nasb.2.rar. عند فتح Run workflow اترك Release Tag على 25، واختر تحويل مود FiveM متعدد السيارات إلى DLC للسوني.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.72))
                        Link(destination: releaseURL) {
                            Label("فتح Release 25 والملف rb3nasb.2.rar", systemImage: "arrow.down.circle.fill")
                                .font(.subheadline.bold()).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(14)
                                .background(Color.orange.opacity(0.78))
                                .clipShape(RoundedRectangle(cornerRadius: 13))
                        }
                    }
                    .padding(16).background(.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

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
                        Text("اضغط Run workflow. الإعدادات الافتراضية الآن تستخدم Release Tag = 25 وتختار تحويل FiveM إلى DLC. لا تضع رابطاً في URL إذا كنت تستخدم ملف الريليس. بعد نجاح التشغيل نزّل Artifact وافحص التقرير قبل تثبيته.")
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
    @AppStorage("gta_language") private var appLanguage = "ar"
    @State private var showAssistantProfile = false
    @State private var assistantPhotoItem: PhotosPickerItem?
    @State private var assistantPhoto: UIImage?
    @AppStorage("gta_assistant_avatar_path") private var assistantAvatarPath = ""

    private let creatorHandle = "Moa_sa7"
    private let assistantName = "q.wq9"
    private let assistantURL = URL(string: "https://www.tiktok.com/@q.wq9")!
    private let creatorURL = URL(string: "https://www.tiktok.com/@Moa_sa7")!

    var body: some View {
        ZStack {
            GTAAppBackground()
            ScrollView {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 13) {
                        Text(appLanguage == "ar" ? "فريق التطوير" : "Development team")
                            .font(.title2.bold()).foregroundStyle(.white)
                        HStack(alignment: .top, spacing: 12) {
                            Link(destination: creatorURL) {
                                creatorCard(handle: creatorHandle, role: appLanguage == "ar" ? "المطوّر وصاحب المشروع" : "Founder & Developer", icon: "crown.fill", primary: true)
                            }
                            .buttonStyle(.plain)

                            Button { showAssistantProfile = true } label: {
                                creatorCard(handle: assistantName, role: appLanguage == "ar" ? "مساعد المشروع" : "Project Assistant", icon: "person.fill", primary: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16).background(.white.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                    Link(destination: creatorURL) {
                        HStack(spacing: 12) {
                            Image(systemName: "music.note").font(.title2)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("TikTok").font(.headline.bold())
                                Text("@\\(creatorHandle)").font(.caption).opacity(0.75)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.headline)
                        }.foregroundStyle(.white).padding(16)
                            .background(Color.purple.opacity(0.28))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label(appLanguage == "ar" ? "حقوق التطبيق" : "App credits", systemImage: "c.circle.fill")
                            .font(.headline).foregroundStyle(.white)
                        Text("© 2026 \\(creatorHandle). " + (appLanguage == "ar" ? "جميع الحقوق محفوظة." : "All rights reserved."))
                            .font(.subheadline).foregroundStyle(.white.opacity(0.72))
                        Text(appLanguage == "ar" ? "GTA Converter مشروع مستقل. العلامات التجارية وأسماء الألعاب المذكورة تعود لأصحابها." : "GTA Converter is an independent project. Mentioned trademarks and game names belong to their respective owners.")
                            .font(.caption).foregroundStyle(.white.opacity(0.48))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16).background(.white.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 17))
                }.padding(16)
            }
        }
        .navigationTitle(appLanguage == "ar" ? "المبدعين" : "Creators")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, appLanguage == "ar" ? .rightToLeft : .leftToRight)
        .environment(\.locale, Locale(identifier: appLanguage))
        .sheet(isPresented: $showAssistantProfile) {
            NavigationStack {
                ZStack {
                    GTAAppBackground()
                    ScrollView {
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [.blue, Color(red: 0.08, green: 0.18, blue: 0.42)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 112, height: 112)
                                if let assistantPhoto {
                                    Image(uiImage: assistantPhoto)
                                        .resizable().scaledToFill()
                                        .frame(width: 112, height: 112)
                                        .clipShape(Circle())
                                } else {
                                    Text("q")
                                        .font(.system(size: 54, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(.top, 22)

                            Text(assistantName)
                                .font(.title2.bold()).foregroundStyle(.white)
                            Text(appLanguage == "ar" ? "مساعد المشروع" : "Project Assistant")
                                .font(.subheadline).foregroundStyle(.cyan)

                            VStack(spacing: 12) {
                                profileInfoRow(appLanguage == "ar" ? "الاسم الظاهر" : "Display name", value: assistantName)
                                Divider().overlay(.white.opacity(0.12))
                                profileInfoRow(appLanguage == "ar" ? "اسم المستخدم" : "Username", value: "@\\(assistantName)")
                                Divider().overlay(.white.opacity(0.12))
                                profileInfoRow(appLanguage == "ar" ? "المنصة" : "Platform", value: "TikTok")
                            }
                            .padding(16)
                            .background(.white.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 18))

                            PhotosPicker(selection: $assistantPhotoItem, matching: .images) {
                                Label(appLanguage == "ar" ? "اختيار صورة الحساب" : "Choose profile photo", systemImage: "photo")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).padding(13)
                                    .background(.white.opacity(0.09))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .onChange(of: assistantPhotoItem) { newItem in
                                guard let newItem else { return }
                                Task {
                                    if let data = try? await newItem.loadTransferable(type: Data.self),
                                       let image = UIImage(data: data) {
                                        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                                            .appendingPathComponent("GTA Converter", isDirectory: true)
                                        do {
                                            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
                                            let imageURL = support.appendingPathComponent("assistant-profile-avatar.jpg")
                                            try data.write(to: imageURL, options: .atomic)
                                            assistantAvatarPath = imageURL.path
                                            assistantPhoto = image
                                        } catch {
                                            assistantPhoto = image
                                        }
                                    }
                                }
                            }

                            Link(destination: assistantURL) {
                                Label(appLanguage == "ar" ? "فتح حساب TikTok" : "Open TikTok profile", systemImage: "arrow.up.right")
                                    .font(.headline).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).padding(15)
                                    .background(Color.cyan.opacity(0.22))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }

                            Text(appLanguage == "ar" ? "تقدر تختار صورة الحساب من ألبوم الصور." : "Choose the account photo from your photo library.")
                                .font(.caption).foregroundStyle(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                        }
                        .padding(20)
                    }
                }
                .navigationTitle(appLanguage == "ar" ? "ملف المساعد" : "Assistant profile")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    if !assistantAvatarPath.isEmpty {
                        assistantPhoto = UIImage(contentsOfFile: assistantAvatarPath)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(appLanguage == "ar" ? "إغلاق" : "Close") { showAssistantProfile = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func profileInfoRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.white.opacity(0.62))
            Spacer()
            Text(value).fontWeight(.semibold).foregroundStyle(.white)
        }
        .font(.subheadline)
    }

    private func creatorCard(handle: String, role: String, icon: String, primary: Bool) -> some View {
        VStack(spacing: 9) {
            ZStack {
                Circle().fill(LinearGradient(
                    colors: primary ? [.purple, Color(red: 0.22, green: 0.08, blue: 0.48)] : [.blue, Color(red: 0.08, green: 0.18, blue: 0.42)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )).frame(width: 58, height: 58)
                Image(systemName: icon).font(.system(size: 25, weight: .bold)).foregroundStyle(.white)
            }
            Text(handle).font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(primary ? .purple : .cyan).lineLimit(1).minimumScaleFactor(0.7)
            Text(role).font(.caption2.weight(.medium)).foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 132).padding(10)
        .background(.white.opacity(0.055)).clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(primary ? .purple.opacity(0.35) : .cyan.opacity(0.25)))
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
        report = "تم اختيار \(urls.count) ملف. يتم استيرادها بأمان ثم حساب البصمات..."
        let scopedURLs = urls.map { ($0, $0.startAccessingSecurityScopedResource()) }
        Task.detached(priority: .userInitiated) {
            defer {
                for (url, started) in scopedURLs where started { url.stopAccessingSecurityScopedResource() }
            }
            var lines: [String] = []
            for (url, _) in scopedURLs {
                do {
                    let localURL = try FileImportService.importItem(from: url, category: "Imports",
                                                                    securityScopeAlreadyStarted: true)
                    let handle = try FileHandle(forReadingFrom: localURL)
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
            await MainActor.run {
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
