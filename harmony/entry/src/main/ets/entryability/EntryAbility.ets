import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, display } from '@kit.ArkUI';
import { RNAbility } from '@rnoh/react-native-openharmony';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0x0000;

export default class EntryAbility extends RNAbility {
  private immersive: boolean | undefined = undefined;

  getPagePath() {
    return 'pages/Index';
  }

  override onCreate(want: Want): void {
    super.onCreate(want);
    hilog.info(0x0000, 'testTag', '%{public}s', 'EntryAbility onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }


  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');


    windowStage.getMainWindow((err: BusinessError, windowClass) => {
      if (err.code) {
        console.error(`Failed to obtain the main window. Cause code: ${err.code}, message: ${err.message}`);
        return;
      }

      display.on('change', () => {
        this.handleOrientationChange(windowClass);
      });
      // 初始检测一次
      this.handleOrientationChange(windowClass);
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  handleOrientationChange(windowClass: window.Window) {
    try {
      let defaultDisplay = display.getDefaultDisplaySync();
      let orientation = defaultDisplay.orientation;
      let landscape = display.Orientation.LANDSCAPE;
      let landscapeInverted = display.Orientation.LANDSCAPE_INVERTED;
      let immersive = orientation == landscape || orientation == landscapeInverted;

      if (immersive == this.immersive) {
        return;
      }
      this.immersive = immersive;

      windowClass.setWindowLayoutFullScreen(immersive).catch((err: BusinessError) => {
        console.error(`Failed to set full screen. Cause code: ${err.code}, message: ${err.message}`);
      });

      windowClass.setSpecificSystemBarEnabled('status', !immersive).catch((err: BusinessError) => {
        console.error(`Failed to set the system bar to be invisible. Cause code: ${err.code}, message: ${err.message}`);
      });
    } catch (err) {
      console.error(`Failed to handle orientation change. Cause code: ${err.code}, message: ${err.message}`);
    }
  }

  onWindowStageDestroy():
    void {
    // Main window is destroyed, release UI related resources
    hilog
      .info
      (
        DOMAIN,
        'testTag',
        '%{public}s',
        'Ability onWindowStageDestroy'
      )
    ;
    display
      .off
      (
        'change'
      )
    ;
  }

  onForeground():
    void {
    // Ability has brought to foreground
    hilog
      .info
      (
        DOMAIN,
        'testTag',
        '%{public}s',
        'Ability onForeground'
      )
    ;
  }

  onBackground():
    void {
    // Ability has back to background
    hilog
      .info
      (
        DOMAIN,
        'testTag',
        '%{public}s',
        'Ability onBackground'
      )
    ;
  }
}