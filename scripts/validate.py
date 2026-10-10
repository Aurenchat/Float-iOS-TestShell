#!/usr/bin/env python3
"""Preflight validation without macOS/Xcode; NOT a substitute for device build."""
from pathlib import Path
import json
import re
import sys

root = Path(__file__).resolve().parents[1]
app = (root / 'Sources/BrowserViewController.swift').read_text(encoding='utf-8')
diag = (root / 'Sources/NativeDiagnostics.swift').read_text(encoding='utf-8')
workflow = (root / '.github/workflows/build-ios-ipa.yml').read_text(encoding='utf-8')
spec = (root / 'project.yml').read_text(encoding='utf-8')
asset = json.loads((root / 'Resources/Assets.xcassets/AppIcon.appiconset/Contents.json').read_text(encoding='utf-8'))
checks = {
  'remote netlify HTTPS entrypoint': 'https://aivirtualphone1130.netlify.app/' in app,
  'persistent WKWebView data store': 'configuration.websiteDataStore = WKWebsiteDataStore.default()' in app and 'configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()' not in app,
  'process termination delegate': 'func webViewWebContentProcessDidTerminate(' in app,
  'no automatic reload in termination callback': 'showRecovery(' in app.split('func webViewWebContentProcessDidTerminate(',1)[1].split('// MARK:',1)[0] and '.reload()' not in app.split('func webViewWebContentProcessDidTerminate(',1)[1].split('// MARK:',1)[0],
  'native download support': 'WKDownloadDelegate' in app and 'func downloadDidFinish(' in app,
  'native diagnostic redaction (source check)': 'Never records URL query strings' in diag and 'cookies' in diag,
  'no PWA data migration': 'WKWebsiteDataStore.default()' in app and 'migrat' not in app.lower(),
  'IPA is unsigned': 'CODE_SIGNING_ALLOWED=NO' in workflow,
  'IPA only built on manual action': 'workflow_dispatch:' in workflow and 'push:' not in workflow,
  'App iOS 16+': "iOS: '16.0'" in spec,
  'icon PNG asset': any((root / 'Resources/Assets.xcassets/AppIcon.appiconset' / x['filename']).exists() for x in asset['images']),
  'privacy: no full URL logging': 'detail: webView.url?.host' in app,
}
for name, ok in checks.items():
    print(('PASS' if ok else 'FAIL') + ' ' + name)
if not all(checks.values()): sys.exit(1)
try:
    import yaml
    with (root / 'project.yml').open(encoding='utf-8') as f: ps = yaml.safe_load(f)
    with (root / '.github/workflows/build-ios-ipa.yml').open(encoding='utf-8') as f: ws = yaml.safe_load(f)
    assert ps['targets']['FloatTestShell']['platform'] == 'iOS'
    assert 'unsigned-ipa' in ws['jobs']
    print('PASS project & workflow YAML parsed')
except ImportError:
    print('NOTE PyYAML unavailable, skipped YAML parse')
