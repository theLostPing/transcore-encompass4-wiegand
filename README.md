# TransCore Encompass 4 — Enable Wiegand over Serial

A small, dependency-free **PowerShell** tool to read and configure a **TransCore Encompass 4 (E4)** RFID reader over its RS-232 serial port — specifically to **turn on Wiegand output** when the reader reads tags but sends nothing to the access-control panel.

No modules, no installers — just `System.IO.Ports.SerialPort`, which is built into Windows PowerShell.

---

## The problem

On a field job I had to find out why a TransCore Encompass 4 would **click on a tag but send no Wiegand output** to the gate access panel. The RF side was clearly fine — it read tags — but the panel got nothing.

The cause is simple, and it's **buried in the documentation rather than missing from it**: the Encompass 4 ships from the factory with **Wiegand output disabled**. This unit had never been programmed. Querying it confirmed the smoking gun — `#532` returned `TOF 0` (Wiegand off). Nothing was broken; it just needed to be configured over serial.

> **As of May 2026** — the manufacture date stamped on the unit I worked on, firmware `Ver 1.12` — Wiegand was off out of the box. Factory defaults can change between production runs, so always run a **read** first to confirm your unit's actual state rather than assuming.

This repo is the script I wrote to talk to the port directly (terminal apps like PuTTY were unreliable — CR handling, and the reader "dings" on input), plus everything I had to work out about the hardware and command set. Published in case it saves the next person the afternoon it cost me.

---

## The quick fix

Once you have a serial connection (hardware below), the whole fix is sending this in order:

```
#01    enter command mode
#451   Wiegand output ON
#871   26-bit Wiegand format
#6401  RF ON
#00    return to data mode (commits the change to non-volatile memory)
```

That's exactly what `.\e4-serial.ps1 wiegand` does, with an automatic read-back to confirm.

---

## Is your reader RS-232? (check this first)

The serial type is encoded in the **part number**, and it decides whether any of this will work:

- `10-40`**`x2`**`-…` → **RS-232** — works with this script and a normal serial / console cable.
- `10-40`**`x4`**`-…` → **RS-422** — a plain console cable or USB-RS232 adapter **will not** talk to it; you'd need an RS-422 adapter.

Tested here on a **TransCore Encompass 4, model `10-4002-024`** (internal antenna). Serial settings throughout: **9600 baud, 8-N-1, no flow control**, every command terminated with a **carriage return (CR)**.

---

## The cable

You need a **true RS-232** USB serial connection — **not TTL.** Two options work:

- A **USB-to-DB9 RS-232 adapter** (FTDI or Prolific) — simplest.
- A **USB-to-RJ45 "Cisco" console cable** (FTDI-based). These have proper RS-232 level shifting, so they're electrically compatible with the reader. **This is what I used.**

