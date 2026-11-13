# mac-inspect

A one-command, **read-only** health and authenticity report for a Mac, built only from tools that ship with macOS.

Use it to check your own Mac's condition, or to check a **used Mac before you buy it**: locks, remote management, replaced or non-genuine parts, battery wear, storage, charger and more. It ends with a verdict for each area and a checklist of hands-on tests.

```bash
curl -fsSL https://raw.githubusercontent.com/rif-qi/mac-inspect/main/mac-inspect.sh | bash
```

No install, no app, nothing left behind. Takes about 6 seconds.

---

## Usage

| What | Command |
|---|---|
| Full report | `curl -fsSL https://raw.githubusercontent.com/rif-qi/mac-inspect/main/mac-inspect.sh \| bash` |
| Add live CPU/GPU power, clocks and thermal pressure (asks for your Mac password) | `curl -fsSL https://raw.githubusercontent.com/rif-qi/mac-inspect/main/mac-inspect.sh \| bash -s -- --deep` |
| Plain text, for pasting into a chat or ticket | `curl -fsSL https://raw.githubusercontent.com/rif-qi/mac-inspect/main/mac-inspect.sh \| NO_COLOR=1 bash` |
| Help / version | `bash mac-inspect.sh --help` · `bash mac-inspect.sh --version` |

### Read it before you run it

Piping a script from the internet into `bash` means trusting it. Read it first; it's one file:

```bash
curl -fsSL https://raw.githubusercontent.com/rif-qi/mac-inspect/main/mac-inspect.sh | less
```

For a version that can't change after you've read it, use a release tag instead of `main`, and compare the SHA-256 checksum published with that [release](https://github.com/rif-qi/mac-inspect/releases):

```bash
curl -fsSL https://raw.githubusercontent.com/rif-qi/mac-inspect/v1.0.0/mac-inspect.sh -o mac-inspect.sh
shasum -a 256 mac-inspect.sh
bash mac-inspect.sh
```

### Make it a command

Add this line to `~/.zshrc`, then open a new Terminal window and type `mac-inspect` (or `mac-inspect --deep`):

```bash
alias mac-inspect='curl -fsSL https://raw.githubusercontent.com/rif-qi/mac-inspect/v1.0.0/mac-inspect.sh | bash -s --'
```

---

## What it checks

| Area | Checks |
|---|---|
| **System** | Model, model number, CPU and GPU cores, memory, macOS and firmware version, uptime, virtual-machine detection |
| **Performance** | CPU and GPU use right now, load average, heat throttling, Low Power Mode |
| **Live power** (`--deep`) | CPU/GPU power draw, clock speeds against their maximum, thermal pressure, with a plain-English explanation |
| **Memory** | Memory pressure, what's using it (apps / system / compressed), swap |
| **Storage** | SSD model, SMART status, free space, Time Machine local snapshots, SSD wear (if `smartctl` is installed) |
| **Battery** | Charge, condition, health vs. original capacity, cycle count, temperature, fault flags |
| **Charger** (when plugged in) | Maker and serial (genuine or not), wattage, negotiated voltage, whether it's actually charging |
| **Display & wireless** | Displays and resolution, Wi‑Fi band, link speed and signal, Bluetooth |
| **Security** | Apple Account sign-in, Activation Lock, local accounts, SIP, FileVault, Gatekeeper, firewall, Touch ID, MDM enrollment, configuration profiles, third-party background items |
| **Parts & reliability** | Retail / refurbished / replacement unit, serial number validity, original SSD, Apple screen panel, battery cell maker and serial, impossible battery capacity, kernel panics in the last 30 days |
| **Top processes** | Top 5 by CPU and by memory |
| **Test by hand** | Links and instructions for keyboard, display, 120 Hz, speakers, camera, microphone, trackpad, ports, charging and Apple Diagnostics |

### How to read the flags

| Flag | Meaning |
|---|---|
| ✓ | Fine |
| · | Information only |
| **!** Watch | Wear, a setting, or something to confirm |
| **✗** Problem | Needs action |
| **⚑** Suspicious | Signs of replaced, fake, locked or tampered parts or system: explain it before trusting or buying the Mac |

The report ends with a **verdict** per area, an overall verdict, and every flagged item grouped by severity.

---

## Buying a used Mac

Run the report on the Mac in front of you, then check:

- **⚑ Managed (MDM)**: an organization can lock or wipe it remotely. Fine on a company laptop, a deal-breaker on a personal one. "Auto-enrolled" is worst: it comes back even after erasing.
- **! Activation Lock**: must be **Off** before you pay, or the Mac stays tied to the seller's Apple Account.
- **⚑ in Parts & reliability**: ask the seller to explain any replaced parts, ideally with a repair receipt.

Two extra checks the report can't do on its own:

```bash
sudo profiles show -type enrollment
```

This asks Apple's servers whether the Mac is registered to an organization, even if its management profile was removed. It needs a password and internet. Also enter the serial number at [checkcoverage.apple.com](https://checkcoverage.apple.com): the model shown should match the Mac.

---

## Privacy and safety

- **Read-only.** It only reads system information; it changes no settings and writes no files.
- **No network.** The script itself makes no network requests. (The `curl` that downloads it is the only one.)
- **Nothing sensitive printed.** The serial number, Apple ID, Wi‑Fi network names and Bluetooth device names are checked but never shown.
- **`--deep` is optional.** It only uses your password to run Apple's own `powermetrics` for 2 seconds.
- **Before sharing your output publicly**, review it: it can include your organization's MDM server name and the names of apps you're running.

## Limitations

- Parts and charger checks are **clues, not proof**. They catch common replacements and counterfeits, but a careful fake can report convincing values, and a clean report can't guarantee every part is original. macOS doesn't expose a full parts history.
- Tested on macOS 15 on Apple silicon (MacBook Pro, M1 Pro). It should work on other recent Macs, including Intel, but those paths are less tested. Issues and pull requests are welcome.

Not affiliated with or endorsed by Apple Inc. "Mac", "MacBook" and "Apple" are trademarks of Apple Inc.

## License

[MIT](LICENSE)
