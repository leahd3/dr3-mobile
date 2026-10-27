#import <Cocoa/Cocoa.h>
#include <mach-o/dyld.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#ifndef DR3_WORK
#error DR3_WORK must name this local project's private workspace
#endif

static NSString *g_resources,*g_runRoot;
static BOOL g_testSession;
static void path_env(const char *key,NSString *base,NSString *suffix) {
    if(setenv(key,[base stringByAppendingPathComponent:suffix].fileSystemRepresentation,1))
        [NSException raise:@"Launch environment" format:@"%s: %s",key,strerror(errno)];
}
static NSTextField *label(NSString *text,CGFloat size,BOOL secondary) {
    NSTextField *v=[NSTextField wrappingLabelWithString:text];
    v.font=[NSFont systemFontOfSize:size];v.textColor=secondary?NSColor.secondaryLabelColor:NSColor.labelColor;
    return v;
}
static NSStackView *column(NSArray<NSView *> *views,CGFloat spacing) {
    NSStackView *v=[NSStackView stackViewWithViews:views];v.orientation=NSUserInterfaceLayoutOrientationVertical;
    v.alignment=NSLayoutAttributeLeading;v.spacing=spacing;return v;
}
static NSBox *section(NSString *title,NSArray<NSView *> *views) {
    NSBox *box=[NSBox new];box.title=title;box.contentViewMargins=NSMakeSize(16,12);
    NSStackView *v=column(views,8);v.translatesAutoresizingMaskIntoConstraints=NO;[box.contentView addSubview:v];
    [NSLayoutConstraint activateConstraints:@[[v.leadingAnchor constraintEqualToAnchor:box.contentView.leadingAnchor],
        [v.trailingAnchor constraintEqualToAnchor:box.contentView.trailingAnchor],
        [v.topAnchor constraintEqualToAnchor:box.contentView.topAnchor],
        [v.bottomAnchor constraintEqualToAnchor:box.contentView.bottomAnchor]]];return box;
}
// Index order matches the three-segment display control; each patched mode maps to its bundled image directory.
static NSArray<NSString *> *display_modes(void) { return @[@"normal",@"wide",@"wider"]; }
static NSString *display_folder(NSString *mode) {
    return [mode isEqualToString:@"normal"]?@"rewrite":[@"rewrite-" stringByAppendingString:mode];
}
static BOOL display_available(NSString *mode) {
    if([mode isEqualToString:@"normal"])return YES;
    NSString *folder=[g_resources stringByAppendingPathComponent:display_folder(mode)];
    return [NSFileManager.defaultManager fileExistsAtPath:[folder stringByAppendingPathComponent:@"main.patched.bin"]];
}
static NSString *display_note(NSString *mode) {
    if([mode isEqualToString:@"wide"])return NSLocalizedString(@"note.display.wide",nil);
    if([mode isEqualToString:@"wider"])return NSLocalizedString(@"note.display.wider",nil);
    return NSLocalizedString(@"note.display.normal",nil);
}
static NSString *selected_mode(NSSegmentedControl *control) {
    NSInteger index=control.selectedSegment;
    return display_modes()[index>=0&&index<(NSInteger)display_modes().count?index:0];
}

