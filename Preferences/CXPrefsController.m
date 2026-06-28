#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

@interface CXPrefsController : PSListController
@end

@implementation CXPrefsController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"CXPrefsController" target:self];
    }
    return _specifiers;
}

// Respring button — restarts SpringBoard so the Camera-app hooks pick up the new state.
- (void)respring {
    // Prefer the rootless sbreload/ldrestart path; fall back to killing backboardd.
    NSArray<NSString *> *candidates = @[
        @"/var/jb/usr/bin/sbreload",
        @"/var/jb/usr/bin/ldrestart",
        @"/usr/bin/sbreload"
    ];
    for (NSString *path in candidates) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
            [self runProcess:path];
            return;
        }
    }
    // Last resort: ask the system to relaunch the frontboard scene session.
    [self runProcess:@"/var/jb/usr/bin/killall"]; // killall backboardd handled in helper
}

- (void)runProcess:(NSString *)launchPath {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = launchPath;
    if ([launchPath hasSuffix:@"killall"]) {
        task.arguments = @[@"-9", @"backboardd"];
    }
    @try { [task launch]; }
    @catch (NSException *e) { NSLog(@"[CinematicX] Respring failed via %@: %@", launchPath, e); }
}

- (void)openGitHub {
    NSURL *url = [NSURL URLWithString:@"https://github.com/Afaqraza12/CinematicX"];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

@end
