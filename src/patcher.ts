import { promises as fs } from 'fs';
import * as PE from 'pe-library';

// Disable warnings in order to suppress "ExperimentalWarning: The fs.promises API is experimental"
process.removeAllListeners('warning');

// Disable this to hide debugging messages
const debug = false;
if (!debug) {
  console.debug = () => {};
}

const main = async () => {
  const fileToPatch = getArguments();
  const fileData = await fs.readFile(fileToPatch);

  if (isWindowsBinary(fileData)) {
    console.log('Detected Windows binary format');
    patchWindowsFileData(fileData);
  } else if (isLinuxBinary(fileData)) {
    console.log('Detected Linux binary format');
    throw new Error('This functionality has not yet been implemented');
  }

  if (!debug) {
    await fs.writeFile(fileToPatch, fileData);
  }
};

const getArguments = () => {
  if (process.argv.length !== 3) {
    console.error('Error: Please provide the path to the file to patch');
    process.exit(1);
  }

  const fileToPatch = process.argv[2];
  return fileToPatch;
};

const isLinuxBinary = (fileData: Buffer): boolean => {
  // Check for the ELF magic number at the start of the file
  return (
    fileData.length > 4 &&
    fileData[0] === 0x7f &&
    fileData[1] === 0x45 &&
    fileData[2] === 0x4c &&
    fileData[3] === 0x46
  );
};

const isWindowsBinary = (fileData: Buffer): boolean => {
  // Check for the PE magic number at the start of the file
  return fileData.length > 2 && fileData[0] === 0x4d && fileData[1] === 0x5a;
};

const patchWindowsFileData = (fileData: Buffer) => {
  giveUnlimitedTurnResets(fileData);
  disableConfirmationPopup(fileData);
};

const giveUnlimitedTurnResets = (fileData: Buffer) => {
  console.log('Enabling unlimited turn resets');
  // Replace DEC with NOP to ensure the reset turn counter never goes down
  //  589a98:       8b 91 5c 45 00 00       mov    0x455c(%ecx),%edx
  //  589a9e:       8d 45 f0                lea    -0x10(%ebp),%eax
  //  589aa1:       4a                      dec    %edx
  const searchBytes = Buffer.from([
    0x8b, 0x91, 0x5c, 0x45, 0x00, 0x00, 0x8d, 0x45, 0xf0, 0x4a,
  ]);
  const offset = findBytes(fileData, searchBytes);
  patchOffset(
    fileData,
    offset,
    Buffer.from([0x8b, 0x91, 0x5c, 0x45, 0x00, 0x00, 0x8d, 0x45, 0xf0, 0x90])
  );
};

const findBytes = (fileData: Buffer, searchBytes: Buffer): number => {
  // Find the offset of the search bytes in the file data
  const offset = fileData.indexOf(searchBytes);
  if (offset === -1) {
    console.error('Bytes not found in file:', searchBytes);
    throw new Error(
      'Unable to find address to patch; has the file already been patched?'
    );
  }
  return offset;
};

const patchOffset = (fileData: Buffer, offset: number, patchBytes: Buffer) => {
  // Check if the offset is within the bounds of the file data
  if (offset < 0 || offset + patchBytes.length > fileData.length) {
    throw new Error('Offset is out of bounds for the file data');
  }

  const originalBytes = fileData.slice(offset, offset + patchBytes.length);
  console.log(
    `Patching bytes at offset ${offset} from ${originalBytes.toString(
      'hex'
    )} to ${patchBytes.toString('hex')}`
  );

  // Replace the bytes at the specified offset with the patch bytes
  fileData.fill(patchBytes, offset, offset + patchBytes.length);
};

const disableConfirmationPopup = (fileData: Buffer) => {
  const undoTurnOffset = findUndoTurnOffset(fileData);
  const flagOffset = dontBlockOnConfirmation(fileData, undoTurnOffset);
  dontShowConfirmationPopup(fileData, undoTurnOffset, flagOffset);
};

const findUndoTurnOffset = (fileData: Buffer) => {
  const stringFileOffset = fileData.indexOf('Reset_TurnFinal');
  console.debug(`Found string 'Reset_Turn' at offset: ${stringFileOffset}`);

  const stringMemoryAddress = fileOffsetToVirtualAddress(
    fileData,
    stringFileOffset
  );
  console.debug(
    `String 'Reset_TurnFinal' memory address: 0x${stringMemoryAddress.toString(
      16
    )}`
  );

  const memoryAddressBuffer = toLittleEndianBytes(stringMemoryAddress);

  // Find the first instance in the file where the memory address is referenced
  const firstUsageAddress = fileData.indexOf(memoryAddressBuffer);

  console.debug(
    `First usage of 'Reset_TurnFinal' memory address found at: 0x${firstUsageAddress.toString(
      16
    )}`
  );

  // Starting from firstUsageAddress, search backwards for the start of the function:
  //  591100:       55                      push   %ebp
  //  591101:       8b ec                   mov    %esp,%ebp
  //  591103:       6a ff                   push   $0xffffffff
  const functionStartBytes = Buffer.from([0x55, 0x8b, 0xec, 0x6a, 0xff]);
  let undoTurnOffset = -1;

  for (let i = firstUsageAddress; i >= 0; i--) {
    if (
      fileData
        .slice(i, i + functionStartBytes.length)
        .equals(functionStartBytes)
    ) {
      undoTurnOffset = i;
      console.debug('undoTurnOffset=', undoTurnOffset);
      break;
    }
  }

  if (undoTurnOffset === -1) {
    console.error(
      'Unable to find the start of the function that uses the Reset_TurnFinal address'
    );
    process.exit(1);
  }

  return undoTurnOffset;

  // // Starting from that address, find the offset of the bytes to patch
  // const searchBuffer = new Uint8Array([0x85, 0xc0, 0x74]);
  // const searchOffset = fileData.indexOf(searchBuffer, firstUsageAddress);

  // if (searchOffset === -1 || searchOffset - firstUsageAddress > 512) {
  //   console.log('Unable to apply patch; has the file already been patched?');
  //   process.exit();
  // }
};

