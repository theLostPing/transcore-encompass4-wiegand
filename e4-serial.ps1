# ============================================================
#  TransCore Encompass 4 (E4)  -  Serial test/config toolkit
#  Reader: 10-4002-024  (internal antenna, RS-232)
#  Port:   COM6  @ 9600 8-N-1, no flow control
#
#  Enables Wiegand output on a reader that reads tags but sends
#  nothing to the access panel (factory default: Wiegand OFF).
#  Full docs + wiring: see README.md
#
#  Usage (run on the LAPTOP, in PowerShell, from wherever you save this):
#     powershell -ExecutionPolicy Bypass -File .\e4-serial.ps1 test      <- confirm link, NO power-cycle
#     powershell -ExecutionPolicy Bypass -File .\e4-serial.ps1 listen
#     powershell -ExecutionPolicy Bypass -File .\e4-serial.ps1 read
#     powershell -ExecutionPolicy Bypass -File .\e4-serial.ps1 wiegand
#     powershell -ExecutionPolicy Bypass -File .\e4-serial.ps1 power     <- menu-driven RF power/range
#     powershell -ExecutionPolicy Bypass -File .\e4-serial.ps1 send "#570"
# ============================================================

param(
    [string]$mode = "read",
    [string]$arg  = ""
)

$PORT = "COM6"     # <-- change to match your COM port (Device Manager > Ports)
$BAUD = 9600

function Open-E4 {
    $sp = New-Object System.IO.Ports.SerialPort($PORT,$BAUD,[System.IO.Ports.Parity]::None,8,[System.IO.Ports.StopBits]::One)
    $sp.NewLine     = [char]13      # carriage return
    $sp.ReadTimeout = 1500
    $sp.WriteTimeout= 1500
    $sp.Open()
    return $sp
}

function Send-Cmd($sp,$cmd,$waitMs=500){
    $sp.DiscardInBuffer()
    $sp.Write($cmd + [char]13)
    Start-Sleep -Milliseconds $waitMs
    return $sp.ReadExisting()
}

function Show-RF($sp){
    # Read #527 and pretty-print the RF status string.
    # e.g.  #RFST C1 O1 T1 F20 R1F G1F A00 I04 E1F
    $raw = (Send-Cmd $sp "#527").Trim()
    Write-Host ("  raw: " + $raw) -ForegroundColor DarkGray
    if($raw -match 'F([0-9A-Fa-f]{2,3}).*R([0-9A-Fa-f]{2}).*G([0-9A-Fa-f]{2}).*A([0-9A-Fa-f]{2}).*I([0-9A-Fa-f]{2})'){
        $A = [Convert]::ToInt32($matches[4],16)
        $R = [Convert]::ToInt32($matches[2],16)
        $G = [Convert]::ToInt32($matches[3],16)
        Write-Host ("  TX attenuation  A{0}  = {1} dB cut   (0 = max power)" -f $matches[4].ToUpper(), $A) -ForegroundColor Cyan
        Write-Host ("  ATA recv range  R{0}  = {1}/31      (1F = max range)" -f $matches[2].ToUpper(), $R) -ForegroundColor Cyan
        Write-Host ("  SeGo/eGo range  G{0}  = {1}/31      (1F = max range)" -f $matches[3].ToUpper(), $G) -ForegroundColor Cyan
    } else {
        Write-Host "  (could not parse RFST string)" -ForegroundColor Red
    }
}

function To-Hex2($n){ return ('{0:X2}' -f [int]$n) }

