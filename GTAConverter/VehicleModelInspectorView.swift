import SwiftUI
import SceneKit
import UniformTypeIdentifiers

private struct VehicleMeshPayload {
    let name: String
    let lod: String
    let model: Int
    let geometry: Int
    let vertices: [[Float]]
    let indices: [UInt32]
    let triangles: Int
}

struct VehicleModelInspectorView: View {
    @State private var showingPicker = false
    @State private var scene: SCNScene?
    @State private var report = "اختر ملف مركبة YFT أو YDR أو YDD لقراءة هندسته ومعاينتها محلياً."
    @State private var isBusy = false
    @State private var selectedName = ""

    var body: some View {
        ZStack {
            GTAAppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Vehicle 3D Inspector").font(.title2.bold()).foregroundStyle(.white)
                    Text("معاينة هندسية محلية. لا يتم رفع الملف إلى الإنترنت.")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                    Button { showingPicker = true } label: {
                        Label("اختيار ملف مركبة YFT / YDR / YDD", systemImage: "car.side")
                            .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(13)
                            .background(.purple).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                    }
                    if !selectedName.isEmpty {
                        Text(selectedName).font(.caption.monospaced()).foregroundStyle(.purple)
                    }
                    if let scene {
                        SceneView(
                            scene: scene,
                            options: [.allowsCameraControl, .autoenablesDefaultLighting]
                        )
                        .frame(height: 340)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12)))
                    }
                    if isBusy {
                        ProgressView("جاري تحليل هندسة المركبة...").tint(.purple).foregroundStyle(.white)
                    }
                    Text(report).font(.caption).foregroundStyle(.white.opacity(0.8))
                        .textSelection(.enabled)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 11))
                    Text("ملاحظة: هذه معاينة للـLOD العالي أو أول LOD. الخامات والعظام والتحريك غير معروضة، ودعم الملفات يعتمد على تخطيط RAGE الذي يستطيع المحرك قراءته.")
                        .font(.caption2).foregroundStyle(.orange)
                }.padding(16)
            }
        }
        .navigationTitle("Vehicle 3D Viewer")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            guard let url = try? result.get().first else { return }
            inspect(url)
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func inspect(_ url: URL) {
        selectedName = url.lastPathComponent
        scene = nil
        isBusy = true
        report = "يتم تحليل الملف..."
        let access = url.startAccessingSecurityScopedResource()
        Task.detached(priority: .userInitiated) {
            do {
                let result = try LocalEngineBridge.previewVehicleModel(at: url)
                let rawMeshes = result["meshes"] as? [[String: Any]] ?? []
                let payloads = rawMeshes.compactMap { item -> VehicleMeshPayload? in
                    guard let name = item["name"] as? String,
                          let lod = item["lod"] as? String,
                          let vertices = item["vertices"] as? [[NSNumber]],
                          let indices = item["indices"] as? [NSNumber] else { return nil }
                    let points = vertices.map { row -> [Float] in
                        guard row.count >= 3 else { return [0, 0, 0] }
                        return [row[0].floatValue, row[1].floatValue, row[2].floatValue]
                    }
                    return VehicleMeshPayload(
                        name: name,
                        lod: lod,
                        model: item["model"] as? Int ?? 0,
                        geometry: item["geometry"] as? Int ?? 0,
                        vertices: points,
                        indices: indices.map { $0.uint32Value },
                        triangles: item["triangle_count"] as? Int ?? 0
                    )
                }
                await MainActor.run {
                    scene = makeScene(from: payloads)
                    let totalVertices = payloads.reduce(0) { $0 + $1.vertices.count }
                    let totalTriangles = payloads.reduce(0) { $0 + $1.triangles }
                    report = """
                    الصيغة: \(result["format"] as? String ?? "RAGE")
                    أجزاء الهندسة: \(payloads.count)
                    الرؤوس: \(totalVertices)
                    المثلثات: \(totalTriangles)

                    \(payloads.map { "\($0.name) • \($0.lod) • Model \($0.model) / Geometry \($0.geometry) • \($0.triangles) triangles" }.joined(separator: "\n"))

                    \(result["warning"] as? String ?? "")
                    """
                    INRPFLocalTimeline.record("معاينة نموذج مركبة", details: url.lastPathComponent)
                    isBusy = false
                }
            } catch {
                await MainActor.run {
                    report = "تعذر عرض النموذج: \(error.localizedDescription)"
                    isBusy = false
                }
            }
            if access { url.stopAccessingSecurityScopedResource() }
        }
    }

    @MainActor private func makeScene(from meshes: [VehicleMeshPayload]) -> SCNScene {
        let scene = SCNScene()
        for mesh in meshes {
            guard !mesh.vertices.isEmpty, mesh.indices.count >= 3 else { continue }
            struct PackedVertex {
                var x: Float
                var y: Float
                var z: Float
            }
            let packed = mesh.vertices.map { PackedVertex(x: $0[0], y: $0[1], z: $0[2]) }
            let vertexData = packed.withUnsafeBufferPointer { Data(buffer: $0) }
            let source = SCNGeometrySource(
                data: vertexData,
                semantic: .vertex,
                vectorCount: packed.count,
                usesFloatComponents: true,
                componentsPerVector: 3,
                bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0,
                dataStride: MemoryLayout<PackedVertex>.stride
            )
            let indexData = mesh.indices.withUnsafeBufferPointer { Data(buffer: $0) }
            let element = SCNGeometryElement(
                data: indexData,
                primitiveType: .triangles,
                primitiveCount: mesh.indices.count / 3,
                bytesPerIndex: MemoryLayout<UInt32>.size
            )
            let geometry = SCNGeometry(sources: [source], elements: [element])
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(red: 0.55, green: 0.58, blue: 0.66, alpha: 1)
            material.isDoubleSided = true
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.name = mesh.name
            scene.rootNode.addChildNode(node)
        }
        let camera = SCNCamera()
        camera.zFar = 100_000
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 2, 8)
        scene.rootNode.addChildNode(cameraNode)
        return scene
    }
}
