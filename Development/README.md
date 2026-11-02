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

## Stage45 — exact BSD finalization cleanup callback audit

Stage45 is a read-only 24H32 Kernel Collection audit of the additional virtual call made by Apple's inherited `IOSkywalkNetworkInterface::finalizeBSDInterface` at vtable byte offset `0x858`. It resolves that slot across the relevant IOSkywalk and IO80211 class vtables, checks the neighboring slots, and disassembles each distinct executable target. It also records the Stage43 source fingerprints and the surrounding source lifecycle context. It does not edit source, build, sign, install, load, change SIP/NVRAM, or modify OpenCore.

Run on the target Mac:

```bash
curl -fsSL https://raw.githubusercontent.com/shammu2bd/BDIX-TV/main/Development/stage45-v1-bsd-finalize-cleanup-slot-audit.sh | bash
```

Temporary output stays under the Stage26 source project's `run log/stage45/` directory. Every report part and supporting audit file is saved in a timestamped `Development/Logs/stage45/<run>/` folder and as a unique file directly under `Development/Logs/`; uploads are read back and SHA-verified. A checkpoint is appended to `Development/output.log`. Identifying the callback does not close the activation gate; queue registration, TX/RX completion ownership, publication and full teardown must still be verified.

## Stage46 — network deregistration and packet-pool ownership audit

Stage46 is a read-only macOS Sequoia 15.8.1 (24H32) Kernel Collection audit of the network-interface teardown path exposed by Stage45. It verifies the Stage43 source fingerprints, resolves and disassembles `IOSkywalkNetworkInterface::deregisterNetworkInterface`, discovers the target KC's actual `IOSkywalkLogicalLink` and `IOSkywalkPacketBufferPool` lifecycle symbols, records relevant class vtables and owners, and compares the Apple stop/free teardown sequence with the native WCL source context. Mangled method names are discovered from the actual KC symbol tables rather than guessed. It does not edit source, build, sign, install, load, change SIP/NVRAM, or modify OpenCore.

Run on the target Mac:

```bash
curl -fsSL https://raw.githubusercontent.com/shammu2bd/BDIX-TV/main/Development/stage46-v2-network-deregistration-pool-ownership-audit.sh | bash
```

Temporary output is kept under the Stage26 source project's `run log/stage46/` directory. Reports and supporting evidence are uploaded both to a per-run `Development/Logs/stage46/<run>/` folder and to unique files directly under `Development/Logs/`. Each upload is read back and SHA-verified, and the checkpoint is appended to `Development/output.log`. The activation gate remains blocked until queue registration, TX/RX completion ownership, publication and complete teardown are all verified.

## Stage47 — logical-link and TX/RX queue-set teardown audit

Stage47 is a read-only macOS Sequoia 15.8.1 (24H32) Kernel Collection audit of the next layer after Stage46: `IOSkywalkNetworkInterface::deleteLogicalLink`, `IOSkywalkLogicalLink` ownership, `IOSkywalkQueueSet` attachment/detachment, and TX/RX submission/completion queue lifecycle. It resolves symbols and vtable targets from the actual target Kernel Collection, verifies owner/executable ranges, disassembles relevant methods, and captures matching native WCL source context plus the Stage43 source fingerprints. It does not edit source, build, sign, install, load, change SIP/NVRAM, or modify OpenCore.

Run on the target Mac:

```bash
curl -fsSL https://raw.githubusercontent.com/shammu2bd/BDIX-TV/main/Development/stage47-v1-logical-link-queue-teardown-audit.sh | bash
```

Temporary output is kept under the Stage26 source project's `run log/stage47/` directory. Report and ABI audit parts, source context, source fingerprints and upstream verification are uploaded in a timestamped `Development/Logs/stage47/<run>/` folder and as unique files directly under `Development/Logs/`. Each upload is read back and SHA-verified; a checkpoint is appended to `Development/output.log`. The activation gate remains blocked until queue registration, TX/RX completion ownership, publication and safe rollback/teardown are verified.

