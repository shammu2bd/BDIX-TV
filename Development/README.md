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
