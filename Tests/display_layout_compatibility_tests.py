from pathlib import Path

app = Path("GTAConverterApp.swift").read_text()
phone = Path("INRPFPhoneRootView.swift").read_text()
survey = Path("INRPFDisplaySurveyView.swift").read_text()
github = Path("GitHubIntegrationView.swift").read_text()
ftp = Path("FTPBrowserView.swift").read_text()
agent = Path("AutonomousAgentView.swift").read_text()
project = Path("project.yml").read_text()

assert 'iOS: "17.0"' in project, "Minimum deployment target must continue to cover iOS 18+."
assert 'TARGETED_DEVICE_FAMILY: "1"' in project, "The app must be iPhone-only."
assert 'MARKETING_VERSION: "6.12"' in project and 'CURRENT_PROJECT_VERSION: "82"' in project
assert "INRPFPhoneRootView.swift" in project, "The iPhone shell must be compiled into the app target."
assert "WindowGroup" in app and "INRPFPhoneRootView()" in app, "The app must launch directly into the iPhone interface."
assert "GeometryReader { viewport in" in app, "Root layout must measure the actual app scene viewport."
assert "width: max(1, viewport.size.width)" in app and "height: max(1, viewport.size.height)" in app, "Root must size the iPhone shell to the measured scene dimensions."
assert ".clipped()" in app, "Root must not render beyond the measured viewport."
assert "appTabs" not in app and "iPadOS" not in app and "ipados" not in app.lower(), "The old universal/iPad shell must not remain in the app entry point."
assert "TabView(selection: $selectedTab)" in phone, "The iPhone shell must retain its dedicated navigation."
assert "GitHubIntegrationView()" in phone and "ContentView()" in phone
assert "GeminiToolView()" in phone and "AutonomousAgentView()" in phone
assert "safeAreaInset(edge: .bottom" in phone, "Phone shell must use mobile bottom navigation."
assert "NavigationStack" in phone, "Phone destinations must retain navigation support."
assert "UIScreen.main" not in survey, "Survey must not use device-wide screen bounds."
assert "UIDevice.current.orientation" not in survey, "Layout orientation must come from viewport geometry."
assert "GeometryReader" in survey and "proxy.size" in survey
assert '@Environment(\\.displayScale)' in survey
assert '"measurement_scope": "scene_viewport"' in survey
assert 'orientation(for: viewportSize)' in survey
for name, source in (("GitHub", github), ("FTP", ftp), ("AI Agent", agent)):
    assert '@AppStorage("inrpf_interface_mode")' not in source, f"{name} must not retain the removed iPad display selector."
    assert '.frame(maxWidth: 560)' in source, f"{name} must use the compact iPhone content width."
    assert "ipados" not in source.lower(), f"{name} must not contain iPad-specific layout mode."
assert 'TARGETED_DEVICE_FAMILY: "1,2"' not in project
assert "UIRequiresFullScreen" not in project
print("PASS: iPhone-only target, measured scene-sized phone root, shared feature screens, and version 6.12 (82).")
