import {
  AnyJSBundleProvider,
  ComponentBuilderContext,
  FileJSBundleProvider,
  MetroJSBundleProvider,
  ResourceJSBundleProvider,
  RNApp,
  RNOHErrorDialog,
  RNOHLogger,
  TraceJSBundleProviderDecorator,
  RNOHCoreContext
} from '@rnoh/react-native-openharmony';
import { createRNPackages } from '../RNPackagesFactory';
import { WebView, WEB_VIEW } from "@react-native-ohos/react-native-webview";
import { RTNPdfView, PDF_VIEW_TYPE } from '@react-native-ohos/react-native-pdf';

@Builder
export function buildCustomRNComponent(ctx: ComponentBuilderContext) {
  if (ctx.componentName === WEB_VIEW) {
    WebView({
      ctx: ctx.rnComponentContext,
      tag: ctx.tag
    })
  } else if (ctx.componentName === PDF_VIEW_TYPE) {
    RTNPdfView({
      ctx: ctx.rnComponentContext,
      tag: ctx.tag,
    })
  }
}

const wrappedCustomRNComponentBuilder = wrapBuilder(buildCustomRNComponent)

@Entry
@Component
struct Index {
  @StorageLink('RNOHCoreContext') private rnohCoreContext: RNOHCoreContext | undefined = undefined
  @State shouldShow: boolean = false
  private logger!: RNOHLogger

  aboutToAppear() {
    this.logger = this.rnohCoreContext!.logger.clone("Index")
    const stopTracing = this.logger.clone("aboutToAppear").startTracing();

    this.shouldShow = true
    stopTracing();
  }

  onBackPress(): boolean | undefined {
    // NOTE: this is required since `Ability`'s `onBackPressed` function always
    // terminates or puts the app in the background, but we want Ark to ignore it completely
    // when handled by RN
    this.rnohCoreContext!.dispatchBackPress()
    return true
  }

  build() {
    Column() {
      if (this.rnohCoreContext && this.shouldShow) {
        if (this.rnohCoreContext?.isDebugModeEnabled) {
          RNOHErrorDialog({ ctx: this.rnohCoreContext })
        }
        RNApp({
          rnInstanceConfig: {
            createRNPackages,
            enableNDKTextMeasuring: true, // 该项必须为true，用于开启NDK文本测算
            enableBackgroundExecutor: false,
            enableCAPIArchitecture: true, // 该项必须为true，用于开启CAPI
            arkTsComponentNames: [
              WEB_VIEW,
              PDF_VIEW_TYPE
            ],
            fontResourceByFontFamily: {
              'anticon': $rawfile('fonts/AntDesign.ttf'),
              'Entypo': $rawfile('fonts/Entypo.ttf'),
              'EvilIcons': $rawfile('fonts/EvilIcons.ttf'),
              'Feather': $rawfile('fonts/Feather.ttf'),
              'FontAwesome': $rawfile('fonts/FontAwesome.ttf'),
              'FontAwesome5Brands-Regular': $rawfile('fonts/FontAwesome5_Brands.ttf'),
              'FontAwesome5Free-Regular': $rawfile('fonts/FontAwesome5_Regular.ttf'),
              'FontAwesome5Free-Solid': $rawfile('fonts/FontAwesome5_Solid.ttf'),
              'FontAwesome6Brands-Regular': $rawfile('fonts/FontAwesome6_Brands.ttf'),
              'FontAwesome6Free-Regular': $rawfile('fonts/FontAwesome6_Regular.ttf'),
              'FontAwesome6Free-Solid': $rawfile('fonts/FontAwesome6_Solid.ttf'),
              'Fontisto': $rawfile('fonts/Fontisto.ttf'),
              'fontcustom': $rawfile('fonts/Foundation.ttf'),
              'Ionicons': $rawfile('fonts/Ionicons.ttf'),
              'Material Design Icons': $rawfile('fonts/MaterialCommunityIcons.ttf'),
              'Material Icons': $rawfile('fonts/MaterialIcons.ttf'),
              'Octicons': $rawfile('fonts/Octicons.ttf'),
              'simple-line-icons': $rawfile('fonts/SimpleLineIcons.ttf'),
              'zocial': $rawfile('fonts/Zocial.ttf'),
            }
          },
          initialProps: { "foo": "bar" } as Record<string, string>,
          appKey: "learnX",
          wrappedCustomRNComponentBuilder: wrappedCustomRNComponentBuilder,
          onSetUp: (rnInstance) => {
            rnInstance.enableFeatureFlag("ENABLE_RN_INSTANCE_CLEAN_UP")
          },
          jsBundleProvider: new TraceJSBundleProviderDecorator(
            new AnyJSBundleProvider([
              new MetroJSBundleProvider(),
              // NOTE: to load the bundle from file, place it in
              // `/data/app/el2/100/base/com.rnoh.tester/files/bundle.harmony.js`
              // on your device. The path mismatch is due to app sandboxing on OpenHarmony
              new FileJSBundleProvider('/data/storage/el2/base/files/bundle.harmony.js'),
              new ResourceJSBundleProvider(this.rnohCoreContext.uiAbilityContext.resourceManager, 'hermes_bundle.hbc'),
              new ResourceJSBundleProvider(this.rnohCoreContext.uiAbilityContext.resourceManager, 'bundle.harmony.js')
            ]),
            this.rnohCoreContext.logger),
        })
      }
    }
    .height('100%')
    .width('100%')
  }
}