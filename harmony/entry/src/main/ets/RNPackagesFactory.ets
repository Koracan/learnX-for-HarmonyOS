import { RNPackageContext, RNPackage } from '@rnoh/react-native-openharmony/ts';
import {SafeAreaViewPackage} from '@react-native-oh-tpl/react-native-safe-area-context/ts';
import {AsyncStoragePackage} from '@react-native-ohos/async-storage/ts';
import { WebViewPackage } from '@react-native-ohos/react-native-webview/ts';
import {CookiesPackage} from '@react-native-ohos/cookies/ts';

export function createRNPackages(ctx: RNPackageContext): RNPackage[] {
  return [
    new SafeAreaViewPackage(ctx),
    new AsyncStoragePackage(ctx),
    new WebViewPackage(ctx),
    new CookiesPackage(ctx),
  ];
}