#!/usr/bin/env bash

# Patch the Into the Breach binary to allow unlimited turn resets

if [ -z "${1}" ]; then
    echo 'Error: please provide path to the Into the Breach binary to patch'
    echo "Usage: $0 BINARY_PATH"
    exit 1
fi

echo "Patching ..."

bin_path="${1}"

# TODO: file offset of function is 4969424
#       offset of JLE is 4971905, so 2481 bytes later

# Get the name of the function we need to patch
renderendturn_function_name=$(nm "${bin_path}" | grep RenderEndTurn | awk '{print $3}')

# Get the virtual address we need to patch
# TODO: make this idempotent, after we figure out if we need to patch the second JLE
virtual_address=$(objdump -d --disassemble=${renderendturn_function_name} "${bin_path}" | grep -B 2 jle | grep -A 2 mov | grep jle | head -n 1 | awk '{print $1}' | cut -d : -f 1)

if [[ -z "$virtual_address" ]]; then
    echo "Unable to find address to patch; has the file already been patched?"
    exit 1
fi

# Get the file offset corresponding to the virtual address of the search string
text_file_offset=$(objdump -h "${bin_path}" | grep .text | awk '{ print $6 }')
text_virtual_offset=$(objdump -h "${bin_path}" | grep .text | awk '{ print $4 }')

file_offset=$((0x$virtual_address + 0x$text_file_offset - 0x$text_virtual_offset))

bytes=$(xxd -p -l 6 --seek "${file_offset}" "${bin_path}" | tr -d '\n')

# Make sure bytes match what we expect
if [[ "${bytes}" != 0f8e* ]]; then
    echo "Unexpected bytes at offset ${file_offset}: ${bytes}"
    echo "This shouldn't happen; please check the binary file."
    exit 1
fi

# Apply the patch to the extracted bytes; replace the JLE instruction with NOPs
patched_bytes='909090909090'

# Write the patched bytes back to the binary file
echo "${patched_bytes}" | xxd -p -r | dd of="${bin_path}" bs=1 conv=notrunc seek="${file_offset}"
