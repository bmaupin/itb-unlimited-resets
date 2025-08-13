#!/usr/bin/env bash

npm install

# Bundle; this is necesssary for ESM support (https://github.com/vercel/pkg/issues/1291#issuecomment-1295792641)
node_modules/.bin/esbuild src/patcher.ts --bundle --platform=node --target=node12 --outfile=src/patcher.js --alias:fs/promises=./src/fs-promises-shim.js

# Build the Linux binary
if [[ ! -f ~/.nexe/linux-x86-10.16.3 ]]; then
    # Build the package once to fetch Node
    node_modules/.bin/nexe src/patcher.js -o patchbreach -t linux-x86-10.16.3
    # upx won't compress a linux binary if it's not marked as executable
    chmod +x ~/.nexe/linux-x86-10.16.3
    # Compress the Node executable
    upx --lzma ~/.nexe/linux-x86-10.16.3
fi
# Build the package with the compressed version of Node
node_modules/.bin/nexe src/patcher.js -o patchbreach -t linux-x86-10.16.3

# Now build the Windows binary
if [[ ! -f ~/.nexe/windows-x86-10.16.3 ]]; then
    node_modules/.bin/nexe src/patcher.js -o patchbreach -t windows-x86-10.16.3
    upx --lzma ~/.nexe/windows-x86-10.16.3
fi
node_modules/.bin/nexe src/patcher.js -o patchbreach -t windows-x86-10.16.3
