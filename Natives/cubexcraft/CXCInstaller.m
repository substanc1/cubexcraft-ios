#import <CommonCrypto/CommonDigest.h>
#import "CXCInstaller.h"
#import "CXCApi.h"
#import "CXCDevice.h"
#import "../PLProfiles.h"
#import "../authenticator/BaseAuthenticator.h"
#import "../LauncherPreferences.h"
#import "../utils.h"

// Откуда брать библиотеки NeoForge: в мобильной раздаче их нет (Android ставит NeoForge сам), берём из десктопной —
// там те же jar, что в classPath профиля (без натива: LWJGL у Amethyst свой).
static NSString *const kLibrariesDir = @"CubeXCraft";

@implementation CXCInstaller {
    NSProgress *_progress;
    NSMutableDictionary *_hashCache;
    NSString *_hashCachePath;
}

- (instancetype)init {
    self = [super init];
    _progress = [NSProgress progressWithTotalUnitCount:1];
    return self;
}

- (NSProgress *)progress {
    return _progress;
}

- (void)status:(NSString *)text {
    NSLog(@"[CXC] %@", text);
    if (self.statusHandler) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusHandler(text);
        });
    }
}

#pragma mark - Профиль Amethyst

+ (NSString *)gameDirPath {
    NSString *filesDir = getPrefObject(@"cubexcraft.files_dir") ?: @"CubeXCraft-mobile";
    return [NSString stringWithFormat:@"%s/custom_gamedir/%@", getenv("GAME_DIR"), filesDir];
}

+ (void)ensureLauncherProfile {
    NSString *filesDir = getPrefObject(@"cubexcraft.files_dir") ?: @"CubeXCraft-mobile";
    NSMutableDictionary *profiles = PLProfiles.current.profiles;
    NSMutableDictionary *profile = [profiles[CXC_PROFILE_NAME] mutableCopy] ?: [NSMutableDictionary new];
    profile[@"name"] = CXC_PROFILE_NAME;
    profile[@"lastVersionId"] = CXC_VERSION_ID;
    profile[@"gameDir"] = [@"./custom_gamedir/" stringByAppendingString:filesDir];
    profile[@"javaVersion"] = @"21";
    profile[@"cubexcraft"] = @YES;
    profiles[CXC_PROFILE_NAME] = profile;
    PLProfiles.current.selectedProfileName = CXC_PROFILE_NAME;   // сохраняет
}

+ (BOOL)isCubeXCraftProfileSelected {
    return [PLProfiles.current.selectedProfile[@"cubexcraft"] boolValue];
}

#pragma mark - Главный проход

