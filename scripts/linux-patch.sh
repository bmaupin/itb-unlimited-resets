#!/usr/bin/env bash

# Patch the Into the Breach binary to allow unlimited turn resets

if [ -z "${1}" ]; then
    echo 'Error: please provide path to the Into the Breach binary to patch'
    echo "Usage: $0 BINARY_PATH"
    exit 1
fi

bin_path="${1}"

# Get the name of the BoardPlayer::UndoTurnUsed function
undoturnused_function_name=$(nm "${bin_path}" | grep BoardPlayer.*UndoTurnUsed | awk '{print $3}')

# Get the virtual address we need to patch
virtual_address=$(objdump -d --disassemble=${undoturnused_function_name} "${bin_path}" | grep '83 af 1c 45 00 00 01' | awk '{print $1}' | cut -d : -f 1)

if [[ -z "$virtual_address" ]]; then
    echo "Unable to find address to patch; has the file already been patched?"
    exit 1
fi

# Get the file offset corresponding to the virtual address of the search string
text_file_offset=$(objdump -h "${bin_path}" | grep .text | awk '{ print $6 }')
text_virtual_offset=$(objdump -h "${bin_path}" | grep .text | awk '{ print $4 }')

file_offset=$((0x$virtual_address + 0x$text_file_offset - 0x$text_virtual_offset))

bytes=$(xxd -p -l 7 --seek "${file_offset}" "${bin_path}" | tr -d '\n')

# Make sure bytes match what we expect
if [[ "${bytes}" != "83af1c45000001" ]]; then
    echo "Unexpected bytes at offset ${file_offset}: ${bytes}"
    echo "This shouldn't happen; please check the binary file."
    exit 1
fi

# Subtract 0 instead of 1 so that the number of turn resets never decreases
patched_bytes='83af1c45000000'

echo "Enabling unlimited turn resets"
echo "    Patching bytes at offset ${file_offset} from ${bytes} to ${patched_bytes}"
echo

# Write the patched bytes back to the binary file
echo "${patched_bytes}" | xxd -p -r | dd of="${bin_path}" bs=1 conv=notrunc seek="${file_offset}"

# Get the mangled name of the BoardPlayer::UndoTurn function
undoturn_function_name=$(nm "${bin_path}" | grep BoardPlayer.*UndoTurn | egrep -v "IsUndoTurnPossible|UndoTurnUsed" | awk '{print $3}')

# Get the virtual addresses we need for the next patches
undoturn_flag_virtual_address=$(objdump -d --disassemble=${undoturn_function_name} "${bin_path}" | grep 0x4518 | awk '{print $1}' | cut -d : -f 1)
undoturn_jump_virtual_address=$(objdump -d --disassemble=${undoturn_function_name} "${bin_path}" | grep 0x4518 -A 2 | tail -n 1 | awk '{print $1}' | cut -d : -f 1)
undoturn_return_virtual_address=$(objdump -d --disassemble=${undoturn_function_name} "${bin_path}" | grep ret -B 2 | grep add | awk '{print $1}' | cut -d : -f 1)

if [[ -z "$undoturn_flag_virtual_address" ]]; then
    echo "Unable to find address to patch; has the file already been patched?"
    exit 1
fi

undoturn_flag_file_offset=$((0x$undoturn_flag_virtual_address + 0x$text_file_offset - 0x$text_virtual_offset))

undoturn_flag_bytes=$(xxd -p -l 10 --seek "${undoturn_flag_file_offset}" "${bin_path}" | tr -d '\n')
if [[ "${undoturn_flag_bytes}" != "c7831845000001000000" ]]; then
    echo "Unexpected bytes at offset ${undoturn_flag_file_offset}: ${undoturn_flag_bytes}"
    echo "This shouldn't happen; please check the binary file."
    exit 1
fi

# Instead of setting the flag at 0x4518, set the flag at 0x4520 to bypass checking the result of the confirmation dialogue
undoturn_flag_patched_bytes='c7832045000001000000'

echo
echo "Bypassing confirmation dialogue response check"
echo "    Patching bytes at offset ${undoturn_flag_file_offset} from ${undoturn_flag_bytes} to ${undoturn_flag_patched_bytes}"
echo

echo "${undoturn_flag_patched_bytes}" | xxd -p -r | dd of="${bin_path}" bs=1 conv=notrunc seek="${undoturn_flag_file_offset}"

# Check that neither of the addresses are empty
if [[ -z "$undoturn_jump_virtual_address" || -z "$undoturn_return_virtual_address" ]]; then
    echo "Unable to find address to patch; has the file already been patched?"
    exit 1
fi

undoturn_jump_file_offset=$((0x$undoturn_jump_virtual_address + 0x$text_file_offset - 0x$text_virtual_offset))
undoturn_jump_bytes=$(xxd -p -l 5 --seek "${undoturn_jump_file_offset}" "${bin_path}" | tr -d '\n')
# TODO: If the binary ever changes, this will break; maybe we shouldn't validate these?
if [[ "${undoturn_jump_bytes}" != "bebe27a900" ]]; then
    echo "Unexpected bytes at offset ${undoturn_jump_file_offset}: ${undoturn_jump_bytes}"
    echo "This shouldn't happen; please check the binary file."
    exit 1
fi

# Calculate the offset to use for the jump; 5 is the length of the instruction where we will be placing the jump
jump_offset=$((0x$undoturn_return_virtual_address - (0x$undoturn_jump_virtual_address + 5)))

# If the jump offset is negative, we need to add 0x100000000 to it
if [[ $jump_offset -lt 0 ]]; then
    jump_offset=$(printf "%x\n" $((0x100000000 + $jump_offset)))
fi

# Convert the jump offset to little endian
le_jump_offset=$(echo "${jump_offset}" | tac -rs .. | echo "$(tr -d '\n')")

# Set a jump to return early and bypass the confirmation dialogue altogether
undoturn_jump_patched_bytes="e9${le_jump_offset}"

echo
echo "Don't show the confirmation dialogue to prevent it from flashing"
echo "    Patching bytes at offset ${undoturn_jump_file_offset} from ${undoturn_jump_bytes} to ${undoturn_jump_patched_bytes}"
echo

echo "${undoturn_jump_patched_bytes}" | xxd -p -r | dd of="${bin_path}" bs=1 conv=notrunc seek="${undoturn_jump_file_offset}"
