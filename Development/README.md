# RTL88WiFi Development Workspace

Dedicated GitHub workspace for RTL88WiFi on macOS Sequoia 15.8.1 (24H32), x86_64.

- [Current development log](./output.log)
- [Fresh Stage26 source package](./RTL88WiFi-1.0.11-WCL-Sequoia-24H32-stage26-clean-source.zip)
- Stage20–Stage27 runner scripts
- Historical source snapshots, ABI audits, packet semantics and ownership reviews

## Repository rules

1. All future RTL88WiFi logs are uploaded to `Development/output.log`.
2. All future RTL88WiFi scripts, source ZIP/tar archives, audit files, build reports and generated artifacts are uploaded under `Development/`.
3. Runner URLs use the `/Development/` prefix, for example:
   `https://raw.githubusercontent.com/shammu2bd/BDIX-TV/main/Development/stage27-new-tree-compile-only.sh`.
4. Do not create new RTL88WiFi development files at the repository root.
5. Preserve the user's existing working older `rtl88wifi.kext`. Experimental WCL candidates must not replace it until build, dependency, signing, ABI, queue lifecycle, teardown and hardware checks are complete.

The unrelated `playlist.m3u` remains at the repository root.

## Stage27 source packaging note

The Stage26 copy originally excluded all `*.kext` paths, which also omitted the source template `driver/RTL88WiFi/RTL88WiFi.kext/Contents/Info.plist`. Stage27a restores that one build input to the fresh Stage26 project and recreates the ZIP while excluding only generated build folders. Builds remain in the Stage26 project; the earlier source folder is read-only for this metadata recovery.


## Native target status — 2026-11-02

- Stage29a: native/legacy object-boundary audit passed.
- Stage29b: separate `rtl88wifi-native` target and dry-run checks passed.
- Stage29c-v5: actual native compile/link and bundle validation passed on macOS 15.8.1 (24H32), x86_64. The binary is not installed or loaded.
- Stage29d: read-only Mach-O, C++ symbol, meta-class, dependency and PCI-personality audit runner:
  [stage29d-native-mach-o-audit.sh](./stage29d-native-mach-o-audit.sh)

Run the next audit from the target Mac:

```bash
curl -fsSL https://raw.githubusercontent.com/shammu2bd/BDIX-TV/main/Development/stage29d-native-mach-o-audit.sh | bash
```

Stage29d verifies that the audited executable SHA-256 still matches the Stage29c-v5 build. It does not build, patch, install, load, or change OpenCore. Reports are appended to the canonical [output.log](./output.log).


## Stage29d dependency-resolution caveat / Stage29e

Stage29d's structural Mach-O checks passed, but the legacy `kextlibs` tool reported 804 imports not found and stale extension caches. Treat Stage29d as a structural pass only; symbol-provider resolution remains unverified.

Run the modern, read-only KernelManagement audit on the target Mac:

```bash
curl -fsSL https://raw.githubusercontent.com/shammu2bd/BDIX-TV/main/Development/stage29e-kmutil-symbol-resolution-audit.sh | bash
```

Stage29e uses `kmutil libraries` against the Boot/System Kernel Collections plus `kmutil print-diagnostics`. It does not use `kmutil load`, `--do-staging`, or make any install/OpenCore/source changes. It verifies the binary hash before inspecting it and appends to the canonical `output.log`.


## Stage29e / Stage29f — dependency and packaging status (2026-11-02)

Stage29e established that `kmutil libraries` successfully resolves the native binary's undefined imports to providers in the Sequoia Boot Kernel Collection. However, `kmutil print-diagnostics` emitted content-level errors despite returning exit code 0: the local build bundle is owned by uid:gid 501:20 rather than root:wheel (0:0), and authentication reports a bad code signature. Therefore Stage29e overall status is **REVIEW_REQUIRED**, not PASS. The Stage29e runner has been corrected to inspect diagnostics text as well as exit status.

Stage29f performs read-only ownership, code-signature, xattr and kmutil checks against the exact Stage29d/29e binary. It does not change ownership, sign, install, load, build, or edit OpenCore.

Run on the target Mac:

```bash
curl -fsSL https://raw.githubusercontent.com/shammu2bd/BDIX-TV/main/Development/stage29f-package-auth-audit.sh | bash
```

Do not proceed to installation until ownership and signing validation are resolved. Preserve the existing working legacy kext and OpenCore configuration.


Stage29f completed on the target Mac and **failed its packaging/authentication gate**:
- The native bundle, executable and Info.plist are all owned by uid:gid 501:20.
- `codesign -d` reports `code object is not signed at all`.
- `codesign --verify` fails.
- `kmutil print-diagnostics` repeats invalid ownership and bad-signature errors.
- Stage29f made no changes; the original candidate remains unsigned and user-owned.

Stage29g is a read-only preflight to inspect SIP status, available valid code-signing identities, and whether any Developer ID certificate contains Apple's kext-signing extension OID `1.2.840.113635.100.6.1.18`. It deliberately does not sign, chown, install or load anything.

Run:

```bash
curl -fsSL https://raw.githubusercontent.com/shammu2bd/BDIX-TV/main/Development/stage29g-signing-policy-preflight.sh | bash
```


Stage29g completed on the target Intel Hackintosh:
- SIP is enabled.
- No valid code-signing identity is present in the local keychain.
- No Developer ID Application identity or certificate with kext-signing OID `1.2.840.113635.100.6.1.18` was found.
- The audited binary hash still matches Stage29d.

Therefore, the candidate remains unsigned and is not load-ready under the current security state. Apple’s kext signing guidance requires a special Developer ID Application identity enabled for kext signing; an ordinary app-signing identity is not sufficient. See [Apple TN2206](https://developer.apple.com/library/archive/technotes/tn2206/) and [Apple Platform Security: Securely extending the kernel](https://support.apple.com/guide/security/securely-extending-the-kernel-sec8e454101b/web).

Next decision: establish whether the developer team has Apple Developer Program membership and Account Holder access to request the kext-signing identity. Do not disable SIP or change OpenCore automatically. No signing, ownership, installation or loading has been performed.