- (NSString *)runWithLauncherToken:(NSString *)token {
    NSString *error;
    [self status:@"Получаю сборку CubeXTech…"];
    NSDictionary *profile = [self fetchProfile:token error:&error];
    if (!profile) return error;

    NSDictionary *mobile = profile[@"mobile"];
    NSString *filesDir = mobile[@"filesDir"] ?: profile[@"dir"];
    setPrefObject(@"cubexcraft.files_dir", filesDir);

    NSDictionary *manifest = [CXCApi getSync:[@"/files/" stringByAppendingString:filesDir] token:token error:&error];
    if (!manifest) return error;
    NSDictionary *libManifest = [CXCApi getSync:[@"/files/" stringByAppendingString:kLibrariesDir] token:token error:&error];
    if (!libManifest) return error;
    NSDictionary *cxlManifest = [CXCApi getSync:@"/files/@cxl" token:token error:&error];
    if (!cxlManifest) return error;

    NSString *gameDir = CXCInstaller.gameDirPath;
    [NSFileManager.defaultManager createDirectoryAtPath:gameDir withIntermediateDirectories:YES attributes:nil error:nil];
    // log4j игры пишет в logs/ относительно рабочей папки (GAME_DIR) — без папки latest.log не создаётся
    for (NSString *dir in @[[gameDir stringByAppendingPathComponent:@"logs"], [@(getenv("GAME_DIR")) stringByAppendingPathComponent:@"logs"]]) {
        [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    _hashCachePath = [gameDir stringByAppendingPathComponent:@".cxc-hashes.json"];
    _hashCache = parseJSONFromFile(_hashCachePath);
    if (_hashCache[@"NSErrorObject"]) {
        _hashCache = [NSMutableDictionary new];
    }

    // 1. Файлы сборки
    NSMutableArray *jobs = [NSMutableArray new];
    [self planFiles:manifest profile:profile gameDir:gameDir jobs:jobs];
    // 2. Библиотеки для описания версии
    NSMutableArray *libraries = [NSMutableArray new];
    error = [self planLibraries:profile manifest:manifest libManifest:libManifest cxlManifest:cxlManifest
        libraries:libraries jobs:jobs];
    if (error) return error;

    error = [self download:jobs];
    saveJSONToFile(_hashCache, _hashCachePath);
    if (error) return error;
    if (self.cancelled) return @"Отменено";

    [self removeExtras:manifest profile:profile gameDir:gameDir];
    // ModernFix: патч на рассказчик ищет com.mojang.text2speech.OperatingSystem, а у Amethyst своя заглушка
    // text2speech без него → MixinTransformerError при создании окна (24.10, iPhone 16 Pro)
    [self ensureProperty:@"mixin.feature.suppress_narrator_stacktrace" value:@"false"
        inFile:@"config/modernfix-mixins.properties" gameDir:gameDir manifest:manifest];
    saveJSONToFile(_hashCache, _hashCachePath);
    [self skipIntroIfLowMemory:gameDir];
    [self disableGTBloom:gameDir];

    // 3. Описание версии для Amethyst
    error = [self writeVersionJson:profile libraries:libraries];
    if (error) return error;

    [CXCInstaller ensureLauncherProfile];
    [CXCDevice applyQualityToGameDir:gameDir];
    [self status:@"Сборка готова"];
    return nil;
}

- (NSDictionary *)fetchProfile:(NSString *)token error:(NSString **)error {
    // Только мобильные профили (есть поле mobile): на неизвестную платформу сервер отдаёт десктопные — с Sodium/Iris,
    // которые на телефоне не работают. Пока у сайта нет ?platform=ios, берём сборку Android — она та же.
    NSMutableArray *profiles = [NSMutableArray new];
    for (NSString *platform in @[@"ios", @"android"]) {
        NSDictionary *json = [CXCApi getSync:[@"/profiles?platform=" stringByAppendingString:platform] token:token error:error];
        if (!json) return nil;
        for (NSDictionary *p in json[@"profiles"]) {
            if ([p[@"mobile"] isKindOfClass:NSDictionary.class]) [profiles addObject:p];
        }
        if (profiles.count) break;
    }
    for (NSDictionary *p in profiles) {
        if ([p[@"title"] isEqual:@"CubeXTech"]) return p;
    }
    if (!profiles.firstObject) {
        *error = @"На сервере нет мобильной сборки CubeXTech";
    }
    return profiles.firstObject;
}

#pragma mark - Файлы сборки

static BOOL pathMatches(NSString *path, NSArray *prefixes) {
    for (NSString *p in prefixes) {
        if ([path isEqualToString:p] || [path hasPrefix:[p stringByAppendingString:@"/"]]) return YES;
    }
    return NO;
}

- (void)planFiles:(NSDictionary *)manifest profile:(NSDictionary *)profile gameDir:(NSString *)gameDir jobs:(NSMutableArray *)jobs {
    NSString *base = manifest[@"base"];
    NSArray *exclusions = profile[@"updateExclusions"] ?: @[];
    NSDictionary *files = manifest[@"files"];
    [self status:[NSString stringWithFormat:@"Проверяю файлы сборки (%lu)…", (unsigned long)files.count]];
    for (NSString *path in files) {
        if ([path hasPrefix:@"libraries/"]) continue;          // идут в общий libraries через описание версии
        NSArray *meta = files[path];
        NSString *dest = [gameDir stringByAppendingPathComponent:path];
        BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:dest];
        // личные файлы игрока (options.txt и т. п.) — только если их ещё нет; options.txt правит пресет качества
        if (exists && (pathMatches(path, exclusions) || [path isEqualToString:@"options.txt"])) continue;
        if (exists && [[self sha1Of:dest] isEqualToString:meta[1]]) continue;
        [jobs addObject:@{@"url": [base stringByAppendingString:[self urlEncodePath:path]], @"dest": dest,
            @"size": meta[0], @"sha1": meta[1]}];
    }
}

- (void)removeExtras:(NSDictionary *)manifest profile:(NSDictionary *)profile gameDir:(NSString *)gameDir {
    NSDictionary *files = manifest[@"files"];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *dir in profile[@"updateVerify"] ?: @[@"mods"]) {
        NSString *root = [gameDir stringByAppendingPathComponent:dir];
        NSDirectoryEnumerator *it = [fm enumeratorAtPath:root];
        for (NSString *rel in it) {
            NSString *path = [dir stringByAppendingPathComponent:rel];
            BOOL isDir;
            [fm fileExistsAtPath:[root stringByAppendingPathComponent:rel] isDirectory:&isDir];
            if (!isDir && !files[path]) {
                NSLog(@"[CXC] лишний файл сборки удалён: %@", path);
                [fm removeItemAtPath:[root stringByAppendingPathComponent:rel] error:nil];
            }
        }
    }
}