const fileOffsetToVirtualAddress = (fileData: Buffer, fileOffset: number) => {
  const exe = PE.NtExecutable.from(fileData, { ignoreCert: true });
  const rdataInfo = exe
    .getAllSections()
    .filter((section) => section.info.name === '.rdata')[0].info;
  const rdataFileOffset = rdataInfo.pointerToRawData;
  const rdataMemoryAddress = rdataInfo.virtualAddress + exe.getImageBase();
  const virtualAddress = fileOffset - rdataFileOffset + rdataMemoryAddress;

  return virtualAddress;
};

const dontBlockOnConfirmation = (fileData: Buffer, undoTurnOffset: number) => {
  console.log('Bypassing confirmation dialogue response check');
  // Set the flag at 0x4560 instead of 0x4558 to skip waiting for the confirmation dialogue response
  //  591143:       c7 86 58 45 00 00 01    movl   $0x1,0x4558(%esi)
  //  59114a:       00 00 00
  const searchBytes = Buffer.from([
    0xc7, 0x86, 0x58, 0x45, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
  ]);
  const flagOffset =
    findBytes(fileData.slice(undoTurnOffset), searchBytes) + undoTurnOffset;
  console.debug('flagOffset=', flagOffset);

  patchOffset(
    fileData,
    flagOffset,
    Buffer.from([0xc7, 0x86, 0x60, 0x45, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00])
  );

  return flagOffset;
};

const dontShowConfirmationPopup = (
  fileData: Buffer,
  undoTurnOffset: number,
  flagOffset: number
) => {
  console.log(
    "Don't show the confirmation dialogue to prevent it from flashing"
  );
  clearUndoTurnPushInstructions(fileData, flagOffset);
  skipConfirmationPopupCreation(fileData, flagOffset);
};

const clearUndoTurnPushInstructions = (
  fileData: Buffer,
  flagOffset: number
) => {
  // Start from undoTurnOffset + flagOffset, subtract 3 bytes and make sure that's an LEA instruction (0x8d)
  const leaOffset = flagOffset - 3;
  const leaInstruction = fileData[leaOffset];

  if (leaInstruction !== 0x8d) {
    console.error(
      `Expected LEA instruction at offset 0x${leaOffset.toString(
        16
      )}, but found 0x${leaInstruction.toString(16)}`
    );
    process.exit(1);
  }

  // The instruction right before that should be a PUSH (0x68)
  const pushInstruction = fileData[leaOffset - 5];

  if (pushInstruction !== 0x68) {
    console.error(
      `Expected PUSH instruction at offset 0x${(leaOffset - 1).toString(
        16
      )}, but found 0x${pushInstruction.toString(16)}`
    );
    process.exit(1);
  }

  // The instruction right before that should be another PUSH (0x6a)
  const secondPushInstruction = fileData[leaOffset - 7];
  if (secondPushInstruction !== 0x6a) {
    console.error(
      `Expected second PUSH instruction at offset 0x${(leaOffset - 2).toString(
        16
      )}, but found 0x${secondPushInstruction.toString(16)}`
    );
    process.exit(1);
  }

  // NOP out both push instructions to ensure the stack pointer is not altered
  const nopBytes = Buffer.from([0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90]);
  patchOffset(fileData, leaOffset - 7, nopBytes);
};

const skipConfirmationPopupCreation = (
  fileData: Buffer,
  flagOffset: number
) => {
  // Find the offset to jump to
  // 5911f4:       8b 4d f4                mov    -0xc(%ebp),%ecx
  const returnBytes = Buffer.from([0x8b, 0x4d, 0xf4]);
  const flagInstructionLength = 10;
  const jumpOffset = flagOffset + flagInstructionLength;
  const jumpInstructionLength = 5;
  const returnRelativeOffset = findBytes(
    fileData.slice(jumpOffset + jumpInstructionLength),
    returnBytes
  );
  console.debug('returnRelativeOffset=', returnRelativeOffset);

  // Patch the JMP instruction to skip the confirmation dialogue
  //  59114d:       e9 a2 00 00 00          jmp    0x5911f4
  const jumpPatchBytes = Buffer.from([
    0xe9, // JUMP
    ...toLittleEndianBytes(returnRelativeOffset),
    // We're writing a 5-byte instruction over a 7-byte instruction, so NOP the final bytes
    0x90,
    0x90,
  ]);
  console.debug('jumpPatchBytes=', jumpPatchBytes);
  patchOffset(fileData, jumpOffset, jumpPatchBytes);
};

const toLittleEndianBytes = (num: number): Buffer => {
  const buf = Buffer.alloc(4);
  buf.writeUInt32LE(num);
  return buf;
};

main();