## Stage48 — registration bridge, queue construction and callback ABI audit

Stage48 is a read-only audit of the next layer after Stage47. It discovers and disassembles the actual 24H32 implementations for `IO80211InfraInterface::registerInfraEthernetInterface`, the `IOSkywalkEthernetInterface` registration overloads, `IOSkywalkNetworkInterface` registration, `IOSkywalkQueueSet` construction, and packet-queue/TX/RX initializer and callback-bearing methods. It records the mangled constructor signatures, direct call edges, relevant vtable targets, matching WCL source context, loaded networking-family context, and the Stage43 source fingerprints. Method names are discovered from the target Kernel Collection instead of being guessed. It does not edit source, build, sign, install, load, change SIP/NVRAM, or modify OpenCore.

Run on the target Mac:

```bash
curl -fsSL "https://raw.githubusercontent.com/shammu2bd/BDIX-TV/main/Development/stage48-v1-registration-queue-construction-audit.sh" | bash
```

Temporary output is kept under the Stage26 source project's `run log/stage48/` directory. Report, ABI-audit and source-context parts, source fingerprints and upstream verification are uploaded both to a timestamped `Development/Logs/stage48/<run>/` folder and as unique files directly under `Development/Logs/`. Each upload is read back and SHA-verified; a concise checkpoint is appended to `Development/output.log`. The runner stops if the Stage43 source fingerprints do not match. The activation gate remains blocked: this audit maps Apple's registration and callback ABI but does not implement queue creation, TX/RX completion, interface publication or safe rollback in RTL88WiFi.

## Stage49 — native source-to-24H32 ABI correlation and activation-gap audit

Stage49 is a read-only correlation pass over the Stage26 RTL88WiFi native WCL source and the exact Stage48 Sequoia 15.8.1 (24H32) registration/queue ABI evidence. It captures numbered source context and builds a cautious pattern-presence gap matrix for registration-info lifecycle, queue constructors and callback wiring, queue-set grouping/order, TX/RX pool ownership, TX completion/ticket draining, RX refill/network enqueue, and rollback/teardown. It retrieves the Stage48 ABI reports from GitHub, verifies the Stage43 source fingerprints, and records the evidence locally before uploading grouped and unique root-mirror artifacts with Git blob SHA readback verification. Pattern matches are evidence pointers, not proof of semantic correctness; manual review remains mandatory.

Run on the target Intel Hackintosh:

```bash
curl -fsSL "https://raw.githubusercontent.com/shammu2bd/BDIX-TV/main/Development/stage49-v2-source-to-abi-correlation-audit.sh" | bash
```

V2 corrects the teardown-pattern regular expression that stopped the first runner and uploads the manifest only after all artifact paths are recorded. All temporary files are stored under the Stage26 source project's `run log/stage49/<run>/` directory. The runner appends a checkpoint to `Development/output.log`. It does not edit driver source, build, sign, install or load a kext, modify OpenCore/SIP/NVRAM, or touch the known-good legacy kext. The activation gate remains BLOCKED; Stage49 does not authorize queue registration or hardware testing.


## Stage50 — exact registration call-graph and callback reachability audit

Stage50 V2 is a read-only source inspection that extracts the actual out-of-line method bodies for interface/controller startup, registration-info preparation, `RTW88WCLSkywalkQueues::createQueues`, all four Skywalk queue callbacks, and the TX/RX adapter handoff methods. V2 corrects the initial audit's method-name typo (`allocateQueues` versus the actual `createQueues`) so the queue-construction body is captured. It masks comments and quoted strings for brace matching, inventories code occurrences of registration and queue APIs, and checks direct body-level edges instead of treating keyword presence as proof. It also verifies the pinned Stage48 24H32 ABI audit artifacts and the Stage43 source fingerprints. A direct-body result is deliberately not presented as proof of transitive runtime reachability.

