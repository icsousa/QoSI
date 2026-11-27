#!/bin/bash
# Arranca a VM NS-2 do professor (x86) no Mac ARM via QEMU (comando do anuncio do curso).
# Uso: ./arrancar_vm_prof.sh [caminho/para/Ubuntu-NS2.vdi]   (por omissao procura em ~/Downloads)
VDI=${1:-$HOME/Downloads/Ubuntu-NS2.vdi}
[ -f "$VDI" ] || { echo "Nao encontrei $VDI - descarrega-o de https://shorturl.at/y1cZk"; exit 1; }
exec qemu-system-x86_64 \
  -m 4096 -smp 4 -cpu max \
  -drive file="$VDI",format=vdi \
  -device virtio-vga,xres=1920,yres=1080 \
  -nic user,model=virtio-net-pci \
  -usb -device usb-tablet \
  -display cocoa,zoom-to-fit=on,show-cursor=on
