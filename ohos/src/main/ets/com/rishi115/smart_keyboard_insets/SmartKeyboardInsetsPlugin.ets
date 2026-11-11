import UIAbility from '@ohos.app.ability.UIAbility';
import display from '@ohos.display';
import window from '@ohos.window';
import {
  AbilityAware,
  AbilityPluginBinding,
  Any,
  EventChannel,
  EventSink,
  FlutterManager,
  FlutterPlugin,
  FlutterPluginBinding,
  Log,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  StreamHandler,
} from '@ohos/flutter_ohos';

const TAG: string = 'SmartKeyboardInsetsPlugin';
const METHOD_CHANNEL_NAME: string = 'smart_keyboard_insets/method';
const EVENT_CHANNEL_NAME: string = 'smart_keyboard_insets/event';

/**
 * OpenHarmony implementation of the keyboard metrics detection.
 *
 * The keyboard height comes from the window keyboard avoid area, which is reported in physical
 * pixels and updated while the input method animates. The bottom safe area comes from the
 * navigation indicator avoid area. Both are divided by the display density so the Dart side
 * receives logical pixels, like on Android and iOS.
 */
export default class SmartKeyboardInsetsPlugin implements FlutterPlugin, MethodCallHandler,
AbilityAware, StreamHandler {
  private methodChannel: MethodChannel | null = null;
  private eventChannel: EventChannel | null = null;
  private eventSink: EventSink | null = null;
  private ability: UIAbility | null = null;
  private hostWindow: window.Window | null = null;
  private isListening: boolean = false;
  private keyboardHeightPx: number = 0;
  private navigationHeightPx: number = 0;

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    const messenger = binding.getBinaryMessenger();
    this.methodChannel = new MethodChannel(messenger, METHOD_CHANNEL_NAME);
    this.methodChannel.setMethodCallHandler(this);
    this.eventChannel = new EventChannel(messenger, EVENT_CHANNEL_NAME);
    this.eventChannel.setStreamHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.stopListening();
    this.eventSink = null;
    this.methodChannel?.setMethodCallHandler(null);
    this.methodChannel = null;
    this.eventChannel?.setStreamHandler(null);
    this.eventChannel = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.ability = binding.getAbility();
    if (this.eventSink !== null && !this.isListening) {
      this.startListening();
      this.sendMetrics();
    }
  }

  onDetachedFromAbility(): void {
    this.stopListening();
    this.ability = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'getCurrentMetrics') {
      result.success(this.currentMetrics());
    } else {
      result.notImplemented();
    }
  }

  onListen(args: Any, events: EventSink): void {
    this.eventSink = events;
    this.startListening();
    this.sendMetrics();
  }

  onCancel(args: Any): void {
    this.stopListening();
    this.eventSink = null;
  }

  private avoidAreaChange = (options: window.AvoidAreaOptions): void => {
    if (options.type === window.AvoidAreaType.TYPE_KEYBOARD) {
      this.keyboardHeightPx = options.area.bottomRect.height;
      this.sendMetrics();
    } else if (options.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
      this.navigationHeightPx = options.area.bottomRect.height;
      this.sendMetrics();
    }
  };

  private keyboardHeightChange = (height: number): void => {
    this.keyboardHeightPx = height;
    this.sendMetrics();
  };

  /** Registers the window listeners, seeding the heights from the current avoid areas. */
  private startListening(): void {
    if (this.isListening) {
      return;
    }
    const hostWindow = this.resolveMainWindow();
    if (hostWindow === null) {
      Log.w(TAG, 'No window available yet, keyboard metrics stay hidden.');
      return;
    }
    try {
      this.keyboardHeightPx = hostWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD).bottomRect.height;
      this.navigationHeightPx =
        hostWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect.height;
      hostWindow.on('avoidAreaChange', this.avoidAreaChange);
      hostWindow.on('keyboardHeightChange', this.keyboardHeightChange);
      this.hostWindow = hostWindow;
      this.isListening = true;
    } catch (err) {
      Log.e(TAG, 'Failed to listen for avoid area changes: ' + JSON.stringify(err));
    }
  }

  private stopListening(): void {
    const hostWindow = this.hostWindow;
    if (!this.isListening || hostWindow === null) {
      return;
    }
    try {
      hostWindow.off('avoidAreaChange', this.avoidAreaChange);
      hostWindow.off('keyboardHeightChange', this.keyboardHeightChange);
    } catch (err) {
      Log.e(TAG, 'Failed to stop listening for avoid area changes: ' + JSON.stringify(err));
    }
    this.isListening = false;
    this.hostWindow = null;
  }

  private sendMetrics(): void {
    this.eventSink?.success(this.currentMetrics());
  }

  private currentMetrics(): Map<string, Object> {
    const density = this.densityPixels();
    const metrics: Map<string, Object> = new Map();
    metrics.set('keyboardHeight', this.keyboardHeightPx / density);
    metrics.set('safeAreaBottom', this.navigationHeightPx / density);
    metrics.set('isKeyboardVisible', this.keyboardHeightPx > 0);
    return metrics;
  }

  private densityPixels(): number {
    try {
      const density = display.getDefaultDisplaySync().densityPixels;
      return density > 0 ? density : 1;
    } catch (err) {
      Log.e(TAG, 'Failed to read the display density: ' + JSON.stringify(err));
      return 1;
    }
  }

  private resolveMainWindow(): window.Window | null {
    const manager = FlutterManager.getInstance();
    try {
      const targetAbility = this.ability ?? manager.getUIAbility();
      if (targetAbility === null || targetAbility === undefined) {
        return null;
      }
      return manager.getWindowStage(targetAbility)?.getMainWindowSync() ?? null;
    } catch (err) {
      Log.e(TAG, 'Failed to resolve the main window: ' + JSON.stringify(err));
      return null;
    }
  }
}
