#!/usr/bin/env bash

npm install
# Bundle; this is necesssary for ESM support (https://github.com/vercel/pkg/issues/1291#issuecomment-1295792641)
node_modules/.bin/esbuild src/patcher.ts --bundle --platform=node --target=node12 --outfile=src/patcher.js
if [[ ! -f ~/.nexe/windows-x86-10.16.3 ]]; then
    # Build the package once to fetch Node
    node_modules/.bin/nexe src/patcher.js -o patchbreach -t windows-x86-10.16.3
    # Compress the Node executable
    upx --lzma ~/.nexe/windows-x86-10.16.3
fi
# Build the package with the compressed version of Node
node_modules/.bin/nexe src/patcher.js -o patchbreach -t windows-x86-10.16.3