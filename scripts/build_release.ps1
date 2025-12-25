node -e "const fs=require('fs');const pkg=require('./package.json');const p='harmony/AppScope/app.json5';const app=JSON.parse(fs.readFileSync(p));app.app.versionName=pkg.version;app.app.versionCode=(app.app.versionCode||0)+1;fs.writeFileSync(p, JSON.stringify(app,null,2)+'\n');"
npm run codegen
react-native bundle-harmony --dev=false --minify=true --bundle-output ./tmp/bundle.harmony.js
./node_modules/react-native/sdks/hermesc/win64-bin/hermesc --emit-binary ./tmp/bundle.harmony.js -out ./harmony/entry/src/main/resources/rawfile/hermes_bundle.hbc 2>./tmp/hermes_build.log