switch ($mode) {

  "test" {
        # LINK TEST - confirms two-way comms WITHOUT a power-cycle.
        # Asks the reader its model (#505); a reply means TX and RX are both good.
        $sp = Open-E4
        Write-Host "--- LINK TEST (no power-cycle needed) ---" -ForegroundColor Green
        [void](Send-Cmd $sp "#01")
        $sn = (Send-Cmd $sp "#505").Trim()
        [void](Send-Cmd $sp "#00")
        if($sn -match "Model|Ver|SN" -or $sn -match "^#\w"){
            Write-Host ("LINK OK -> " + $sn) -ForegroundColor Green
        } else {
            Write-Host ("NO REPLY [" + $sn + "] - check COM port, baud 9600, wiring (swap Red/Black), reader power.") -ForegroundColor Red
        }
        $sp.Close()
  }

  "listen" {
        # LISTEN ONLY - tests reader-TX -> laptop-RX path.
        # Power-cycle the reader during the window to catch its sign-on banner.
        # No banner? Swap your two data leads (TX/RX backwards).
        $sp = Open-E4
        Write-Host "PORT OPEN. POWER-CYCLE THE READER NOW. Listening 30s..." -ForegroundColor Yellow
        $end=(Get-Date).AddSeconds(30); $buf=""
        while((Get-Date) -lt $end){ if($sp.BytesToRead){ $buf+=$sp.ReadExisting() }; Start-Sleep -Milliseconds 100 }
        Write-Host ("GOT [" + $buf.Length + " chars]:") -ForegroundColor Cyan
        Write-Host $buf
        $sp.Close()
  }

  "read" {
        # Non-destructive read-out of current config.
        $sp = Open-E4
        Write-Host "--- E4 READ-OUT (no changes made) ---" -ForegroundColor Green
        Write-Host ("#01  (cmd mode)   -> " + (Send-Cmd $sp "#01"))
        Write-Host ("#505 (fw/model/SN)-> " + (Send-Cmd $sp "#505"))
        Write-Host ("#527 (RF status)  -> " + (Send-Cmd $sp "#527"))
        Write-Host ("#570 (protocols)  -> " + (Send-Cmd $sp "#570"))
        Write-Host ("#532 (wiegand?)   -> " + (Send-Cmd $sp "#532"))
        Write-Host ("#531 (wieg fmt)   -> " + (Send-Cmd $sp "#531"))
        Write-Host ("#533 (wieg intvl) -> " + (Send-Cmd $sp "#533"))
        Write-Host ("#00  (data mode)  -> " + (Send-Cmd $sp "#00"))
        $sp.Close()
  }

  "wiegand" {
        # Enable standard 26-bit Wiegand output and SAVE to NVM.
        # (Run 'read' first so you know the starting state.)
        $sp = Open-E4
        Write-Host "--- ENABLE WIEGAND (26-bit) ---" -ForegroundColor Magenta
        Write-Host ("#01  (cmd mode)        -> " + (Send-Cmd $sp "#01"))
        Write-Host ("#451 (wiegand ON)      -> " + (Send-Cmd $sp "#451"))
        Write-Host ("#871 (26-bit format)   -> " + (Send-Cmd $sp "#871"))
        Write-Host ("#6401(RF ON)           -> " + (Send-Cmd $sp "#6401"))
        Write-Host ("#00  (data mode+SAVE)  -> " + (Send-Cmd $sp "#00"))
        Write-Host "Re-reading to confirm..." -ForegroundColor Magenta
        Write-Host ("#01                    -> " + (Send-Cmd $sp "#01"))
        Write-Host ("#532 (wiegand?)        -> " + (Send-Cmd $sp "#532"))
        Write-Host ("#531 (wieg fmt)        -> " + (Send-Cmd $sp "#531"))
        Write-Host ("#570 (protocols)       -> " + (Send-Cmd $sp "#570"))
        Write-Host ("#00                    -> " + (Send-Cmd $sp "#00"))
        $sp.Close()
  }

  "power" {
        # Menu-driven RF power / read-range tuning.
        # TX power  = #644NN  attenuation 0-20 dB  (00 = max power)
        # ATA range = #643NN  00-1F hex            (1F = max range)
        # SeGo/eGo  = #645NN  00-1F hex            (1F = max range)
        # All changes are written to NVM by the closing #00 (data mode).
        $sp = Open-E4
        [void](Send-Cmd $sp "#01")   # command mode
        Write-Host "=== E4 RF POWER / RANGE TUNER ===" -ForegroundColor Green
        Write-Host "Current state:" -ForegroundColor Green
        Show-RF $sp

        $run = $true
        while($run){
            Write-Host ""
            Write-Host "------------------------------------------" -ForegroundColor DarkGray
            Write-Host " 1) Lower TX power    (set attenuation, 0-20 dB)"
            Write-Host " 2) Set ATA receive range      (0-31)"
            Write-Host " 3) Set SeGo/eGo receive range (0-31)"
            Write-Host " 4) Preset: SHORT range  (10 dB cut + ranges -> 15)"
            Write-Host " 5) Preset: MEDIUM range ( 5 dB cut + ranges -> 24)"
            Write-Host " 6) Preset: MAX range    ( 0 dB cut + ranges -> 31, factory)"
            Write-Host " 7) Re-read current RF status (#527)"
            Write-Host " 8) Restore FACTORY defaults (#66F, keeps frequency)"
            Write-Host " S) Save and exit"
            Write-Host " Q) Quit WITHOUT saving new changes"
            $c = (Read-Host "Choose").Trim().ToUpper()

            switch($c){
              "1" {
                    $db = Read-Host "  TX attenuation in dB (0 = max power, 20 = weakest)"
                    if($db -match '^\d+$' -and [int]$db -ge 0 -and [int]$db -le 20){
                        $cmd = "#644" + (To-Hex2 $db)
                        Write-Host ("  " + $cmd + " -> " + (Send-Cmd $sp $cmd).Trim()) -ForegroundColor Yellow
                        Show-RF $sp
                    } else { Write-Host "  Enter a whole number 0-20." -ForegroundColor Red }
              }
              "2" {
                    $r = Read-Host "  ATA receive range 0-31 (31 = max range)"
                    if($r -match '^\d+$' -and [int]$r -ge 0 -and [int]$r -le 31){
                        $cmd = "#643" + (To-Hex2 $r)
                        Write-Host ("  " + $cmd + " -> " + (Send-Cmd $sp $cmd).Trim()) -ForegroundColor Yellow
                        Show-RF $sp
                    } else { Write-Host "  Enter a whole number 0-31." -ForegroundColor Red }
              }
              "3" {
                    $g = Read-Host "  SeGo/eGo receive range 0-31 (31 = max range)"
                    if($g -match '^\d+$' -and [int]$g -ge 0 -and [int]$g -le 31){
                        $cmd = "#645" + (To-Hex2 $g)
                        Write-Host ("  " + $cmd + " -> " + (Send-Cmd $sp $cmd).Trim()) -ForegroundColor Yellow
                        Show-RF $sp
                    } else { Write-Host "  Enter a whole number 0-31." -ForegroundColor Red }
              }
              "4" {
                    Write-Host "  Applying SHORT-range preset..." -ForegroundColor Yellow
                    Write-Host ("  #6440A -> " + (Send-Cmd $sp ("#644" + (To-Hex2 10))).Trim())
                    Write-Host ("  #6430F -> " + (Send-Cmd $sp ("#643" + (To-Hex2 15))).Trim())
                    Write-Host ("  #6450F -> " + (Send-Cmd $sp ("#645" + (To-Hex2 15))).Trim())
                    Show-RF $sp
              }
              "5" {
                    Write-Host "  Applying MEDIUM-range preset..." -ForegroundColor Yellow
                    Write-Host ("  #64405 -> " + (Send-Cmd $sp ("#644" + (To-Hex2 5))).Trim())
                    Write-Host ("  #64318 -> " + (Send-Cmd $sp ("#643" + (To-Hex2 24))).Trim())
                    Write-Host ("  #64518 -> " + (Send-Cmd $sp ("#645" + (To-Hex2 24))).Trim())
                    Show-RF $sp
              }
              "6" {
                    Write-Host "  Applying MAX-range preset..." -ForegroundColor Yellow
                    Write-Host ("  #64400 -> " + (Send-Cmd $sp ("#644" + (To-Hex2 0))).Trim())
                    Write-Host ("  #6431F -> " + (Send-Cmd $sp ("#643" + (To-Hex2 31))).Trim())
                    Write-Host ("  #6451F -> " + (Send-Cmd $sp ("#645" + (To-Hex2 31))).Trim())
                    Show-RF $sp
              }
              "7" { Show-RF $sp }
              "8" {
                    $ok = Read-Host "  Restore FACTORY defaults? (y/N)"
                    if($ok.Trim().ToUpper() -eq "Y"){
                        Write-Host ("  #66F -> " + (Send-Cmd $sp "#66F").Trim()) -ForegroundColor Yellow
                        Show-RF $sp
                    } else { Write-Host "  Cancelled." }
              }
              "S" {
                    Write-Host ("Saving to NVM... #00 -> " + (Send-Cmd $sp "#00").Trim()) -ForegroundColor Green
                    Write-Host "Done. Settings persisted." -ForegroundColor Green
                    $run = $false
              }
              "Q" {
                    Write-Host "Leaving command mode without an explicit save (#00)." -ForegroundColor DarkYellow
                    Write-Host "Note: range/atten commands may already be live; power-cycle to be sure of NVM state." -ForegroundColor DarkYellow
                    [void](Send-Cmd $sp "#00")
                    $run = $false
              }
              default { Write-Host "  Unknown choice." -ForegroundColor Red }
            }
        }
        $sp.Close()
  }

  "send" {
        # Send one arbitrary command:  ... .ps1 send "#570"
        $sp = Open-E4
        Write-Host ($arg + " -> " + (Send-Cmd $sp $arg))
        $sp.Close()
  }

  default {
        Write-Host "Unknown mode '$mode'. Use: listen | read | wiegand | power | send `"#xxx`""
  }
}
