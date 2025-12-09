import { RNPackageContext, RNPackage } from '@rnoh/react-native-openharmony/ts';
import {SafeAreaViewPackage} from '@react-native-oh-tpl/react-native-safe-area-context/ts';
import {AsyncStoragePackage} from '@react-native-ohos/async-storage/ts';
import { WebViewPackage } from '@react-native-ohos/react-native-webview/ts';
import {CookiesPackage} from '@react-native-ohos/cookies/ts';
import GestureHandlerPackage from '@react-native-ohos/react-native-gesture-handler';
import {BlobUtilPackage} from '@react-native-ohos/react-native-blob-util/ts';
import { FsPackage } from '@react-native-ohos/react-native-fs/ts';

export function createRNPackages(ctx: RNPackageContext): RNPackage[] {
  return [
    new SafeAreaViewPackage(ctx),
    new AsyncStoragePackage(ctx),
    new WebViewPackage(ctx),
    new CookiesPackage(ctx),
    new GestureHandlerPackage(ctx),
    new BlobUtilPackage(ctx),
    new FsPackage(ctx),
  ];
}