Run on the target Intel Hackintosh:

```bash
curl -fsSL "https://raw.githubusercontent.com/shammu2bd/BDIX-TV/main/Development/stage50-v2-registration-callgraph-reachability-audit.sh" | bash
```

Temporary files are stored only under the Stage26 source project's `run log/stage50/<run>/` directory. The runner uploads grouped and unique root-mirror artifacts with Git blob SHA readback verification, then appends a checkpoint to `Development/output.log`. It does not edit driver source, build, sign, install or load a kext, modify OpenCore/SIP/NVRAM, or touch the known-good legacy kext. The activation gate remains BLOCKED; Stage50 is an audit only and does not authorize queue registration or hardware testing.


## Stage51 — controller / infrastructure-interface ownership and lifecycle audit

Stage51 is a read-only source audit of the relationship between `RTW88WCLController` and `RTW88WCLInfraInterface`. It extracts the qualified out-of-line methods for both classes, inventories code-only references across the source tree, and checks direct method-body edges for object construction, radio attach/detach, primary Skywalk interface wiring, registration preparation, and start/stop/free ordering. It also scans textual personality/metadata files for class references and verifies the Stage43 source fingerprints. A direct reference is evidence of a source edge, not proof of runtime execution.

Run on the target Intel Hackintosh:

```bash
curl -fsSL "https://raw.githubusercontent.com/shammu2bd/BDIX-TV/main/Development/stage51-v1-controller-interface-lifecycle-audit.sh" | bash
```

Temporary files are stored only under the Stage26 source project's `run log/stage51/<run>/` directory. The runner uploads grouped and unique root-mirror artifacts with Git blob SHA readback verification, then appends a checkpoint to `Development/output.log`. It does not edit driver source, build, sign, install or load a kext, modify OpenCore/SIP/NVRAM, or touch the known-good legacy kext. The activation gate remains BLOCKED; this audit does not authorize interface registration or hardware testing.


## Stage52 — IOKit personality, class-registration and provider-contract audit

Stage52 is a read-only audit of the IOKit service/personality contract connecting the native controller and infrastructure protocol. It parses every kext `Info.plist` under the source tree and reports `IOKitPersonalities` keys such as `IOClass`, `IOProviderClass` and `IOMatchCategory`; indexes class inheritance and `OSMetaClass` declarations; extracts provider-init, `attachRadio`, `getController`, controller-start and teardown method bodies; and maps source references to interface factories, primary-interface getters/setters and service registration. It verifies the Stage43 source fingerprints and reports direct source edges separately from possible Apple framework-internal behavior.

Run on the target Intel Hackintosh:

```bash
curl -fsSL "https://raw.githubusercontent.com/shammu2bd/BDIX-TV/main/Development/stage52-v1-iokit-personality-provider-contract-audit.sh" | bash
```

Temporary files are stored only under the Stage26 source project's `run log/stage52/<run>/` directory. The runner uploads grouped and unique root-mirror artifacts with Git blob SHA readback verification, then appends a checkpoint to `Development/output.log`. It does not edit driver source, build, sign, install or load a kext, modify OpenCore/SIP/NVRAM, or touch the known-good legacy kext. The activation gate remains BLOCKED; this audit does not authorize interface registration or hardware testing.


## Stage53 — IO80211 controller/interface factory and vtable audit

Stage53 V2 is a read-only audit of the exact macOS Sequoia 15.8.1 (24H32) Boot Kernel Collection. It discovers actual methods and vtables for `IO80211Controller`, `IO80211SkywalkInterface`, `IO80211InfraInterface`, `IO80211InfraProtocol` and Apple's `AppleBCMWLANSkywalkInterface`. It resolves and disassembles the primary Skywalk interface getter, infrastructure-interface start/registration methods, Skywalk initialization and Apple's two interface-start overloads where present. It records direct call edges, owner/executable-range checks, the pinned Stage43 source fingerprints and the matching native source contract context. Apple Broadcom code is reference evidence only; its vendor-specific implementation must not be copied blindly.

