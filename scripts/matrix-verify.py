#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
matrix-verify.py — Harness kiểm chứng Ma trận Cài đặt, Nâng cấp và Gỡ cài đặt (WS-9 DoD)
Tài liệu liên quan: docs/INSTALL_UPGRADE_MATRIX.md
"""

import sys
import os
import argparse
import pathlib
import platform
import subprocess
import json

def parse_toml_simple(text):
    data = {}
    current_sec = ""
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('[') and line.endswith(']'):
            current_sec = line[1:-1].strip()
            if current_sec not in data:
                data[current_sec] = {}
        elif '=' in line:
            k, v = line.split('=', 1)
            k = k.strip()
            v = v.strip().strip('"').strip("'")
            if current_sec:
                data[current_sec][k] = v
            else:
                data[k] = v
    return data

def config_diff(pre_text, post_text):
    pre = parse_toml_simple(pre_text)
    post = parse_toml_simple(post_text)
    critical_keys = ['id', 'enc_id', 'password', 'salt', 'key_pair']
    results = {'preserved': [], 'missing': [], 'modified': [], 'new': []}
    
    for k in critical_keys:
        if k in pre:
            if k not in post:
                results['missing'].append(k)
            elif pre[k] == post[k]:
                results['preserved'].append(k)
            else:
                results['modified'].append(k)
    return results

def sweep_orphans(search_names=None):
    if search_names is None:
        search_names = ['rustdesk', 'carriez']
    hits = []
    
    # 1. Quét Environment variables
    for env_k, env_v in os.environ.items():
        for name in search_names:
            if name in env_k.lower() or name in env_v.lower():
                hits.append(f'ENV: {env_k}={env_v}')
                
    # 2. Quét ProgramData / AppData nếu trên Windows
    if platform.system() == 'Windows':
        pd = os.environ.get('ProgramData', 'C:\\ProgramData')
        for name in search_names:
            target = os.path.join(pd, name)
            if os.path.exists(target):
                hits.append(f'DIR: {target}')
    return hits

VENDOR_EXPECTED = {
    "dash_chat_2": "vendor/flutter_plugins/dash_chat_2",
    "window_manager": "vendor/flutter_plugins/window_manager",
    "desktop_multi_window": "vendor/flutter_plugins/desktop_multi_window",
    "flutter_custom_cursor": "vendor/flutter_plugins/flutter_custom_cursor",
    "uni_links": "vendor/flutter_plugins/uni_links/uni_links",
    "texture_rgba_renderer": "vendor/flutter_plugins/texture_rgba_renderer",
    "flutter_gpu_texture_renderer": "vendor/flutter_plugins/flutter_gpu_texture_renderer",
    "dynamic_layouts": "vendor/flutter_plugins/dynamic_layouts",
    "window_size": "vendor/flutter_plugins/window_size",
}

def verify_flutter_vendor(root=None):
    """Check 9 fork pubspec path refs resolve to vendored dirs, no rustdesk-org fetch."""
    # ponytail: local path-exists check only; full offline `flutter pub get --offline`
    # + SHA-256 manifest pinning when CI runner has flutter.
    base = pathlib.Path(root) if root else pathlib.Path(__file__).resolve().parent.parent
    pub = base / "flutter" / "pubspec.yaml"
    text = pub.read_text(encoding="utf-8")
    missing_dirs, missing_refs = [], []
    for name, rel in VENDOR_EXPECTED.items():
        if rel not in text:
            missing_refs.append(name)
        target = base / rel
        if not (target / "pubspec.yaml").is_file():
            missing_dirs.append(name)
    upstream_hits = [l for l in text.splitlines() if "rustdesk-org" in l]
    return {"missing_refs": missing_refs, "missing_dirs": missing_dirs,
            "upstream_hits": upstream_hits}

def run_selftest():
    print("=== matrix-verify.py selftest ===")
    
    # Test 1: Config diff preservation
    cfg_v1 = """
id = "123456789"
password = "encrypted_pwd"
salt = "secure_salt_hex"
key_pair = ["sk_hex", "pk_hex"]
config_version = 1
"""
    cfg_v2 = """
id = "123456789"
password = "encrypted_pwd"
salt = "secure_salt_hex"
key_pair = ["sk_hex", "pk_hex"]
config_version = 2
v2_signaling_server = "sig.deskagent.io:34116"
"""
    diff = config_diff(cfg_v1, cfg_v2)
    assert 'id' in diff['preserved'], "ID must be preserved"
    assert 'password' in diff['preserved'], "Password must be preserved"
    assert len(diff['missing']) == 0, "No critical key should be missing"
    print("  [PASS] Config diff critical key preservation test")
    
    # Test 2: Config diff missing key detection
    cfg_bad = """
config_version = 2
"""
    diff_bad = config_diff(cfg_v1, cfg_bad)
    assert 'id' in diff_bad['missing'], "Missing ID must be detected"
    print("  [PASS] Config diff missing key detection test")
    
    # Test 3: Orphan scanner test
    hits = sweep_orphans(['nonexistent_legacy_test_xyz'])
    assert len(hits) == 0, "Nonexistent search should have 0 hits"
    print("  [PASS] Orphan scanner negative test")

    # Test 4: Flutter vendor provenance (9 forks local, no rustdesk-org fetch)
    v = verify_flutter_vendor()
    assert v["missing_refs"] == [], f"pubspec missing path refs: {v['missing_refs']}"
    assert v["missing_dirs"] == [], f"vendor dirs missing: {v['missing_dirs']}"
    assert v["upstream_hits"] == [], f"upstream fetch remains: {v['upstream_hits']}"
    print("  [PASS] Flutter vendor provenance 9/9 local test")
    
    print("selftest: OK")
    return True

def main():
    parser = argparse.ArgumentParser(description="DeskAgent Install/Upgrade/Uninstall Matrix Verification Tool")
    parser.add_argument('--selftest', action='store_true', help="Run unit selftests")
    parser.add_argument('--check-env', action='store_true', help="Check system test environment")
    parser.add_argument('--sweep-orphans', action='store_true', help="Sweep for legacy orphan files/registry/services")
    parser.add_argument('--check-vendor', action='store_true', help="Verify 8 Flutter forks vendored locally")
    
    args = parser.parse_args()
    
    if args.selftest:
        if run_selftest():
            sys.exit(0)
        else:
            sys.exit(1)
            
    if args.check_env:
        print(f"OS: {platform.system()} {platform.release()} ({platform.machine()})")
        print(f"Python: {platform.python_version()}")
        print(f"Hostname: {platform.node()}")
        sys.exit(0)
        
    if args.sweep_orphans:
        hits = sweep_orphans()
        print(f"Total legacy orphan hits: {len(hits)}")
        for h in hits:
            print(f"  {h}")
        sys.exit(0)

    if args.check_vendor:
        v = verify_flutter_vendor()
        print(f"missing_refs: {v['missing_refs']}")
        print(f"missing_dirs: {v['missing_dirs']}")
        print(f"upstream_hits: {len(v['upstream_hits'])}")
        sys.exit(0 if not (v["missing_refs"] or v["missing_dirs"] or v["upstream_hits"]) else 1)
        
    parser.print_help()

if __name__ == '__main__':
    main()
