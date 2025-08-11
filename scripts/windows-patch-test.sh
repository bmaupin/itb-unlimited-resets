#!/usr/bin/env bash

bin_path="$1"

# Patch 1: NOP DEC EDX at 0x00589aa1
file_offset=$((0x188ea1))
bytes=$(xxd -p -l 1 --seek ${file_offset} "${bin_path}" | tr -d '\n')
if [[ "${bytes}" != "4a" ]]; then
    echo "Unexpected bytes at offset ${file_offset}: ${bytes}"
    exit 1
fi
echo "90" | xxd -p -r | dd of="$bin_path" bs=1 seek="${file_offset}" conv=notrunc

# Patch 2: NOP 0x00591139 to 0x00591140
# We need to skip the two pushes to the stack, otherwise the stack pointer will be off
file_offset=$((0x190539))
bytes=$(xxd -p -l 7 --seek ${file_offset} "${bin_path}" | tr -d '\n')
if [[ "${bytes}" != "6a0a68dcfd8200" ]]; then
    echo "Unexpected bytes at offset ${file_offset}: ${bytes}"
    exit 1
fi
echo "90 90 90 90 90 90 90" | xxd -p -r | dd of="$bin_path" bs=1 seek="${file_offset}" conv=notrunc

# Patch 3: Change 0x4558 to 0x4560 at 0x00591143
file_offset=$((0x190543))
bytes=$(xxd -p -l 10 --seek ${file_offset} "${bin_path}" | tr -d '\n')
if [[ "${bytes}" != "c7865845000001000000" ]]; then
    echo "Unexpected bytes at offset ${file_offset}: ${bytes}"
    exit 1
fi
echo "c7 86 60 45 00 00 01 00 00 00" | xxd -p -r | dd of="$bin_path" bs=1 seek="${file_offset}" conv=notrunc

# Patch 4: JMP 0x005911F4 at 0x0059114D
file_offset=$((0x19054d))
bytes=$(xxd -p -l 7 --seek ${file_offset} "${bin_path}" | tr -d '\n')
if [[ "${bytes}" != "c745ec0f000000" ]]; then
    echo "Unexpected bytes at offset ${file_offset}: ${bytes}"
    exit 1
fi
echo "e9 a2 00 00 00 90 90" | xxd -p -r | dd of="$bin_path" bs=1 seek="${file_offset}" conv=notrunc

echo "Patching complete."