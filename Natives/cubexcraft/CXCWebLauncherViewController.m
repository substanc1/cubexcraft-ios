#include <ctype.h>
#import <WebKit/WebKit.h>
#import <os/proc.h>
#import "CXCWebLauncherViewController.h"
#import "CXCApi.h"
#import "CXCDevice.h"
#import "CXCInstaller.h"
#import "../authenticator/BaseAuthenticator.h"
#import "../LauncherNavigationController.h"
#import "../LauncherPreferences.h"
#import "../LauncherPreferencesViewController.h"
#import "../utils.h"

typedef void (^CXCReply)(id _Nullable reply, NSString * _Nullable error);

@interface CXCWebLauncherViewController () <WKScriptMessageHandlerWithReply>
@property(nonatomic) WKWebView *web;
@property(nonatomic, nullable) CubeXCraftAuthenticator *pendingLogin;
@property(nonatomic, nullable) CXCInstaller *installer;
@property(nonatomic, nullable) NSTimer *prepTimer;
@property(nonatomic) BOOL preparing;
@property(nonatomic) long long lastBytes;
@property(nonatomic) CFTimeInterval lastTime;
@property(nonatomic) double speed;
@property(nonatomic) NSInteger appearCount;
@end

@implementation CXCWebLauncherViewController

- (void)loadView {
    WKWebViewConfiguration *config = [WKWebViewConfiguration new];
    [config.userContentController addScriptMessageHandlerWithReply:self contentWorld:WKContentWorld.pageWorld name:@"cxc"];
    self.web = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    UIColor *bg = [UIColor colorWithRed:11/255.0 green:5/255.0 blue:9/255.0 alpha:1];
    self.web.opaque = NO;
    self.web.backgroundColor = bg;
    self.web.scrollView.backgroundColor = bg;
    self.web.scrollView.bounces = NO;
    self.web.scrollView.scrollEnabled = NO;   // прокручивают блоки страницы, не сама страница
    // безопасные зоны считает CSS (env(safe-area-inset-*)), без отступов от UIScrollView
    self.web.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.view = self.web;
    NSURL *index = [NSBundle.mainBundle URLForResource:@"index" withExtension:@"html" subdirectory:@"cxc-ui"];
    [self.web loadFileURL:index allowingReadAccessToURL:index.URLByDeletingLastPathComponent];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // вернулись из StikDebug / LocalDevVPN / App Store — страница перепроверяет помощников JIT
    __weak typeof(self) weakSelf = self;
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        [weakSelf emit:@"active" data:weakSelf.jitInfo];
    }];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (@available(iOS 16.0, *)) {
        if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad) {
            [self.navigationController setNeedsUpdateOfSupportedInterfaceOrientations];
            UIWindowSceneGeometryPreferencesIOS *portrait = [[UIWindowSceneGeometryPreferencesIOS alloc]
                initWithInterfaceOrientations:UIInterfaceOrientationMaskPortrait];
            [self.view.window.windowScene requestGeometryUpdateWithPreferences:portrait errorHandler:nil];
        }
    }
    if (self.appearCount++ > 0) {
        [self emit:@"resume" data:@{}];
    }
}

// лаунчер — только вертикально (на iPad — как удобно); на время запуска игры — горизонтально
static BOOL cxcLandscapeForGame = NO;

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) return UIInterfaceOrientationMaskAll;
    return cxcLandscapeForGame ? UIInterfaceOrientationMaskLandscape : UIInterfaceOrientationMaskPortrait;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (LauncherNavigationController *)nav {
    return (LauncherNavigationController *)self.navigationController;
}

- (nullable CubeXCraftAuthenticator *)account {
    id auth = BaseAuthenticator.current;
    return [auth isKindOfClass:CubeXCraftAuthenticator.class] && [auth launcherToken] ? auth : nil;
}

#pragma mark - Мост со страницей

- (void)emit:(NSString *)type data:(NSDictionary *)data {
    NSData *json = [NSJSONSerialization dataWithJSONObject:data ?: @{} options:0 error:nil];
    NSString *js = [NSString stringWithFormat:@"window.cxc && window.cxc.emit('%@', %@)", type,
        [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] ?: @"{}"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.web evaluateJavaScript:js completionHandler:nil];
    });
}

- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message replyHandler:(CXCReply)reply {
    NSDictionary *m = [message.body isKindOfClass:NSDictionary.class] ? message.body : @{};
    NSString *cmd = m[@"cmd"];
    if ([cmd isEqual:@"init"]) [self cmdInit:reply];
    else if ([cmd isEqual:@"api"]) [self cmdApi:m reply:reply];
    else if ([cmd isEqual:@"image"]) [self cmdImage:m reply:reply];
    else if ([cmd isEqual:@"projectState"]) [self cmdProjectState:m reply:reply];
    else if ([cmd isEqual:@"login"]) [self cmdLogin:m reply:reply];
    else if ([cmd isEqual:@"cancelLogin"]) { self.pendingLogin.cancelled = YES; reply(@{}, nil); }
    else if ([cmd isEqual:@"logout"]) [self cmdLogout:reply];
    else if ([cmd isEqual:@"play"]) [self cmdPlay:m reply:reply];
    else if ([cmd isEqual:@"cancelPlay"]) [self cmdCancelPlay:reply];
    else if ([cmd isEqual:@"jitCheck"]) reply(self.jitInfo, nil);
    else if ([cmd isEqual:@"jitRetry"]) { [self.nav cxcRetryJIT]; reply(@{}, nil); }
    else if ([cmd isEqual:@"setSetting"]) [self cmdSetSetting:m reply:reply];
    else if ([cmd isEqual:@"openURL"]) { [self open:m[@"url"]]; reply(@{}, nil); }
    else if ([cmd isEqual:@"openStore"]) { [CXCDevice openHelper:[m[@"app"] isEqual:@"stik"] ? @"stik" : @"vpn"]; reply(@{}, nil); }
    else if ([cmd isEqual:@"share"]) [self cmdShare:m reply:reply];
    else if ([cmd isEqual:@"openAdvanced"]) [self cmdOpenAdvanced:reply];
    else reply(nil, [@"unknown command: " stringByAppendingString:cmd ?: @"?"]);
}

- (void)open:(NSString *)url {
    NSURL *u = [url isKindOfClass:NSString.class] ? [NSURL URLWithString:url] : nil;
    if (u) [UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil];
}

#pragma mark - Команды

// помощники JIT: StikDebug стоит, туннель поднят, LocalDevVPN стоит
- (NSDictionary *)jitInfo {
    return @{@"stik": @(CXCDevice.stikDebugInstalled), @"vpn": @(CXCDevice.vpnActive), @"vpnApp": @(CXCDevice.localDevVPNInstalled)};
}

- (NSDictionary *)settingsInfo {
    return @{
        @"quality": getPrefObject(@"cubexcraft.quality") ?: @"auto",
        @"qualityAuto": [CXCDevice keyFor:CXCDevice.autoQuality],
        @"shaders": getPrefObject(@"cubexcraft.shaders") ?: @"auto",
        @"shadersAuto": @(CXCDevice.autoShaders),
        @"joinOnStart": @(getPrefBool(@"cubexcraft.join_on_start")),
    };
}

- (void)cmdInit:(CXCReply)reply {
    NSString *lang = getPrefObject(@"cubexcraft.lang");
    if (![lang isKindOfClass:NSString.class] || lang.length == 0) {
        lang = [NSLocale.preferredLanguages.firstObject hasPrefix:@"ru"] ? @"ru" : @"en";
    }
    CubeXCraftAuthenticator *acc = self.account;
    NSMutableDictionary *info = [self.settingsInfo mutableCopy];
    [info addEntriesFromDictionary:@{
        @"lang": lang,
        @"version": NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"",
        @"memTotalGB": @(round(NSProcessInfo.processInfo.physicalMemory / 1073741824.0)),
        @"memAvailGB": @(os_proc_available_memory() / 1073741824.0),
        @"jit": self.jitInfo,
        @"needsSetup": @(!getPrefBool(@"cubexcraft.setup_done")),
        // без права increased-memory-limit игре не хватает памяти (поставлено не через iloader CubeXCraft)
        @"lowMemory": @(!CXCDevice.hasIncreasedMemory),
    }];
    if (acc) {
        info[@"account"] = @{@"username": acc.authData[@"username"] ?: @"", @"uuid": acc.authData[@"profileId"] ?: @""};
    }
    reply(info, nil);
}

- (void)cmdApi:(NSDictionary *)m reply:(CXCReply)reply {
    NSString *path = m[@"path"];
    NSString *method = [m[@"method"] isKindOfClass:NSString.class] ? m[@"method"] : @"GET";
    NSDictionary *body = [m[@"body"] isKindOfClass:NSDictionary.class] ? m[@"body"] : nil;
    NSString *token = nil;
    if (![m[@"auth"] isEqual:@NO]) {
        token = self.account.launcherToken;
        if (!token) {
            reply(@{@"status": @401, @"json": @{}}, nil);
            return;
        }
    }
    if (![path isKindOfClass:NSString.class] || ![path hasPrefix:@"/"]) {
        reply(nil, @"bad path");
        return;
    }
    [CXCApi request:method path:path token:token body:body callback:^(NSDictionary *json, NSInteger status, NSString *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (status == 0) reply(@{@"network": @YES}, nil);
            else reply(@{@"status": @(status), @"json": json ?: @{}}, nil);
        });
    }];
}

