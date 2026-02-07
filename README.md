# Android ROM Importer for Termux

Watches your Downloads folder for new ZIP files, extracts them, then moves ROMs
into the correct system folder based on `systeminfo.txt` extension lists.

## Requirements

- Android device
- Termux (from F-Droid)
- Termux:Boot (optional, for auto-start on boot)

## Install (Termux)

1) Allow storage access:
```
termux-setup-storage
```

2) Install tools:
```
pkg update
pkg install unzip inotify-tools
```

Optional, faster extraction:
```
pkg install p7zip
```

## Setup (script starts in Downloads)

Assuming `rom_importer.sh` is in `/storage/emulated/0/Download`:
```
mkdir -p ~/scripts
mv /storage/emulated/0/Download/rom_importer.sh ~/scripts/
chmod +x ~/scripts/rom_importer.sh
```

## Run

```
~/scripts/rom_importer.sh start
```

Check status or stop:
```
~/scripts/rom_importer.sh status
~/scripts/rom_importer.sh stop
```

Logs:
```
tail -n 50 ~/.rom_importer.log
```

## Auto-start on boot (Termux:Boot)

1) Install and open Termux:Boot once.
2) Create the boot script:
```
mkdir -p ~/.termux/boot
cat > ~/.termux/boot/rom_importer.sh <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
nohup /data/data/com.termux/files/home/scripts/rom_importer.sh start >/dev/null 2>&1 &
EOF
chmod +x ~/.termux/boot/rom_importer.sh
```

## Notes

- Downloads folder: `/storage/emulated/0/Download`
- ROMs folder: `/storage/emulated/0/ROMs`
- Each system folder in ROMs should have `systeminfo.txt` with a
  "Supported file extensions:" line and a list on the next line.
