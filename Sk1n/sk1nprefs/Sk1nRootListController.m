#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "Sk1nRespring.h"

@interface Sk1nRootListController : PSListController
@end

@implementation Sk1nRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)confirm:(NSString *)title message:(NSString *)msg destructive:(BOOL)destructive action:(void (^)(void))go {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Respring"
                                          style:destructive ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *x) { go(); }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)applyAndRespring {
    [self confirm:@"Apply & Respring" message:@"Your settings are saved now and take effect after SpringBoard restarts."
      destructive:NO action:^{
        CFPreferencesSynchronize(CFSTR("com.kolby.sk1n"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        Sk1nRespringNow();
    }];
}

- (void)revertToStock {
    [self confirm:@"Revert to Stock" message:@"Switches the active skin back to Stock and restarts SpringBoard."
      destructive:YES action:^{
        Sk1nSetActiveSkin(@"stock");
        CFPreferencesSetValue(CFSTR("slideToUnlock"), kCFBooleanFalse, CFSTR("com.kolby.sk1n"),
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize(CFSTR("com.kolby.sk1n"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        Sk1nRespringNow();
    }];
}

@end