// обложка новости сайта как data:-адрес для ленты на главном экране (только картинки с сайта, до 2 МБ)
- (void)cmdImage:(NSDictionary *)m reply:(CXCReply)reply {
    NSString *url = [m[@"url"] isKindOfClass:NSString.class] ? m[@"url"] : nil;
    NSURL *u = [url hasPrefix:@"https://www.cubexcraft.site/"] ? [NSURL URLWithString:url] : nil;
    if (!u) {
        reply(@{}, nil);
        return;
    }
    [[NSURLSession.sharedSession dataTaskWithURL:u completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger code = [resp isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
        NSString *type = resp.MIMEType ?: @"";
        NSDictionary *out = @{};
        if (!err && code == 200 && [type hasPrefix:@"image/"] && data.length <= (2 << 20)) {
            out = @{@"data": [NSString stringWithFormat:@"data:%@;base64,%@", type, [data base64EncodedStringWithOptions:0]]};
        }
        dispatch_async(dispatch_get_main_queue(), ^{ reply(out, nil); });
    }] resume];
}

// «gtceu-1.21.1-8.0.0.jar» → «gtceu»: имя без версии и загрузчика (названий модов API не отдаёт)
static NSString *modName(NSString *file) {
    NSMutableArray *words = [NSMutableArray new];
    for (NSString *part in [[file stringByDeletingPathExtension] componentsSeparatedByString:@"-"]) {
        NSString *low = part.lowercaseString;
        if (part.length == 0 || isdigit([part characterAtIndex:0]) || [low hasPrefix:@"mc1"] || [low hasPrefix:@"v1"]
            || [low isEqual:@"neoforge"] || [low isEqual:@"forge"] || [low isEqual:@"fabric"] || [low isEqual:@"all"]) {
            break;
        }
        [words addObject:part];
    }
    return words.count ? [words componentsJoinedByString:@" "] : [file stringByDeletingPathExtension];
}

- (void)cmdProjectState:(NSDictionary *)m reply:(CXCReply)reply {
    NSString *filesDir = [m[@"filesDir"] isKindOfClass:NSString.class] ? m[@"filesDir"] : @"CubeXCraft-mobile";
    NSString *modsDir = [NSString stringWithFormat:@"%s/custom_gamedir/%@/mods", getenv("GAME_DIR"), filesDir];
    NSArray *jars = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:modsDir error:nil]
        filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF ENDSWITH '.jar'"]];
    NSMutableArray *mods = [NSMutableArray new];
    if (jars.count) {
        for (NSString *jar in jars) [mods addObject:modName(jar)];
        reply(@{@"installed": @YES, @"mods": [mods sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]}, nil);
        return;
    }
    // ещё не скачана: размер и моды — по манифесту раздачи
    NSString *token = self.account.launcherToken;
    [CXCApi get:[@"/files/" stringByAppendingString:filesDir] token:token callback:^(NSDictionary *json, NSInteger status, NSString *error) {
        long long bytes = 0;
        NSMutableArray *names = [NSMutableArray new];
        NSDictionary *files = [json[@"files"] isKindOfClass:NSDictionary.class] ? json[@"files"] : @{};
        for (NSString *path in files) {
            NSArray *meta = files[path];
            if ([meta isKindOfClass:NSArray.class] && meta.count) bytes += [meta[0] longLongValue];
            if ([path hasPrefix:@"mods/"] && [path hasSuffix:@".jar"]) [names addObject:modName(path.lastPathComponent)];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableDictionary *r = [@{@"installed": @NO, @"mods": [names sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]} mutableCopy];
            if (bytes) r[@"sizeMB"] = @((long long)round(bytes / 1048576.0));
            reply(r, nil);
        });
    }];
}

