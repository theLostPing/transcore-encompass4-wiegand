# TransCore Encompass 4 — Enable Wiegand over Serial

A small, dependency-free **PowerShell** tool to read and configure a **TransCore Encompass 4 (E4)** RFID reader over its RS-232 serial port — specifically to **turn on Wiegand output** when the reader reads tags but sends nothing to the access-control panel.

No modules, no installers. Just `System.IO.Ports.SerialPort` from built-in PowerShell.

## Why this exists

While working a field job, I was tasked with figuring out why a TransCore Encompass 4 reader would **click/read a tag but produce no Wiegand output** to the gate access panel. The RF side was clearly working — it saw tags — but the panel got nothing.

The cause was simple and undocumented anywhere obvious: **the Encompass 4 ships from the factory with Wiegand output DISABLED.** This unit had never been programmed. Querying it confirmed the smoking gun — `#532` returned `TOF 0` (Wiegand off). Nothing was broken; it just needed to be configured over serial, which requires a **true RS-232** connection and the right command sequence. Terminal apps (PuTTY etc.) were unreliable for this — CR handling and the reader "dinging" on input — so I wrote this script to talk to the serial port directly.

This repo is that script, plus everything I had to work out about the hardware, wiring, and command set — published in case it saves the next person the afternoon it cost me.

## TL;DR fix

Reads a tag but no Wiegand at the panel? The reader almost certainly has Wiegand **disabled** from the factory. Connect to its RS-232 port and send:

```
#01    enter command mode
#451   Wiegand output ON
#871   26-bit Wiegand format
#6401  RF ON
#00    return to data mode (commits to non-volatile memory)
```

That is exactly what `.\e4-serial.ps1 wiegand` does, with an automatic read-back to confirm.

## Is your reader RS-232? (check the part number first)

- Tested on: **TransCore Encompass 4, model `10-4002-024`** (internal antenna).
- **The serial type is encoded in the part number:**
  - `10-40`**`x2`**`-…` → **RS-232** — works with this script and a normal serial/console cable.
  - `10-40`**`x4`**`-…` → **RS-422** — a plain console cable / USB-RS232 adapter will **not** talk to it; you'd need an RS-422 adapter.
- Serial settings: **9600 baud, 8-N-1, no flow control**, commands terminated with a **carriage return (CR)**.

## What you need

- A Windows laptop with PowerShell (built-in — nothing to install).
- A **true RS-232** USB serial connection — **not TTL.** Two options that work:
  - A **USB-to-DB9 RS-232 adapter** (FTDI or Prolific) — simplest.
  - A **USB-to-RJ45 "Cisco" console cable** (FTDI-based). These have proper RS-232 level shifting, so they're electrically compatible with the reader. **This is what I used** (a generic FTDI Cisco-style USB console cable).
- A few jumper wires to land the reader's serial leads onto the cable.

## Wiring

The reader needs **3 serial wires: TX, RX, and GND.**

If you use an **FTDI USB-to-RJ45 console cable**, the RJ45 end typically pins out as:

| RJ45 pin | Signal |
|----------|--------|
| 3 | TXD (cable → reader) |
| 6 | RXD (reader → cable) |
| 4 & 5 | GND |

Cross TX/RX between the two sides:

- Reader **TX** → cable **RXD (pin 6)**
- Reader **RX** → cable **TXD (pin 3)**
- Reader **GND** → cable **GND (pin 4 or 5)**

**Verify your cable first:** bridge pins 3 and 6 with a jumper (loopback) and confirm a terminal echoes what you type. That proves pin 3 = TX / pin 6 = RX on *your* specific cable — some clones differ.

> ### Got no sign-on banner? Swap your two data leads.
> This is the single most common gotcha. If `listen` mode shows nothing when you power-cycle the reader, your **TX/RX are backwards** — swap the two data wires and try again. (GND stays put.)

## Usage

Set `$PORT` at the top of the script to match your COM port (Device Manager → Ports). Then, from PowerShell:

```powershell
# 1. Prove the wiring — listen for the reader's power-on banner,
#    then power-cycle the reader within the 30-second window.
powershell -ExecutionPolicy Bypass -File .\e4-serial.ps1 listen

# 2. Non-destructive read-out of the current config (start here).
powershell -ExecutionPolicy Bypass -File .\e4-serial.ps1 read

# 3. Enable 26-bit Wiegand and save, with read-back to confirm.
powershell -ExecutionPolicy Bypass -File .\e4-serial.ps1 wiegand

# 4. Send any single command and print the reply.
powershell -ExecutionPolicy Bypass -File .\e4-serial.ps1 send "#570"
```

Always run `read` before `wiegand` so you know the starting state.

## Command reference

The E4 command set is large; these are the ones relevant to this task.

| Command | Meaning |
|---------|---------|
| `#01` | Enter **command mode** |
| `#00` | Return to **data mode** (commits/saves changes to NVM) |
| `#505` | Firmware version / model / serial number |
| `#527` | RF status |
| `#570` | Enabled tag protocols |
| `#532` | Wiegand enabled? — **`TOF 0` = Wiegand OFF** (the smoking gun) |
| `#531` | Wiegand format |
| `#533` | Wiegand interval |
| `#451` | Wiegand output **ON** |
| `#871` | **26-bit** Wiegand format |
| `#6401` | RF **ON** |

## Notes

- **Wiegand is not serial.** This script configures the reader *over* RS-232. Once enabled, the reader outputs Wiegand on its dedicated **D0/D1** data leads to your access panel — you do not read Wiegand back through this serial port.
- `#00` commits to non-volatile memory, so the setting survives a power cycle.
- Default RF frequency on US units is ~915 MHz.

## License

MIT — see [LICENSE](LICENSE). Use at your own risk; this touches live access-control hardware.
