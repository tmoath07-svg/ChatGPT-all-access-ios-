from pathlib import Path

app = Path("GTAConverterApp.swift").read_text()
phone = Path("INRPFPhoneRootView.swift").read_text()
survey = Path("INRPFDisplaySurveyView.swift").read_text()
github = Path("GitHubIntegrationView.swift").read_text()
ftp = Path("FTPBrowserView.swift").read_text()
agent = Path("AutonomousAgentView.swift").read_text()
project = Path("project.yml").read_text()

assert 'iOS: "17.0"' in project, "Minimum deployment target must continue to cover iOS 18+."
assert 'TARGETED_DEVICE_FAMILY: "1,2"' in project, "Both iPhone and iPad must remain targeted."
assert "INRPFPhoneRootView.swift" in project, "The new iPhone shell must be compiled into the app target."
assert "GeometryReader" in app and "scene.size.width < 600" in app, "Root must choose the compact shell from actual scene width."
assert "UIDevice.current.userInterfaceIdiom == .phone" in app, "iPhone must keep its dedicated shell in both orientations."
assert "INRPFPhoneRootView()" in app, "Compact scenes must use the dedicated iPhone shell."
assert "TabView(selection: $selectedTab)" in app, "The existing iPad tab interface must remain intact."
assert "GitHubIntegrationView()" in phone and "ContentView()" in phone
assert "GeminiToolView()" in phone and "AutonomousAgentView()" in phone
assert "safeAreaInset(edge: .bottom" in phone, "Phone shell must use its own mobile bottom navigation."
assert "NavigationStack" in phone, "Phone destinations must retain navigation support."
assert ".environment(\\.horizontalSizeClass" not in app, "Never override the system size class."
assert "UIScreen.main" not in survey, "Survey must not use device-wide screen bounds."
assert "UIDevice.current.orientation" not in survey, "Layout orientation must come from viewport geometry."
assert "GeometryReader" in survey and "proxy.size" in survey
assert '@Environment(\\.displayScale)' in survey
assert '"measurement_scope": "scene_viewport"' in survey
assert 'orientation(for: viewportSize)' in survey
for name, source in (("GitHub", github), ("FTP", ftp), ("AI Agent", agent)):
    assert '@AppStorage("inrpf_interface_mode")' in source, f"{name} must honor the selected layout mode."
    assert 'interfaceMode == "ios" ? 560 : interfaceMode == "ipados" ? 900 : 760' in source, f"{name} width must be adaptive."
assert "UIRequiresFullScreen" not in project, "Do not opt out of modern window resizing."
print("Display compatibility static checks passed: dedicated compact iPhone shell and preserved iPad shell.")