// Заставка CubeXCraft Intro: без права increased-memory-limit её первый показ совпадает с пиком памяти при входе в мир
// (рецепты GTCEu, чанки) — iOS выгружает игру, ролик не досмотрен, и так при каждом входе (24.10, iPhone 16 Pro, 3,3 ГБ).
// На таких телефонах ставим метку «просмотрено» в формате мода: «ник:номер сброса» из resets.json (решение владельца).
- (void)skipIntroIfLowMemory:(NSString *)gameDir {
    if (getEntitlementValue(@"com.apple.developer.kernel.increased-memory-limit")) return;
    NSString *user = BaseAuthenticator.current.authData[@"username"];
    if (user.length == 0) return;
    NSDictionary *resets = parseJSONFromFile([gameDir stringByAppendingPathComponent:@"config/cubexcraft-intro/resets.json"]);
    int reset = resets[@"NSErrorObject"] ? 0 : [resets[user] intValue];
    NSString *mark = [NSString stringWithFormat:@"%@:%d", user, reset];
    NSString *path = [gameDir stringByAppendingPathComponent:@".cubexcraft-intro-seen"];
    NSString *current = [[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![current isEqualToString:mark]) {
        [mark writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"[CXC] заставка пропущена (нет права на расширенную память): %@", mark);
    }
}

// GregTech: свечение (bloom) выключено. Без Sodium чанки строит обычный путь Minecraft, и в нём GTCEu 8.0.0 падает
// «Not building!» на светящихся блоках (24.10, iPhone 16 Pro, gtceu:hpca_heat_sink_component). При type: DISABLED
// GTCEu не подключает свечение к сборке чанков (BloomShaderManager.isBloomActive), заодно меньше работы видеокарте.
// Файла ещё нет (первый запуск) — пишем только этот ключ: остальное мод дополнит значениями по умолчанию.
- (void)disableGTBloom:(NSString *)gameDir {
    NSString *path = [gameDir stringByAppendingPathComponent:@"config/gtceu.yaml"];
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    NSString *result = nil;
    if (text.length == 0) {
        result = @"client:\n  bloom:\n    type: DISABLED\n";
    } else {
        NSMutableArray<NSString *> *lines = [[text componentsSeparatedByString:@"\n"] mutableCopy];
        NSString *section = nil, *sub = nil;
        for (NSUInteger i = 0; i < lines.count; i++) {
            NSString *line = lines[i];
            NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (trimmed.length == 0 || [trimmed hasPrefix:@"#"]) continue;
            if (![line hasPrefix:@" "]) {
                section = line;
                sub = nil;
            } else if (![line hasPrefix:@"   "]) {
                sub = line;
            } else if ([section isEqualToString:@"client:"] && [sub isEqualToString:@"  bloom:"] && [line hasPrefix:@"    type:"]) {
                if ([trimmed isEqualToString:@"type: DISABLED"]) return;
                lines[i] = @"    type: DISABLED";
                result = [lines componentsJoinedByString:@"\n"];
                break;
            }
        }
        if (!result) {
            NSLog(@"[CXC] config/gtceu.yaml: не нашёл client.bloom.type");
            return;
        }
    }
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [result writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSLog(@"[CXC] config/gtceu.yaml: client.bloom.type: DISABLED");
}

// key=value в .properties сборки; файл дальше считается серверным (по кэшу хэшей), чтобы не перекачивать каждый раз
- (void)ensureProperty:(NSString *)key value:(NSString *)value inFile:(NSString *)rel gameDir:(NSString *)gameDir manifest:(NSDictionary *)manifest {
    NSString *dest = [gameDir stringByAppendingPathComponent:rel];
    NSString *text = [NSString stringWithContentsOfFile:dest encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSString *want = [NSString stringWithFormat:@"%@=%@", key, value];
    NSString *prefix = [key stringByAppendingString:@"="];
    NSMutableArray *lines = [NSMutableArray new];
    BOOL found = NO, changed = NO;
    for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if ([line hasPrefix:prefix]) {
            found = YES;
            changed |= ![line isEqualToString:want];
            [lines addObject:want];
        } else if (line.length) {
            [lines addObject:line];
        }
    }
    if (!found) {
        [lines addObject:want];
        changed = YES;
    }
    if (!changed) return;
    [NSFileManager.defaultManager createDirectoryAtPath:dest.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [[[lines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"] writeToFile:dest atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSArray *meta = manifest[@"files"][rel];
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:dest error:nil];
    if (meta && attrs) {
        NSString *stamp = [NSString stringWithFormat:@"%llu:%.0f", attrs.fileSize, attrs.fileModificationDate.timeIntervalSince1970];
        @synchronized (self) {
            _hashCache[dest] = @{@"stamp": stamp, @"sha1": meta[1]};
        }
    }
    NSLog(@"[CXC] %@: %@", rel, want);
}

#pragma mark - Библиотеки и описание версии

// libraries/net/neoforged/bus/8.0.5/bus-8.0.5.jar → net.neoforged:bus:8.0.5 (+ :классификатор)
static NSString *mavenName(NSString *rel) {
    NSArray *parts = [rel componentsSeparatedByString:@"/"];
    if (parts.count < 4) {
        return [NSString stringWithFormat:@"cubexcraft:%@:1", [rel.lastPathComponent stringByDeletingPathExtension]];
    }
    NSString *file = parts.lastObject;
    NSString *version = parts[parts.count - 2];
    NSString *artifact = parts[parts.count - 3];
    NSString *group = [[parts subarrayWithRange:NSMakeRange(0, parts.count - 3)] componentsJoinedByString:@"."];
    NSString *name = [NSString stringWithFormat:@"%@:%@:%@", group, artifact, version];
    NSString *plain = [NSString stringWithFormat:@"%@-%@", artifact, version];
    NSString *stem = [file stringByDeletingPathExtension];
    if ([stem hasPrefix:[plain stringByAppendingString:@"-"]]) {
        name = [name stringByAppendingFormat:@":%@", [stem substringFromIndex:plain.length + 1]];
    }
    return name;
}

- (NSString *)planLibraries:(NSDictionary *)profile manifest:(NSDictionary *)manifest libManifest:(NSDictionary *)libManifest
        cxlManifest:(NSDictionary *)cxlManifest libraries:(NSMutableArray *)libraries jobs:(NSMutableArray *)jobs {
    NSMutableOrderedSet *paths = [NSMutableOrderedSet new];
    [paths addObjectsFromArray:profile[@"classPath"] ?: @[]];
    [paths addObjectsFromArray:profile[@"moduleConf"][@"modulePath"] ?: @[]];
    [paths addObjectsFromArray:profile[@"altClassPath"] ?: @[]];
    NSString *libRoot = [NSString stringWithFormat:@"%s/libraries", getenv("GAME_DIR")];
    NSMutableSet *seenNames = [NSMutableSet new];

    for (NSString *entry in paths) {
        NSString *rel, *url;
        NSArray *meta;
        if ([entry hasPrefix:@"@cxl/"]) {
            // своя папка лаунчера (/cxl/libs, манифест без «libs/»): ванильный authlib 6.0.54 вместо Gravit
            NSString *key = [entry hasPrefix:@"@cxl/libs/"] ? [entry substringFromIndex:10] : entry.lastPathComponent;
            meta = cxlManifest[@"files"][key];
            url = [cxlManifest[@"base"] stringByAppendingString:[self urlEncodePath:key]];
            rel = [key.lastPathComponent hasPrefix:@"authlib-"] ?
                [NSString stringWithFormat:@"com/mojang/authlib/%@/%@",
                    [[key.lastPathComponent stringByDeletingPathExtension] substringFromIndex:8], key.lastPathComponent] :
                [@"cxl/" stringByAppendingString:key.lastPathComponent];
        } else if ([entry hasPrefix:@"libraries/"]) {
            rel = [entry substringFromIndex:10];
            NSDictionary *src = manifest[@"files"][entry] ? manifest : libManifest;
            meta = src[@"files"][entry];
            url = [src[@"base"] stringByAppendingString:[self urlEncodePath:entry]];
        } else {
            NSLog(@"[CXC] путь вне libraries пропущен: %@", entry);
            continue;
        }
        NSString *name = mavenName(rel);
        if ([name hasPrefix:@"org.lwjgl"] || [seenNames containsObject:name]) {
            continue;   // LWJGL — у Amethyst свой; повтор в classPath ломает BootstrapLauncher («Duplicate key»)
        }
        if (!meta) {
            return [NSString stringWithFormat:@"На сервере нет библиотеки %@", entry];
        }
        [seenNames addObject:name];
        [libraries addObject:@{@"name": name, @"downloads": @{@"artifact": @{
            @"path": rel, @"url": url, @"sha1": meta[1], @"size": meta[0]}}}];
        NSString *dest = [libRoot stringByAppendingPathComponent:rel];
        if (![[self sha1Of:dest] isEqualToString:meta[1]]) {
            [jobs addObject:@{@"url": url, @"dest": dest, @"size": meta[0], @"sha1": meta[1]}];
        }
    }

    // Сама игра — не в classPath: FML находит пропатченные jar Minecraft и NeoForge (client-…-srg/-extra,
    // neoforge-…-client/-universal) по -DlibraryDirectory. Без них «minecraft/neoforge [MISSING]» (24.10, первый запуск).
    NSDictionary *libFiles = libManifest[@"files"];
    for (NSString *path in libFiles) {
        if (![path hasPrefix:@"libraries/net/minecraft/"] && ![path hasPrefix:@"libraries/net/neoforged/neoforge/"]) continue;
        if ([path hasSuffix:@".cache"] || [path hasSuffix:@"/minecraft.jar"]) continue;
        NSString *rel = [path substringFromIndex:10];
        if ([paths containsObject:path]) continue;
        NSArray *meta = libFiles[path];
        NSString *dest = [libRoot stringByAppendingPathComponent:rel];
        if (![[self sha1Of:dest] isEqualToString:meta[1]]) {
            [jobs addObject:@{@"url": [libManifest[@"base"] stringByAppendingString:[self urlEncodePath:path]],
                @"dest": dest, @"size": meta[0], @"sha1": meta[1]}];
        }
    }
    return nil;
}

- (NSString *)writeVersionJson:(NSDictionary *)profile libraries:(NSArray *)libraries {
    NSMutableArray *jvm = [NSMutableArray new];
    for (NSString *arg in profile[@"jvmArgs"]) {
        if ([arg hasPrefix:@"-DlibraryDirectory="]) {
            [jvm addObject:@"-DlibraryDirectory=${library_directory}"];
        } else if ([arg hasPrefix:@"-Xmx"] || [arg hasPrefix:@"-Xms"]) {
            continue;   // кучу ставит лаунчер по телефону (CXCDevice)
        } else {
            [jvm addObject:arg];
        }
    }
    NSDictionary *mc = profile[@"moduleConf"];
    NSMutableArray *modulePath = [NSMutableArray new];
    for (NSString *p in mc[@"modulePath"]) {
        [modulePath addObject:[@"${library_directory}/" stringByAppendingString:[p substringFromIndex:10]]];
    }
    if (modulePath.count) {
        [jvm addObjectsFromArray:@[@"-p", [modulePath componentsJoinedByString:@"${classpath_separator}"]]];
        [jvm addObjectsFromArray:@[@"--add-modules", [mc[@"modules"] componentsJoinedByString:@","] ?: @"ALL-MODULE-PATH"]];
    }
    for (NSString *k in mc[@"exports"]) [jvm addObjectsFromArray:@[@"--add-exports", [NSString stringWithFormat:@"%@=%@", k, mc[@"exports"][k]]]];
    for (NSString *k in mc[@"opens"]) [jvm addObjectsFromArray:@[@"--add-opens", [NSString stringWithFormat:@"%@=%@", k, mc[@"opens"][k]]]];
    for (NSString *k in mc[@"reads"]) [jvm addObjectsFromArray:@[@"--add-reads", [NSString stringWithFormat:@"%@=%@", k, mc[@"reads"][k]]]];
    // Сборщик мусора — короткие паузы: без настроек на подгрузке чанков игра подтормаживала (24.10, iPhone 16 Pro).
    // -Xlog:gc — паузы в журнал, чтобы по логу игрока видеть, тормозит ли сборка мусора
    [jvm addObjectsFromArray:@[@"-XX:+UnlockExperimentalVMOptions", @"-XX:+UseG1GC", @"-XX:MaxGCPauseMillis=37",
        @"-XX:G1NewSizePercent=20", @"-XX:G1ReservePercent=20", @"-XX:G1HeapRegionSize=8M",
        @"-XX:+ParallelRefProcEnabled", @"-XX:+DisableExplicitGC", @"-Xlog:gc"]];

    // Аргументы игры целиком: Amethyst заменяет (не сливает) arguments ванильной версии
    NSMutableArray *game = [@[
        @"--username", @"${auth_player_name}", @"--version", @"${version_name}",
        @"--gameDir", @"${game_directory}", @"--assetsDir", @"${assets_root}",
        @"--assetIndex", @"${assets_index_name}", @"--uuid", @"${auth_uuid}",
        @"--accessToken", @"${auth_access_token}", @"--clientId", @"${clientid}",
        @"--userType", @"${user_type}", @"--versionType", @"CubeXCraft"
    ] mutableCopy];
    NSArray *client = profile[@"clientArgs"] ?: @[];
    for (NSUInteger i = 0; i < client.count; i++) {
        if ([client[i] isEqual:@"--width"] || [client[i] isEqual:@"--height"]) {
            i++;            // размер окна задаёт Amethyst
            continue;
        }
        [game addObject:client[i]];
    }
    NSDictionary *server = [profile[@"servers"] firstObject];
    if (server && getPrefBool(@"cubexcraft.auto_join")) {
        [game addObjectsFromArray:@[@"--quickPlayMultiplayer",
            [NSString stringWithFormat:@"%@:%@", server[@"serverAddress"], server[@"serverPort"]]]];
    }

    NSDictionary *version = @{
        @"id": CXC_VERSION_ID,
        @"inheritsFrom": profile[@"version"] ?: @"1.21.1",
        @"type": @"release",
        @"mainClass": profile[@"mainClass"],
        @"arguments": @{@"game": game, @"jvm": jvm},
        @"libraries": libraries,
        @"releaseTime": @"2024-08-08T00:00:00+00:00",
        @"time": @"2024-08-08T00:00:00+00:00"
    };
    NSString *dir = [NSString stringWithFormat:@"%s/versions/%@", getenv("GAME_DIR"), CXC_VERSION_ID];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSError *err = saveJSONToFile(version, [dir stringByAppendingPathComponent:[CXC_VERSION_ID stringByAppendingString:@".json"]]);
    return err ? err.localizedDescription : nil;
}

#pragma mark - Скачивание

- (NSString *)download:(NSArray *)jobs {
    if (jobs.count == 0) {
        _progress.totalUnitCount = 1;
        _progress.completedUnitCount = 1;
        return nil;
    }
    long long total = 0;
    for (NSDictionary *j in jobs) total += [j[@"size"] longLongValue];
    _progress.totalUnitCount = MAX(total, 1);
    _progress.completedUnitCount = 0;
    [self status:[NSString stringWithFormat:@"Загрузка сборки: %lu файлов, %.1f МБ", (unsigned long)jobs.count, total / 1048576.0]];

    NSOperationQueue *queue = [NSOperationQueue new];
    queue.maxConcurrentOperationCount = 6;
    __block NSString *firstError;
    NSObject *lock = [NSObject new];
    for (NSDictionary *job in jobs) {
        [queue addOperationWithBlock:^{
            if (firstError || self.cancelled) return;
            NSString *err = [self downloadJob:job];
            if (err) {
                @synchronized (lock) {
                    if (!firstError) firstError = err;
                }
            }
        }];
    }
    [queue waitUntilAllOperationsAreFinished];
    return firstError;
}

- (NSString *)downloadJob:(NSDictionary *)job {
    for (int attempt = 0; attempt < 3; attempt++) {
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block NSString *error;
        NSURL *url = [NSURL URLWithString:job[@"url"]];
        [[NSURLSession.sharedSession downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *netError) {
            NSInteger code = ((NSHTTPURLResponse *)response).statusCode;
            if (netError || code != 200) {
                error = [NSString stringWithFormat:@"Не скачался %@ (%@)", [job[@"dest"] lastPathComponent],
                    netError ? netError.localizedDescription : @(code)];
            } else {
                NSFileManager *fm = NSFileManager.defaultManager;
                NSString *dest = job[@"dest"];
                [fm createDirectoryAtPath:dest.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
                [fm removeItemAtPath:dest error:nil];
                NSError *moveError;
                [fm moveItemAtPath:location.path toPath:dest error:&moveError];
                if (moveError) {
                    error = moveError.localizedDescription;
                } else if (![[self sha1Of:dest] isEqualToString:job[@"sha1"]]) {
                    error = [NSString stringWithFormat:@"Файл %@ пришёл повреждённым", dest.lastPathComponent];
                    [fm removeItemAtPath:dest error:nil];
                }
            }
            dispatch_semaphore_signal(sem);
        }] resume];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        if (!error) {
            @synchronized (_progress) {
                _progress.completedUnitCount += [job[@"size"] longLongValue];
            }
            return nil;
        }
        if (attempt == 2) return error;
    }
    return nil;
}

- (NSString *)urlEncodePath:(NSString *)path {
    return [path stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
}

#pragma mark - SHA-1 с кэшем по размеру и времени файла

- (NSString *)sha1Of:(NSString *)path {
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    if (!attrs) return nil;
    NSString *key = path.lastPathComponent;
    NSString *stamp = [NSString stringWithFormat:@"%llu:%.0f", attrs.fileSize, attrs.fileModificationDate.timeIntervalSince1970];
    @synchronized (self) {
        NSDictionary *cached = _hashCache[path];
        if ([cached[@"stamp"] isEqualToString:stamp]) return cached[@"sha1"];
    }
    NSInputStream *stream = [NSInputStream inputStreamWithFileAtPath:path];
    [stream open];
    CC_SHA1_CTX ctx;
    CC_SHA1_Init(&ctx);
    uint8_t buffer[65536];
    NSInteger n;
    while ((n = [stream read:buffer maxLength:sizeof(buffer)]) > 0) {
        CC_SHA1_Update(&ctx, buffer, (CC_LONG)n);
    }
    [stream close];
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1_Final(digest, &ctx);
    NSMutableString *hex = [NSMutableString stringWithCapacity:40];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    @synchronized (self) {
        if (_hashCache) _hashCache[path] = @{@"stamp": stamp, @"sha1": hex};
    }
    (void)key;
    return hex;
}

@end