Run on the target Intel Hackintosh:

```bash
curl -fsSL "https://raw.githubusercontent.com/shammu2bd/BDIX-TV/main/Development/stage53-v2-io80211-interface-factory-vtable-audit.sh" | bash
```

Temporary files are stored only under the Stage26 source project's `run log/stage53/<run>/` directory. The corrected V2 runner converts the output argument to a pathlib.Path before writing audit artifacts. It uses the pinned WTLKcAbi parser/disassembler, uploads grouped and unique root-mirror artifacts with Git blob SHA readback verification, then appends a checkpoint to `Development/output.log`. It does not edit driver source, build, sign, install or load a kext, modify OpenCore/SIP/NVRAM, or touch the known-good legacy kext. The activation gate remains BLOCKED; this audit does not authorize interface registration or hardware testing.


## Stage54 — exact Skywalk interface initializer, factory and lifecycle audit

Stage54 V2 is a read-only audit of the macOS Sequoia 15.8.1 (24H32) Boot Kernel Collection. It resolves the exact `IO80211SkywalkInterface::init(IOService*, ether_addr*)` provider initializer (not the unrelated `initIvars()` helper), the controller primary-interface getter, Skywalk/infra interface start-stop-free and registration methods, and Apple's reference `AppleBCMWLANCore` factory/lifecycle methods (`skywalkInfraInit`, `createSkywalkInterface`, `destroySkywalkInterface`, and `getSkywalkInterface`). It records vtable slots, validated method ownership, executable ranges, disassembly, and direct/indirect dispatch call sites. Apple Broadcom implementation is reference evidence only and must not be copied blindly.

Run on the target Intel Hackintosh:

```bash
curl -fsSL "https://raw.githubusercontent.com/shammu2bd/BDIX-TV/main/Development/stage54-v2-exact-interface-initializer-factory-lifecycle-audit.sh" | bash
```

Temporary files are kept under the Stage26 source project's `run log/stage54/<run>/` directory. The corrected V2 runner fixes the method range formatter by supplying both range endpoints. It checks the pinned WTLKcAbi tools and Stage43 source fingerprints, uploads grouped and unique root-mirror artifacts with Git blob SHA readback verification, and then appends a checkpoint to `Development/output.log`. It does not edit driver source, build/sign/install/load a kext, change OpenCore/SIP/NVRAM, or touch the known-good legacy kext. The activation gate remains BLOCKED; this audit does not authorize interface registration or hardware testing.


## Stage55 — native factory, registration and datapath reachability crosswalk

Stage55 is a read-only source-to-ABI correlation audit for the Sequoia 15.8.1 (24H32) native WCL frontend. It downloads and Git-blob-SHA verifies the completed Stage54 V2 evidence, checks the Stage43 source fingerprints, extracts the native controller/interface method bodies, and inventories call sites related to interface construction, provider initialization, radio attachment, primary-interface publication, Ethernet/network registration, QueueSet/LogicalLink creation, and TX/RX adapter callbacks. The reachability matrix distinguishes what is present from what was not found in the selected method bodies; absence from that scope is not treated as proof of global absence. This stage does not modify source, build/sign/install/load a kext, or alter OpenCore/SIP/NVRAM.

Run on the target Intel Hackintosh:

```bash
curl -fsSL "https://raw.githubusercontent.com/shammu2bd/BDIX-TV/main/Development/stage55-v1-native-factory-registration-reachability-audit.sh" | bash
```

Temporary output remains under the Stage26 source project's `run log/stage55/<run>/` directory. Artifacts are uploaded to grouped and unique root-mirror paths with Git blob SHA readback verification, followed by a checkpoint in `Development/output.log`. The activation gate remains BLOCKED; this is an audit, not an implementation or hardware-test authorization.
