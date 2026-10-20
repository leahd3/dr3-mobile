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

@interface DR3Launcher : NSObject <NSApplicationDelegate,NSWindowDelegate>
@property(strong) NSWindow *window;
@property(strong) NSSegmentedControl *mode;
@property(strong) NSButton *hud,*fx,*lan,*play;
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
    NSMenuItem *quit=[[NSMenuItem alloc] initWithTitle:@"退出 DR3 Mobile" action:@selector(terminate:) keyEquivalent:@"q"];
    quit.target=NSApp;[applicationMenu addItem:quit];applicationItem.submenu=applicationMenu;NSApp.mainMenu=menu;
    [NSUserDefaults.standardUserDefaults registerDefaults:@{@"LaunchWide":@NO,@"LaunchMetalHUD":@YES,@"LaunchMetalFX":@YES,@"LaunchLocalLAN":@YES}];
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,760,470)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"DR3 Mobile · 启动设置";self.window.delegate=self;self.window.contentMinSize=NSMakeSize(700,450);
    NSImageView *icon=[NSImageView imageViewWithImage:[[NSImage alloc] initWithContentsOfFile:[g_resources stringByAppendingPathComponent:@"AppIcon.icns"]]];
    [icon.widthAnchor constraintEqualToConstant:96].active=YES;[icon.heightAnchor constraintEqualToConstant:96].active=YES;
    NSTextField *title=label(@"DR3 Mobile",28,NO);title.font=[NSFont systemFontOfSize:28 weight:NSFontWeightSemibold];
    self.play=[NSButton buttonWithTitle:@"开始游戏" target:self action:@selector(start:)];self.play.bezelStyle=NSBezelStyleRounded;
    self.play.controlSize=NSControlSizeLarge;self.play.keyEquivalent=@"\r";self.play.identifier=@"start-game";
    [self.play.widthAnchor constraintGreaterThanOrEqualToConstant:190].active=YES;
    NSStackView *left=column(@[icon,title,label(@"暗黑破坏神 III · 永恒之战版",12,YES),self.play,
        label(@"设置会自动保存，下次打开可重新选择。",12,YES),
        label(g_testSession?@"存档：联机测试副本":@"存档：本机游戏进度",12,YES)],16);
    self.mode=[NSSegmentedControl segmentedControlWithLabels:@[@"正常 16:9",@"宽屏"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(changed:)];
    self.mode.selectedSegment=[NSUserDefaults.standardUserDefaults boolForKey:@"LaunchWide"]?1:0;self.mode.identifier=@"display-mode";
    [self.mode setEnabled:[NSFileManager.defaultManager fileExistsAtPath:[g_resources stringByAppendingPathComponent:@"rewrite-wide/main.patched.bin"]] forSegment:1];
    if(![self.mode isEnabledForSegment:1])self.mode.selectedSegment=0;
    self.displayNote=label(@"",12,YES);self.graphicsNote=label(@"",12,YES);
    self.hud=[self toggle:@"Metal HUD" key:@"LaunchMetalHUD"];
    self.fx=[self toggle:@"MetalFX 超分" key:@"LaunchMetalFX"];
    self.lan=[self toggle:@"本地 Wi-Fi 联机" key:@"LaunchLocalLAN"];
    NSStackView *right=column(@[section(@"画面模式",@[self.mode,self.displayNote]),
        section(@"图形选项",@[self.hud,self.fx,self.graphicsNote]),
        section(@"局域网",@[self.lan,label(@"两台设备连接同一 Wi-Fi，在游戏内创建或加入本地游戏。",12,YES)])],14);
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
    [d setBool:self.mode.selectedSegment==1 forKey:@"LaunchWide"];
    for(NSButton *b in @[self.hud,self.fx,self.lan])[d setBool:b.state==NSControlStateValueOn forKey:b.identifier];
    self.displayNote.stringValue=self.mode.selectedSegment==1?@"1568×720，扩大左右视野；窗口保持画面比例。":@"1280×720，保留原版 16:9 视野。";
    self.graphicsNote.stringValue=self.fx.state==NSControlStateValueOn?@"720p 渲染，MetalFX 超分至 2K；HUD 显示帧率与 GPU 数据。":@"720p 渲染，直接适配窗口；HUD 显示帧率与 GPU 数据。";
}
- (void)start:(id)sender {
    (void)sender;if(self.starting)return;self.starting=YES;self.play.enabled=NO;
    @try {
        BOOL wide=self.mode.selectedSegment==1,fx=self.fx.state==NSControlStateValueOn;
        NSString *rewrite=[g_resources stringByAppendingPathComponent:wide?@"rewrite-wide":@"rewrite"];
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
        // zh-Hans needs the separate zhCN DLC pack; the shipped base set is enUS.
        setenv("DM_WINDOW","1",1);setenv("DM_AUDIO","1",1);setenv("DM_LANG","enUS",1);setenv("DM_OPMODE","0",1);
        setenv("DM_HID_RECEIPT_LIMIT","65536",1);setenv("DM_NVN_TSV_CALLS","0",1);setenv("DM_NVN_UNIFORM_FORWARD","1",1);
        setenv("DM_NVN_TBDR","0",1);setenv("DM_PSO_MANIFEST","off",1);
        setenv("MTL_HUD_ENABLED",self.hud.state==NSControlStateValueOn?"1":"0",1);
        setenv("DM_METALFX",fx?"spatial":"off",1);setenv("DM_MAC_DISPLAY_MODE",wide?"wide":"normal",1);
        setenv("DM_DR3_LAN",self.lan.state==NSControlStateValueOn?"1":"0",1);
        [NSUserDefaults.standardUserDefaults synchronize];
        fprintf(stderr,"launch: mode=%s HUD=%s MetalFX=%s LAN=%s save=%s\n",wide?"wide":"normal",getenv("MTL_HUD_ENABLED"),getenv("DM_METALFX"),getenv("DM_DR3_LAN"),g_testSession?"test-copy":"local");
        char *args[]={(char *)binary.fileSystemRepresentation,(char *)rewrite.fileSystemRepresentation,"main","sdk",NULL};
        execv(args[0],args);[NSException raise:@"Launch failed" format:@"%s",strerror(errno)];
    } @catch(NSException *e) {
        NSAlert *alert=[NSAlert new];alert.messageText=@"游戏未能启动";alert.informativeText=e.reason?:@"请检查本机游戏资源后重试。";[alert runModal];
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