**The exact cable I used — suggested, not required:** [USB Console Cable — USB to RJ45 Console Cable for Cisco Routers / AP Router / Switch, Windows / Mac / Linux (1.8 m, Blue)](https://www.amazon.com/dp/B075V1RGQK).

> **Any true RS-232 adapter *may* work** — the only hard requirements are real RS-232 levels (not TTL) and an RS-232 reader part number (`10-40x2-…`). But cheap clones vary in chipset and RJ45 pinout, so a different adapter may or may not behave. Whatever you use, prove it with the loopback test below before trusting it (some won't enumerate; some have TX/RX swapped).

---

## Wiring

The reader needs exactly **three wires — TX, RX, and GND.** It's wired as **DCE**, so it maps **straight** to a PC DB9 — no null-modem needed.

### The reader's three wires

The RS-232 signals live on two of the reader's twisted pairs:

| Reader wire | Twisted pair | Function |
|-------------|--------------|----------|
| **Black** | Red/Black pair | reader **TX** (→ your RX) |
| **Red** | Red/Black pair | reader **RX** (← your TX) |
| **Yellow** | Yellow/Black pair | **Signal Ground** |

> ⚠️ **Do not use Blue for ground.** On this reader **Blue is Wiegand Data0** — the RS-232 signal ground is the **Yellow** wire of the Yellow/Black pair. (Separately, connect the cable shield to earth ground for surge protection.)

### Verify the cable first (loopback)

Before landing anything on the reader, prove the cable's pinout:

1. With nothing else connected, **bridge RJ45 pins 3 and 6** (or DB9 pins 2 and 3) with a jumper.
2. Open a terminal on your COM port and type.
3. If your characters **echo back**, the cable is good — pin 3 = TX, pin 6 = RX on *your* specific cable. No echo means it isn't wired the way you think — fix that before going further.

### Landing them on the reader

Use whichever cable you have.

**USB-to-DB9 adapter** — land the three wires straight onto the DB9 pins (DB25 in parentheses):

| Reader wire | Host DB9 pin (DB25) |
|-------------|---------------------|
| **Black** (reader TX) | **2** (3) |
| **Red** (reader RX) | **3** (2) |
| **Yellow** (GND) | **5** (7) |

**USB-to-RJ45 console cable** — **don't cut the RJ45 tip off your cable.** You'll want a plain **RJ45 coupler** and a piece of **Cat6** between the cable and the reader **regardless of distance** — a foot or fifty feet — so your console cable stays intact and reusable. Plug the console cable into the coupler, run the Cat6 from there to the reader (RJ45 end into the coupler), then cut and strip the far end and land its bare conductors on the reader's leads. This is how I did it, using **one half of a Cat6 patch cable**.

With standard **T568B** color coding, only three of the eight conductors are used:

| Cat6 conductor (T568B) | RJ45 pin | Console-cable signal | Lands on reader |
|------------------------|----------|----------------------|-----------------|
| **green/white** (green stripe) | 3 | TXD (cable → reader) | reader **RX** — Red |
| **green** | 6 | RXD (reader → cable) | reader **TX** — Black |
| **blue** | 4 | GND | reader **GND** — Yellow |

Only **green, green/white, and blue** matter; the other five go unused. (If your cable or coupler is wired **T568A**, the green and orange pairs swap — re-verify with the loopback test.)

### No sign-on banner? Swap the data leads

The single most common gotcha. If `listen` (below) shows nothing when you power-cycle the reader, your **TX/RX are backwards**: swap the two data wires, **Black ↔ Red** (the Red/Black pair), and try again. Yellow / ground stays put.

---

## Using the script — step by step

Once the reader is wired up, the whole job is four commands. Run them from PowerShell in the repo folder.

**Step 1 — Point the script at your COM port.** Open `e4-serial.ps1` and set `$PORT` at the top to your port (find it in **Device Manager → Ports (COM & LPT)**, e.g. `COM3`).

**Step 2 — Prove the link (`listen`).** Listen for the reader's power-on banner, then power-cycle the reader within the 30-second window:

```powershell
powershell -ExecutionPolicy Bypass -File .\e4-serial.ps1 listen
```

Nothing appears? See **"No sign-on banner? Swap the data leads"** above.

**Step 3 — Read the current config (`read`).** Always do this before changing anything:

```powershell
powershell -ExecutionPolicy Bypass -File .\e4-serial.ps1 read
```

Look at `#532`: **`TOF 0` means Wiegand is OFF** — the smoking gun. This is your starting state.

**Step 4 — Enable Wiegand and save (`wiegand`).** Sends the enable sequence, commits it to non-volatile memory, and reads it back to confirm:

```powershell
powershell -ExecutionPolicy Bypass -File .\e4-serial.ps1 wiegand
```

Power-cycle the reader and present a tag — the panel should now receive 26-bit Wiegand.

> **This is permanent.** `wiegand` ends with `#00`, which commits the change to **non-volatile memory** — it survives a reader reboot/power-cycle. Once the read-back shows Wiegand enabled, the job is done; you don't need to return to the site.

**Ad-hoc — send any single command (`send`).**

```powershell
powershell -ExecutionPolicy Bypass -File .\e4-serial.ps1 send "#570"
```

---

## Command reference

The E4 command set is large; these are the ones relevant to this task — listed in the order you'd actually use them: **enter command mode → query → change → save & exit.**

| Command | Meaning |
|---------|---------|
| `#01` | **Enter command mode** — send first |
| `#505` | *Query:* firmware version / model / serial number |
| `#527` | *Query:* RF status |
| `#570` | *Query:* enabled tag protocols |
| `#532` | *Query:* Wiegand enabled? — **`TOF 0` = Wiegand OFF** (the smoking gun) |
| `#531` | *Query:* Wiegand format |
| `#533` | *Query:* Wiegand interval |
| `#451` | *Change:* Wiegand output **ON** |
| `#871` | *Change:* **26-bit** Wiegand format |
| `#6401` | *Change:* RF **ON** |
| `#00` | **Save & exit** — commit changes to NVM and return to data mode; **send last** |

---

## Notes

- **Wiegand is not serial.** This script configures the reader *over* RS-232. Once enabled, the reader outputs Wiegand on its dedicated **D0/D1** data leads to the access panel — you do not read Wiegand back through this serial port.
- `#00` commits to non-volatile memory, so the setting survives a power cycle.
- Default RF frequency on US units is ~915 MHz.

## License

MIT — see [LICENSE](LICENSE). Use at your own risk; this touches live access-control hardware.