- (void)cmdLogin:(NSDictionary *)m reply:(CXCReply)reply {
    NSString *login = m[@"login"], *password = m[@"password"];
    if (![login isKindOfClass:NSString.class] || ![password isKindOfClass:NSString.class]) {
        reply(@{@"ok": @NO, @"code": @"password"}, nil);
        return;
    }
    CubeXCraftAuthenticator *auth = [[CubeXCraftAuthenticator alloc] initWithLogin:login password:password];
    self.pendingLogin = auth;
    __weak typeof(self) weakSelf = self;
    // при входе statusHandler зовётся только на 2FA: «подтвердите в Telegram»
    auth.statusHandler = ^(NSString *status) {
        [weakSelf emit:@"login2fa" data:@{}];
    };
    [auth loginWithCallback:^(id status, BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.pendingLogin = nil;
            if (success) {
                setPrefObject(@"internal.selected_account", auth.authData[@"username"]);
                BaseAuthenticator.current = auth;
                reply(@{@"ok": @YES, @"account": @{@"username": auth.authData[@"username"] ?: login, @"uuid": auth.authData[@"profileId"] ?: @""}}, nil);
                return;
            }
            BaseAuthenticator.current = nil;   // неудачный вход не остаётся «текущим»
            NSInteger code = auth.lastStatus;
            NSString *kind = auth.cancelled ? @"cancelled" : code == 0 ? @"network" : code == 429 ? @"rate"
                : (code == 400 || code == 401) ? @"password" : @"other";
            reply(@{@"ok": @NO, @"code": kind, @"message": [status description] ?: @""}, nil);
        });
    }];
}

- (void)cmdLogout:(CXCReply)reply {
    CubeXCraftAuthenticator *acc = (CubeXCraftAuthenticator *)BaseAuthenticator.current;
    if ([acc isKindOfClass:CubeXCraftAuthenticator.class]) {
        NSString *name = acc.authData[@"username"];
        [acc logout];
        if (name.length) {
            [NSFileManager.defaultManager removeItemAtPath:[NSString stringWithFormat:@"%s/accounts/%@.json", getenv("AME_HOME"), name] error:nil];
        }
    }
    BaseAuthenticator.current = nil;
    setPrefObject(@"internal.selected_account", @"");
    reply(@{}, nil);
}

#pragma mark - Запуск

- (void)stopPrep {
    self.preparing = NO;
    [self.prepTimer invalidate];
    self.prepTimer = nil;
}

- (void)cmdPlay:(NSDictionary *)m reply:(CXCReply)reply {
    reply(@{}, nil);
    if (self.preparing) return;
    CubeXCraftAuthenticator *auth = self.account;
    if (!auth) {
        [self emit:@"prepError" data:@{@"message": @"Войдите в аккаунт CubeXCraft заново"}];
        return;
    }
    LauncherNavigationController *nav = self.nav;
    __weak typeof(self) weakSelf = self;
    nav.cxcEvents = ^(NSString *type, NSDictionary *data) {
        if ([type isEqual:@"prepError"]) [weakSelf stopPrep];
        if ([type isEqual:@"jit"]) [weakSelf.prepTimer invalidate];
        [weakSelf emit:type data:data];
    };
    self.preparing = YES;
    self.installer = nil;
    self.lastBytes = 0;
    self.lastTime = CACurrentMediaTime();
    self.speed = 0;
    [self emit:@"prep" data:@{@"phase": @0, @"percent": @0}];
    self.prepTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(prepTick) userInfo:nil repeats:YES];
    [auth refreshTokenWithCallback:^(id status, BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!weakSelf.preparing) return;
            if (!success) {
                [weakSelf stopPrep];
                [weakSelf emit:@"prepError" data:@{@"message": [status description] ?: @""}];
                return;
            }
            CXCInstaller *installer = [CXCInstaller new];
            weakSelf.installer = installer;
            NSString *token = auth.launcherToken;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                NSString *error = [installer runWithLauncherToken:token];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (installer.cancelled) {
                        [weakSelf stopPrep];
                        [weakSelf emit:@"prepCancelled" data:@{}];
                        return;
                    }
                    if (error) {
                        [weakSelf stopPrep];
                        [weakSelf emit:@"prepError" data:@{@"message": error, @"done": @(installer.filesDone), @"total": @(installer.filesTotal)}];
                        return;
                    }
                    weakSelf.installer = nil;
                    // сборка на месте — ванильные файлы и запуск делает код Amethyst (JIT — события «jit»)
                    [nav startDownloadForVersionId:CXC_VERSION_ID];
                });
            });
        });
    }];
}