@interface DR3Launcher : NSObject <NSApplicationDelegate,NSWindowDelegate>
@property(strong) NSWindow *window;
@property(strong) NSSegmentedControl *mode;
@property(strong) NSButton *hud,*fx,*lan,*play;
@property(strong) NSPopUpButton *language;
@property(strong) NSTextField *displayNote,*graphicsNote;
@property BOOL starting;
@end
@implementation DR3Launcher
- (NSButton *)toggle:(NSString *)title key:(NSString *)key {
    NSButton *b=[NSButton checkboxWithTitle:title target:self action:@selector(changed:)];
    b.state=[NSUserDefaults.standardUserDefaults boolForKey:key]?NSControlStateValueOn:NSControlStateValueOff;
    b.identifier=key;return b;
}
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    (void)note;
    NSMenu *menu=[NSMenu new];NSMenuItem *applicationItem=[NSMenuItem new];[menu addItem:applicationItem];
    NSMenu *applicationMenu=[[NSMenu alloc] initWithTitle:@"DR3 Mobile"];
    NSMenuItem *quit=[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"menu.quit",nil) action:@selector(terminate:) keyEquivalent:@"q"];
    quit.target=NSApp;[applicationMenu addItem:quit];applicationItem.submenu=applicationMenu;NSApp.mainMenu=menu;
    [NSUserDefaults.standardUserDefaults registerDefaults:@{@"LaunchMetalHUD":@YES,@"LaunchMetalFX":@YES,@"LaunchLocalLAN":@YES,@"LaunchLanguage":@"system"}];
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,760,610)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title=NSLocalizedString(@"window.title",nil);self.window.delegate=self;self.window.contentMinSize=NSMakeSize(700,580);
    NSImageView *icon=[NSImageView imageViewWithImage:[[NSImage alloc] initWithContentsOfFile:[g_resources stringByAppendingPathComponent:@"AppIcon.icns"]]];
    [icon.widthAnchor constraintEqualToConstant:96].active=YES;[icon.heightAnchor constraintEqualToConstant:96].active=YES;
    NSTextField *title=label(@"DR3 Mobile",28,NO);title.font=[NSFont systemFontOfSize:28 weight:NSFontWeightSemibold];
    self.play=[NSButton buttonWithTitle:NSLocalizedString(@"button.play",nil) target:self action:@selector(start:)];self.play.bezelStyle=NSBezelStyleRounded;
    self.play.controlSize=NSControlSizeLarge;self.play.keyEquivalent=@"\r";self.play.identifier=@"start-game";
    [self.play.widthAnchor constraintGreaterThanOrEqualToConstant:190].active=YES;
    NSStackView *left=column(@[icon,title,label(NSLocalizedString(@"subtitle",nil),12,YES),self.play,
        label(NSLocalizedString(@"note.autosave",nil),12,YES),
        label(g_testSession?NSLocalizedString(@"save.test",nil):NSLocalizedString(@"save.local",nil),12,YES)],16);
    NSArray<NSString *> *modes=display_modes();
    self.mode=[NSSegmentedControl segmentedControlWithLabels:@[NSLocalizedString(@"mode.normal",nil),NSLocalizedString(@"mode.wide",nil),NSLocalizedString(@"mode.wider",nil)] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(changed:)];
    for(NSInteger i=1;i<(NSInteger)modes.count;i++)[self.mode setEnabled:display_available(modes[i]) forSegment:i];
    // LaunchDisplayMode supersedes the retired LaunchWide bool; a missing preference migrates from it.
    NSString *saved=[NSUserDefaults.standardUserDefaults stringForKey:@"LaunchDisplayMode"];
    if(!saved)saved=[NSUserDefaults.standardUserDefaults boolForKey:@"LaunchWide"]?@"wide":@"normal";
    NSInteger segment=[modes indexOfObject:saved];
    if(segment==NSNotFound||!display_available(modes[segment]))segment=0;
    self.mode.selectedSegment=segment;self.mode.identifier=@"display-mode";
    self.displayNote=label(@"",12,YES);self.graphicsNote=label(@"",12,YES);
    self.hud=[self toggle:NSLocalizedString(@"toggle.hud",nil) key:@"LaunchMetalHUD"];
    self.fx=[self toggle:NSLocalizedString(@"toggle.metalfx",nil) key:@"LaunchMetalFX"];
    self.lan=[self toggle:NSLocalizedString(@"toggle.lan",nil) key:@"LaunchLocalLAN"];
    self.language=[NSPopUpButton new];
    // NSMenuItem tags are integers, so each Switch language tag lives in representedObject.
    [self.language addItemWithTitle:NSLocalizedString(@"lang.system",nil)];self.language.lastItem.representedObject=@"system";
    [self.language addItemWithTitle:NSLocalizedString(@"lang.en",nil)];self.language.lastItem.representedObject=@"en-US";
    [self.language addItemWithTitle:NSLocalizedString(@"lang.zh",nil)];self.language.lastItem.representedObject=@"zh-Hans";
    self.language.identifier=@"LaunchLanguage";self.language.target=self;self.language.action=@selector(changed:);
    NSString *language=[NSUserDefaults.standardUserDefaults stringForKey:@"LaunchLanguage"];
    for(NSMenuItem *item in self.language.itemArray)if([item.representedObject isEqual:language])[self.language selectItem:item];
    NSStackView *right=column(@[section(NSLocalizedString(@"section.display",nil),@[self.mode,self.displayNote]),
        section(NSLocalizedString(@"section.graphics",nil),@[self.hud,self.fx,self.graphicsNote]),
        section(NSLocalizedString(@"section.lan",nil),@[self.lan,label(NSLocalizedString(@"note.lan",nil),12,YES)]),
        section(NSLocalizedString(@"section.language",nil),@[self.language,label(NSLocalizedString(@"note.language",nil),12,YES)])],14);
    for(NSView *v in right.arrangedSubviews)[v.widthAnchor constraintEqualToAnchor:right.widthAnchor].active=YES;
    NSStackView *content=[NSStackView stackViewWithViews:@[left,right]];content.orientation=NSUserInterfaceLayoutOrientationHorizontal;
    content.alignment=NSLayoutAttributeTop;content.distribution=NSStackViewDistributionFill;content.spacing=30;content.translatesAutoresizingMaskIntoConstraints=NO;
    [self.window.contentView addSubview:content];
    [NSLayoutConstraint activateConstraints:@[[content.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor constant:28],
        [content.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor constant:-28],
        [content.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor constant:28],
        [content.bottomAnchor constraintLessThanOrEqualToAnchor:self.window.contentView.bottomAnchor constant:-24],
        [left.widthAnchor constraintEqualToConstant:240],
        [right.widthAnchor constraintEqualToAnchor:content.widthAnchor constant:-270]]];
    [self changed:nil];[self.window center];[self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
}
- (void)changed:(id)sender {
    (void)sender;NSUserDefaults *d=NSUserDefaults.standardUserDefaults;
    NSString *mode=selected_mode(self.mode);
    [d setObject:mode forKey:@"LaunchDisplayMode"];
    for(NSButton *b in @[self.hud,self.fx,self.lan])[d setBool:b.state==NSControlStateValueOn forKey:b.identifier];
    [d setObject:self.language.selectedItem.representedObject forKey:@"LaunchLanguage"];
    self.displayNote.stringValue=display_note(mode);
    self.graphicsNote.stringValue=self.fx.state==NSControlStateValueOn?NSLocalizedString(@"note.graphics.fx",nil):NSLocalizedString(@"note.graphics.direct",nil);
}
- (void)start:(id)sender {
    (void)sender;if(self.starting)return;self.starting=YES;self.play.enabled=NO;
    @try {
        BOOL fx=self.fx.state==NSControlStateValueOn;
        NSString *mode=selected_mode(self.mode);
        if(!display_available(mode))mode=@"normal";
        NSString *rewrite=[g_resources stringByAppendingPathComponent:display_folder(mode)];
        NSString *binary=[[[g_resources stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:@"dmhost"];
        NSFileManager *fm=NSFileManager.defaultManager;NSError *error=nil;
        if(![fm createDirectoryAtPath:[g_runRoot stringByAppendingPathComponent:@"temp"] withIntermediateDirectories:YES attributes:nil error:&error])
            [NSException raise:@"Launch files" format:@"%@",error.localizedDescription];
        FILE *log=freopen([[g_runRoot stringByAppendingPathComponent:@"app.log"] fileSystemRepresentation],"w",stderr);
        if(!log||dup2(fileno(log),STDOUT_FILENO)<0)[NSException raise:@"Launch log" format:@"%s",strerror(errno)];
        for(NSString *key in NSProcessInfo.processInfo.environment)if([key hasPrefix:@"DM_"])unsetenv(key.UTF8String);
        setenv("DM_ROOT",DR3_WORK,1);path_env("DM_ROMFS",@DR3_WORK,@"game/RomFS");path_env("DM_AOC_DIR",@DR3_WORK,@"aoc");
        path_env("DM_SAVE",g_runRoot,@"save");path_env("DM_TEMP",g_runRoot,@"temp");path_env("DM_HID_RECEIPT_LOG",g_runRoot,@"controller.jsonl");
        path_env("DM_PAD_EVENT_LOG",g_runRoot,@"controller-events.jsonl");path_env("DM_NVN_TSV",g_runRoot,@"performance.tsv");
        path_env("DM_NVN_SHMAP",g_resources,@"game/shader_map.tsv");path_env("DM_MSL_DIR",g_resources,@"shaders");
        // DM_LANG seeds new profiles; an existing save's Settings.json Language wins.
        NSString *language=self.language.selectedItem.representedObject;
        if([language isEqualToString:@"system"])language=NSLocale.preferredLanguages.firstObject?:@"en-US";
        language=[language.lowercaseString hasPrefix:@"zh"]?@"zh-Hans":@"en-US";
        setenv("DM_WINDOW","1",1);setenv("DM_AUDIO","1",1);setenv("DM_LANG",language.UTF8String,1);setenv("DM_OPMODE","0",1);
        setenv("DM_HID_RECEIPT_LIMIT","65536",1);setenv("DM_NVN_TSV_CALLS","0",1);setenv("DM_NVN_UNIFORM_FORWARD","1",1);
        setenv("DM_NVN_TBDR","0",1);setenv("DM_PSO_MANIFEST","off",1);
        setenv("MTL_HUD_ENABLED",self.hud.state==NSControlStateValueOn?"1":"0",1);
        setenv("DM_METALFX",fx?"spatial":"off",1);setenv("DM_MAC_DISPLAY_MODE",mode.UTF8String,1);
        setenv("DM_DR3_LAN",self.lan.state==NSControlStateValueOn?"1":"0",1);
        [NSUserDefaults.standardUserDefaults synchronize];
        fprintf(stderr,"launch: mode=%s HUD=%s MetalFX=%s LAN=%s lang=%s save=%s\n",mode.UTF8String,getenv("MTL_HUD_ENABLED"),getenv("DM_METALFX"),getenv("DM_DR3_LAN"),getenv("DM_LANG"),g_testSession?"test-copy":"local");
        char *args[]={(char *)binary.fileSystemRepresentation,(char *)rewrite.fileSystemRepresentation,"main","sdk",NULL};
        execv(args[0],args);[NSException raise:@"Launch failed" format:@"%s",strerror(errno)];
    } @catch(NSException *e) {
        NSAlert *alert=[NSAlert new];alert.messageText=NSLocalizedString(@"alert.failed.title",nil);alert.informativeText=e.reason?:NSLocalizedString(@"alert.failed.body",nil);[alert runModal];
        self.starting=NO;self.play.enabled=YES;
    }
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {(void)sender;return YES;}
@end

int main(int argc,char **argv) {
    @autoreleasepool {
        char exe[PATH_MAX],actual[PATH_MAX];uint32_t length=sizeof exe;
        if(_NSGetExecutablePath(exe,&length)||!realpath(exe,actual))return 1;
        NSString *folder=[[@(actual) stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
        g_resources=[folder stringByAppendingPathComponent:@"Resources"];g_runRoot=[@DR3_WORK stringByAppendingPathComponent:@"run"];
        NSString *testRoot=[NSBundle.mainBundle objectForInfoDictionaryKey:@"DR3TestSessionRoot"];
        if([testRoot isKindOfClass:NSString.class]) {
            if(!realpath(testRoot.fileSystemRepresentation,actual))return 1;g_runRoot=@(actual);g_testSession=YES;
            if(![NSFileManager.defaultManager fileExistsAtPath:[g_runRoot stringByAppendingPathComponent:@"save/account.dat"]])return 1;
        }
        for(int i=1;i<argc;i++)if(!strcmp(argv[i],"--session-root")&&i+1<argc){
            if(!realpath(argv[++i],actual))return 1;g_runRoot=@(actual);g_testSession=YES;
            if(![NSFileManager.defaultManager fileExistsAtPath:[g_runRoot stringByAppendingPathComponent:@"save/account.dat"]])return 1;
        }
        [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        DR3Launcher *launcher=[DR3Launcher new];NSApp.delegate=launcher;[NSApp run];
    }return 0;
}
