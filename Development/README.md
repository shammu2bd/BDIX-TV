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
6. Preserve every run log as a uniquely named file directly under `Development/Logs/`; never overwrite an earlier run's log. Use the stage and UTC run timestamp in each filename, for example `stage43-run-20261102-040558-report.txt`, `stage43-run-20261102-040558-build.log`, `stage43-run-20261102-040558-source.patch`, and `stage43-run-20261102-040558-manifest.txt`. Timestamped subfolders may also retain the original grouped run artifacts. Keep appending concise stage summaries to `Development/output.log`, but do not use that shared file as the only retained record.


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


## Internal testing route accepted — Stage29h

The user has selected the free internal-testing route. No Developer ID certificate is available on this machine; SIP is currently enabled. The candidate is unsigned.

Apple documents unsigned kext builds for internal testing on test systems with SIP disabled. This route is temporary and lowers system security; SIP should be restored after testing. The obsolete `kext-dev-mode=1` boot argument must not be used.

Stage29h is a read-only Intel Hackintosh boot-policy/test-isolation audit. It inspects current SIP/NVRAM state, mounted OpenCore `config.plist` values for `csr-active-config` and `boot-args`, current matching bundle load state, and the legacy/native bundle-identifier relationship. It does not change NVRAM, SIP, OpenCore, bundle ownership, installation or loading.

Run:

```bash
curl -fsSL https://raw.githubusercontent.com/shammu2bd/BDIX-TV/main/Development/stage29h-boot-policy-and-test-isolation-audit.sh | bash
```

Stage29h must be reviewed before any SIP change. After that, prepare an explicitly separate test EFI/configuration while preserving the known-good everyday EFI and legacy RTL88WiFi kext. The native bundle currently shares the legacy bundle identifier; therefore the two candidates are mutually exclusive and must never be installed side by side. Installation and loading remain blocked until a test-only rollback plan and queue/teardown ABI review are complete.


## Stage29i — read-only EFI partition discovery

Stage29h completed, but no mounted `EFI/OC/config.plist` was found. Stage29i inventories EFI System Partition candidates with `diskutil list -plist`, reports their device identifiers and mount state, and inspects OpenCore settings only if a config is already present on a mounted EFI volume. It does **not** mount an EFI partition or write to it.

Run on the target Mac:

```bash
curl -fsSL https://raw.githubusercontent.com/shammu2bd/BDIX-TV/main/Development/stage29i-efi-partition-discovery.sh | bash
```

If the report lists one or more unmounted EFI partitions, it will print an exact `sudo diskutil mount diskXs1` command for each. Do not guess which EFI to mount: identify the partition used to start OpenCore before mounting. After the correct EFI is mounted, rerun Stage29i so its `config.plist` can be audited. No replacement config is generated until the existing OpenCore config and test-boot strategy are reviewed.


## Stage20 — 24H32 queue contract review ledger

The Stage20 review is a static correlation of the previously collected Stage14–17 target ABI evidence with the Stage18/19 ownership dossier. It records verified sub-facts and keeps the six activation contracts blocked where ownership or teardown is still unresolved.

See [STAGE20-24H32-queue-contract-review.md](./STAGE20-24H32-queue-contract-review.md). This review does not alter driver source, register queues, enable callbacks, start the radio, install/load a kext, or change OpenCore. Do not treat any partial finding as permission to activate the datapath.


## Stage21 — native source-to-ABI contract audit

After Stage20, run this read-only audit on the Stage26 source tree. It inventories current WCL source files, extracts the controller/interface start fences, lists registration and queue call sites, inspects the built native bundle dependencies and compares the executable hash with Stage29c-v5. It appends its report to the canonical Development/output.log and verifies the GitHub update. It does not edit source, build, install, load, register queues, enable callbacks, alter SIP/NVRAM, or change OpenCore.

```bash
curl -fsSL https://raw.githubusercontent.com/shammu2bd/BDIX-TV/main/Development/stage21-native-source-contract-audit.sh | bash
```

The result is intentionally REVIEW_REQUIRED pending manual correlation with the exact 24H32 callbacks and ownership contracts.


## Stage22 — deep source lifecycle and ownership audit

Stage22 is a read-only evidence-collection pass over the Stage26 native WCL source. It records SHA-256 hashes and numbered source contexts for controller/interface start-stop, registration and deregistration, RX/TX callback paths, packet-ticket references, packet-pool and DMA prepare/complete, and queue teardown. The excerpts support manual correlation with the saved Sequoia 15.8.1 (24H32) ABI dossier; they do not by themselves prove ownership or close the activation gate.

Run on the target Mac from the Stage26 project root (or set `PROJECT_DIR`):

```bash
curl -fsSL https://raw.githubusercontent.com/shammu2bd/BDIX-TV/main/Development/stage22-deep-source-lifecycle-audit.sh | bash
```

The runner fetches the canonical `Development/output.log`, verifies Stage21 and prior prerequisites, appends the Stage22 report, uploads it to GitHub and checks the remote blob SHA. It does not modify source, build, install, load, register/enable queues, change OpenCore/SIP/NVRAM, or touch the known-good legacy kext. Stage22 remains REVIEW_REQUIRED and the activation gate remains BLOCKED pending manual closure of all six ownership/lifecycle contracts.

## Stage44 — exact BSD prepare/finalize callback audit

Stage44 is a read-only 24H32 Kernel Collection audit of `IO80211InfraInterface::prepareBSDInterface`, its inherited BSD finalization path, ancestor implementations, and the relevant vtable ownership. It first verifies that the local Stage43 interface source, ABI header, and concrete interface declaration still match their expected SHA-256 fingerprints. It records source context, exact method disassembly, vtable matches, and loaded networking-family context. It does not edit source, build, sign, install, load, change SIP/NVRAM, or modify OpenCore.

Run on the target Mac:

```bash
curl -fsSL https://raw.githubusercontent.com/shammu2bd/BDIX-TV/main/Development/stage44-v4-bsd-prepare-finalize-abi-audit.sh | bash
```

The runner stores temporary output only inside the Stage26 source project's `run log/stage44/` directory. Every report part and supporting audit file is retained both in a timestamped `Development/Logs/stage44/<run>/` folder and as a unique stage/timestamp-named file directly under `Development/Logs/`; every upload is read back and SHA-verified. A concise checkpoint is appended to `Development/output.log`. This audit does not close the activation gate: queue registration, TX/RX completion ownership, publication, and teardown still require verified implementation.
