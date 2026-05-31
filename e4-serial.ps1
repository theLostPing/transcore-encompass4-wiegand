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
#     powershell -ExecutionPolicy Bypass -File .\e4-serial.ps1 listen
#     powershell -ExecutionPolicy Bypass -File .\e4-serial.ps1 read
#     powershell -ExecutionPolicy Bypass -File .\e4-serial.ps1 wiegand
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

switch ($mode) {

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

  "send" {
        # Send one arbitrary command:  ... .ps1 send "#570"
        $sp = Open-E4
        Write-Host ($arg + " -> " + (Send-Cmd $sp $arg))
        $sp.Close()
  }

  default {
        Write-Host "Unknown mode '$mode'. Use: listen | read | wiegand | send `"#xxx`""
  }
}
