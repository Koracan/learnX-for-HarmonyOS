npm run codegen
react-native bundle-harmony --dev=false --minify=true --bundle-output ./tmp/bundle.harmony.js
./node_modules/react-native/sdks/hermesc/win64-bin/hermesc --emit-binary ./tmp/bundle.harmony.js -out ./harmony/entry/src/main/resources/rawfile/hermes_bundle.hbc