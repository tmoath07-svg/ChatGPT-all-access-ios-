from pathlib import Path

app = Path("GTAConverter/GTAConverterApp.swift").read_text()
survey = Path("GTAConverter/INRPFDisplaySurveyView.swift").read_text()
github = Path("GTAConverter/GitHubIntegrationView.swift").read_text()
ftp = Path("GTAConverter/FTPBrowserView.swift").read_text()
agent = Path("GTAConverter/AutonomousAgentView.swift").read_text()
project = Path("project.yml").read_text()

assert 'iOS: "17.0"' in project, "Minimum deployment target must continue to cover iOS 18+."
assert 'TARGETED_DEVICE_FAMILY: "1,2"' in project, "Both iPhone and iPad must remain targeted."
assert "GeometryReader" in app, "Root layout must read the actual scene viewport."
assert 'interfaceMode == "ios" ? min(560, availableWidth) : availableWidth' in app
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
print("Display compatibility static checks passed (iOS 18-27; iPhone/iPad).")
