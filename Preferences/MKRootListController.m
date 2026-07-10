//
//  MKRootListController.m
//

#import "MKRootListController.h"
#import <UIKit/UIKit.h>
#import <Preferences/PSSpecifier.h>

// 偏好设置域名(与 Tweak 读取的文件一致)
static NSString * const kPrefsDomain = @"com.mk.runningdotindicatorprefs";
// 每次值变化时广播的 Darwin 通知名
static NSString * const kReloadNotification = @"com.mk.runningdotindicator.reload";

@implementation MKRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];

        // 手动绑定注销按钮：PSButtonCell 仅靠 plist 中的 action 有时不触发
        // 通过 setButtonAction 确保点击后调用 respring 方法
        for (PSSpecifier *spec in _specifiers) {
            NSString *action = [spec propertyForKey:@"action"];
            if ([action isEqualToString:@"respring"]) {
                [spec setButtonAction:@selector(respring)];
            }
        }
    }
    return _specifiers;
}

// 拦截写值: 先写偏好, 再广播通知让 Tweak 实时刷新
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key) {
        CFPreferencesSetValue((__bridge CFStringRef)key,
                              (__bridge CFPropertyListRef)value,
                              (__bridge CFStringRef)kPrefsDomain,
                              kCFPreferencesCurrentUser,
                              kCFPreferencesAnyHost);
        CFPreferencesAppSynchronize((__bridge CFStringRef)kPrefsDomain);
    }
    // 同步刷新界面显示
    [self reloadSpecifier:specifier animated:YES];

    // 广播 Darwin 通知
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)kReloadNotification,
        NULL, NULL, TRUE);
}

// 颜色选择等需要返回当前值的 cell
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return nil;
    CFPropertyListRef v = CFPreferencesCopyAppValue(
        (__bridge CFStringRef)key,
        (__bridge CFStringRef)kPrefsDomain);
    if (v) {
        id result = (__bridge_transfer id)v;
        return result;
    }
    return [specifier propertyForKey:@"default"];
}

// 注销按钮(无参版): 某些 PreferenceLoader 版本使用此签名
- (void)respring {
    [self respring:nil];
}

// 注销按钮(带参版): 多数 PreferenceLoader 当 action="respring" 时调用此签名
// 注意：设置 App 处于沙盒内，无法直接 posix_spawn/kill，因此这里只广播通知，
//       真正的 respring 由运行在 SpringBoard(非沙盒)中的 Tweak 监听并执行。
- (void)respring:(PSSpecifier *)specifier {
    NSLog(@"[RD-Prefs] respring requested -> posting Darwin notification");
    // 确保最新配置已写入
    CFPreferencesAppSynchronize((__bridge CFStringRef)kPrefsDomain);
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.mk.runningdotindicator.respring"),
        NULL, NULL, TRUE);
}

@end
