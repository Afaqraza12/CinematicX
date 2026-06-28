#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <spawn.h>

extern char **environ;

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
// Uses posix_spawn (NSTask is not available in the public iOS SDK).
- (void)respring {
    // Prefer the rootless sbreload/ldrestart path; fall back to killing backboardd.
    if ([self spawn:@"/var/jb/usr/bin/sbreload" args:@[@"sbreload"]]) return;
    if ([self spawn:@"/var/jb/usr/bin/ldrestart" args:@[@"ldrestart"]]) return;
    if ([self spawn:@"/usr/bin/sbreload" args:@[@"sbreload"]]) return;
    // Last resort: kill backboardd to force a frontboard relaunch.
    [self spawn:@"/var/jb/usr/bin/killall" args:@[@"killall", @"-9", @"backboardd"]];
}

// Returns YES if the executable exists and was spawned.
- (BOOL)spawn:(NSString *)path args:(NSArray<NSString *> *)args {
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:path]) return NO;

    NSUInteger count = args.count;
    char **argv = (char **)malloc(sizeof(char *) * (count + 1));
    for (NSUInteger i = 0; i < count; i++)
        argv[i] = strdup([args[i] UTF8String]);
    argv[count] = NULL;

    pid_t pid;
    int status = posix_spawn(&pid, [path fileSystemRepresentation], NULL, NULL, argv, environ);

    for (NSUInteger i = 0; i < count; i++) free(argv[i]);
    free(argv);

    if (status != 0) {
        NSLog(@"[CinematicX] Respring spawn failed (%d) via %@", status, path);
        return NO;
    }
    return YES;
}

- (void)openGitHub {
    NSURL *url = [NSURL URLWithString:@"https://github.com/Afaqraza12/CinematicX"];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

@end