- (void)prepTick {
    CFTimeInterval now = CACurrentMediaTime();
    CXCInstaller *installer = self.installer;
    if (installer) {
        long long bytes = installer.progress.completedUnitCount;
        if (now - self.lastTime >= 1) {
            double mbs = (bytes - self.lastBytes) / 1048576.0 / (now - self.lastTime);
            self.speed = self.speed > 0 ? self.speed * 0.6 + mbs * 0.4 : mbs;
            self.lastBytes = bytes;
            self.lastTime = now;
        }
        BOOL downloading = installer.phase == 1 && installer.filesTotal > 0;
        [self emit:@"prep" data:@{
            @"phase": @(installer.phase),
            @"percent": @(downloading ? installer.progress.fractionCompleted * 100 : 0),
            @"done": @(installer.filesDone), @"total": @(installer.filesTotal),
            @"mb": @(installer.bytesTotal / 1048576.0), @"speed": @(downloading ? MAX(self.speed, 0) : 0),
        }];
        return;
    }
    NSProgress *task = self.nav.cxcTaskProgress;
    if (task) {
        // файлы самой игры (ванильные 1.21.1 и ресурсы) — часть загрузки
        [self emit:@"prep" data:@{@"phase": @1, @"percent": @(task.fractionCompleted * 100)}];
    }
}

- (void)cmdCancelPlay:(CXCReply)reply {
    self.installer.cancelled = YES;
    [self.nav cxcCancel];
    if (!self.installer) {
        [self stopPrep];
    }
    reply(@{}, nil);
}

#pragma mark - Настройки и прочее

- (void)cmdSetSetting:(NSDictionary *)m reply:(CXCReply)reply {
    NSString *key = m[@"key"];
    id value = m[@"value"];
    if ([key isEqual:@"quality"]) setPrefObject(@"cubexcraft.quality", value);
    else if ([key isEqual:@"shaders"]) setPrefObject(@"cubexcraft.shaders", value);
    else if ([key isEqual:@"joinOnStart"]) setPrefBool(@"cubexcraft.join_on_start", [value boolValue]);
    else if ([key isEqual:@"lang"]) setPrefObject(@"cubexcraft.lang", value);
    else if ([key isEqual:@"setupDone"]) setPrefBool(@"cubexcraft.setup_done", [value boolValue]);
    reply(self.settingsInfo, nil);
}

- (void)cmdShare:(NSDictionary *)m reply:(CXCReply)reply {
    NSURL *url = [NSURL URLWithString:[m[@"url"] isKindOfClass:NSString.class] ? m[@"url"] : CXC_SITE];
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    share.popoverPresentationController.sourceView = self.view;
    share.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMaxY(self.view.bounds) - 40, 1, 1);
    [self presentViewController:share animated:YES completion:nil];
    reply(@{}, nil);
}

// скрытый вход (7 нажатий на версию): полные настройки Amethyst — для нас, не для игроков
- (void)cmdOpenAdvanced:(CXCReply)reply {
    LauncherPreferencesViewController *prefs = [LauncherPreferencesViewController new];
    prefs.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self action:@selector(closeAdvanced)];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:prefs];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
    reply(@{}, nil);
}

- (void)closeAdvanced {
    [self dismissViewControllerAnimated:YES completion:^{
        [self emit:@"settings" data:self.settingsInfo];
    }];
}

@end

// ждём, пока окно станет горизонтальным (до 2 с), и ещё чуть-чуть — чтобы размеры экрана игры были верные
static void cxcWaitLandscape(UIWindow *window, int tries, void (^done)(void)) {
    if (window.bounds.size.width > window.bounds.size.height || tries > 40) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), done);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        cxcWaitLandscape(window, tries + 1, done);
    });
}

void CXCRotateToLandscape(UIWindow *window, void (^done)(void)) {
    BOOL portrait = window.bounds.size.width < window.bounds.size.height;
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad || !portrait) {
        done();
        return;
    }
    if (@available(iOS 16.0, *)) {
        cxcLandscapeForGame = YES;
        [window.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
        UIWindowSceneGeometryPreferencesIOS *landscape = [[UIWindowSceneGeometryPreferencesIOS alloc]
            initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscape];
        [window.windowScene requestGeometryUpdateWithPreferences:landscape errorHandler:^(NSError *error) {
            NSLog(@"[CXC] поворот перед игрой не вышел: %@", error);
        }];
        cxcWaitLandscape(window, 0, done);
        return;
    }
    done();
}

UIViewController *CXCLauncherRoot(void) {
    cxcLandscapeForGame = NO;
    LauncherNavigationController *nav = [[LauncherNavigationController alloc] initWithRootViewController:[CXCWebLauncherViewController new]];
    nav.navigationBarHidden = YES;
    nav.toolbarHidden = YES;
    return nav;
}
