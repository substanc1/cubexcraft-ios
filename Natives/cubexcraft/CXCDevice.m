#import <CFNetwork/CFNetwork.h>
#include <ifaddrs.h>
#include <mach/mach.h>
#include <malloc/malloc.h>
#include <net/if.h>
#include <sys/socket.h>
#import <os/proc.h>
#import <UIKit/UIKit.h>
#import "CXCDevice.h"
#import "../LauncherPreferences.h"
#import "../utils.h"

@implementation CXCDevice

// Что ещё может кончиться, кроме запаса до выгрузки: 25.10 Sodium падал на realloc ~6 МБ при запасе 1,6 ГБ —
// смотрим адресное пространство, число областей памяти и malloc
static NSString *cxcProcessMemoryDetails(void) {
    task_vm_info_data_t vm;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vm, &count) != KERN_SUCCESS) {
        return @"task_info не ответил";
    }
    unsigned regions = 0;
    vm_address_t address = 0;
    vm_size_t size = 0;
    while (regions < 1000000) {
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t infoCount = VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t object = MACH_PORT_NULL;
        if (vm_region_64(mach_task_self(), &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info,
                &infoCount, &object) != KERN_SUCCESS) {
            break;
        }
        regions++;
        address += size;
    }
    malloc_statistics_t stats;
    malloc_zone_statistics(NULL, &stats);
    return [NSString stringWithFormat:@"след %llu МБ, до лимита %llu МБ, адреса %.1f ГБ, областей %u, malloc %zu/%zu МБ",
        vm.phys_footprint >> 20, vm.limit_bytes_remaining >> 20, vm.virtual_size / 1073741824.0, regions,
        stats.size_in_use >> 20, stats.size_allocated >> 20];
}

// В журнал: запас памяти до выгрузки системой — раз в 15 с и при предупреждении iOS. iOS убивает за память молча,
// без исключения в логе — по этим строкам видно, что дело в памяти и на каком шаге.
+ (void)load {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil
            queue:nil usingBlock:^(NSNotification *note) {
            NSLog(@"[CXC] iOS: мало памяти! до выгрузки осталось %llu МБ", (unsigned long long)(os_proc_available_memory() >> 20));
        }];
        static dispatch_source_t timer;
        timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), 15 * NSEC_PER_SEC, NSEC_PER_SEC);
        dispatch_source_set_event_handler(timer, ^{
            NSLog(@"[CXC] память: до выгрузки %llu МБ · %@", (unsigned long long)(os_proc_available_memory() >> 20),
                cxcProcessMemoryDetails());
        });
        dispatch_resume(timer);
    });
}

+ (BOOL)hasIncreasedMemory {
    return getEntitlementValue(@"com.apple.developer.kernel.increased-memory-limit");
}

+ (BOOL)stikDebugInstalled {
    return [UIApplication.sharedApplication canOpenURL:[NSURL URLWithString:@"stikjit://"]];
}

+ (void)openHelper:(NSString *)app {
    NSString *url;
    if ([app isEqual:@"stik"]) {
        // StikDebug убран из App Store (25.10) — его ставит CubeXCraft Installer; нет его — инструкция на сайте
        url = self.stikDebugInstalled ? @"stikjit://" : @"https://www.cubexcraft.site/?install=iphone";
    } else {
        // localdevvpn://enable?scheme=… — LocalDevVPN включает туннель и через секунду открывает нашу схему
        url = self.localDevVPNInstalled ? @"localdevvpn://enable?scheme=cubexcraft" : @"itms-apps://apps.apple.com/app/id6755608044";
    }
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:url] options:@{} completionHandler:nil];
}

+ (BOOL)localDevVPNInstalled {
    return [UIApplication.sharedApplication canOpenURL:[NSURL URLWithString:@"localdevvpn://"]];
}

// Туннель VPN поднят: интерфейс utun с адресом IPv4 (у LocalDevVPN — 10.7.1.1, маршрут только до 10.7.0.1,
// поэтому в настройках прокси системы его нет — по ним 24.10 включённый LocalDevVPN не находился).
// Запасной путь — настройки прокси (обычные VPN). Проверка приблизительная: игрок всегда может продолжить.
+ (BOOL)vpnActive {
    struct ifaddrs *list = NULL;
    BOOL found = NO;
    if (getifaddrs(&list) == 0) {
        for (struct ifaddrs *a = list; a && !found; a = a->ifa_next) {
            if (!a->ifa_addr || a->ifa_addr->sa_family != AF_INET || !(a->ifa_flags & IFF_UP)) continue;
            found = !strncmp(a->ifa_name, "utun", 4) || !strncmp(a->ifa_name, "ipsec", 5) || !strncmp(a->ifa_name, "ppp", 3);
        }
        freeifaddrs(list);
    }
    if (found) return YES;
    NSDictionary *settings = CFBridgingRelease(CFNetworkCopySystemProxySettings());
    for (NSString *name in [settings[@"__SCOPED__"] allKeys]) {
        if ([name hasPrefix:@"utun"] || [name hasPrefix:@"ipsec"] || [name hasPrefix:@"ppp"] || [name hasPrefix:@"tun"]) {
            return YES;
        }
    }
    return NO;
}

+ (CXCQuality)autoQuality {
    unsigned long long gb = NSProcessInfo.processInfo.physicalMemory >> 20;   // МБ
    // «Максимум» (полные текстуры) — только когда iOS дала приложению больше памяти (AltStore, право
    // increased-memory-limit); с Sideloadly и бесплатным Apple ID на 8 ГБ — «Сбалансировано»
    if (gb >= 7300) return getEntitlementValue(@"com.apple.developer.kernel.increased-memory-limit") ? CXCQualityMax : CXCQualityBalanced;
    if (gb >= 5300) return CXCQualityBalanced;   // 6 ГБ
    return CXCQualityLight;                      // 4 ГБ и меньше
}

+ (CXCQuality)effectiveQuality {
    NSString *q = getPrefObject(@"cubexcraft.quality");
    if ([q isEqual:@"max"]) return CXCQualityMax;
    if ([q isEqual:@"balanced"]) return CXCQualityBalanced;
    if ([q isEqual:@"light"]) return CXCQualityLight;
    return self.autoQuality;
}

+ (NSString *)titleFor:(CXCQuality)quality {
    switch (quality) {
        case CXCQualityMax: return @"Максимум";
        case CXCQualityBalanced: return @"Сбалансировано";
        default: return @"Лёгкий";
    }
}

+ (NSString *)keyFor:(CXCQuality)quality {
    switch (quality) {
        case CXCQualityMax: return @"max";
        case CXCQualityBalanced: return @"balanced";
        default: return @"light";
    }
}

+ (NSString *)memoryDescription {
    double total = NSProcessInfo.processInfo.physicalMemory / 1073741824.0;
    double avail = os_proc_available_memory() / 1073741824.0;
    return [NSString stringWithFormat:@"Память: %.0f ГБ, приложению доступно ~%.1f ГБ", round(total), avail];
}

+ (NSInteger)heapMBForQuality:(CXCQuality)quality {
    // Сколько ещё можно занять до выгрузки системой (jetsam). Без права increased-memory-limit (Sideloadly с
    // бесплатным Apple ID) это ~3,3 ГБ на 8-гигабайтном айфоне: при куче 2 ГБ iOS убивала игру на входе в мир
    // (текстуры, заставка, метапространство 84 модов — вне кучи). Поэтому без права — половина запаса, с ним — 60 %.
    NSInteger avail = (NSInteger)(os_proc_available_memory() >> 20);
    BOOL raised = getEntitlementValue(@"com.apple.developer.kernel.increased-memory-limit");
    NSInteger cap = quality == CXCQualityMax ? 3584 : quality == CXCQualityBalanced ? 2560 : 1792;
    NSInteger heap = avail > 0 ? (NSInteger)(avail * (raised ? 0.6 : 0.5)) : (NSInteger)((NSProcessInfo.processInfo.physicalMemory >> 20) / 4);
    heap = MIN(heap, cap);
    return MAX(heap, 1024);
}

#pragma mark - options.txt

+ (NSMutableArray<NSString *> *)readOptions:(NSString *)path {
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSMutableArray *lines = [NSMutableArray new];
    for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if (line.length) [lines addObject:line];
    }
    // без version: Minecraft считает файл древним и не применяет ничего (DEVLOG 24.10)
    if (![lines.firstObject hasPrefix:@"version:"]) {
        [lines insertObject:@"version:3955" atIndex:0];
    }
    return lines;
}

+ (void)set:(NSString *)key value:(NSString *)value in:(NSMutableArray<NSString *> *)lines {
    NSString *prefix = [key stringByAppendingString:@":"];
    for (NSUInteger i = 0; i < lines.count; i++) {
        if ([lines[i] hasPrefix:prefix]) {
            lines[i] = [prefix stringByAppendingString:value];
            return;
        }
    }
    [lines addObject:[prefix stringByAppendingString:value]];
}

+ (NSString *)get:(NSString *)key in:(NSArray<NSString *> *)lines {
    NSString *prefix = [key stringByAppendingString:@":"];
    for (NSString *line in lines) {
        if ([line hasPrefix:prefix]) return [line substringFromIndex:prefix.length];
    }
    return nil;
}

// лёгкий пак (16×) — последним, выше встроенного пака gtforms; на «Максимуме» снимается
+ (void)setLitePack:(BOOL)on in:(NSMutableArray<NSString *> *)lines {
    NSString *raw = [self get:@"resourcePacks" in:lines] ?: @"[\"vanilla\",\"mod_resources\"]";
    NSMutableArray *packs = [[NSJSONSerialization JSONObjectWithData:[raw dataUsingEncoding:NSUTF8StringEncoding]
        options:NSJSONReadingMutableContainers error:nil] mutableCopy] ?: [@[@"vanilla", @"mod_resources"] mutableCopy];
    [packs removeObject:@"file/cubex_lite.zip"];
    if (on) [packs addObject:@"file/cubex_lite.zip"];
    NSData *data = [NSJSONSerialization dataWithJSONObject:packs options:0 error:nil];
    [self set:@"resourcePacks" value:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] in:lines];
    NSString *incompatible = [self get:@"incompatibleResourcePacks" in:lines];
    if (!incompatible) [self set:@"incompatibleResourcePacks" value:@"[]" in:lines];
}

+ (void)applyQualityToGameDir:(NSString *)gameDir {
    CXCQuality q = self.effectiveQuality;
    NSInteger heap = [self heapMBForQuality:q];
    setPrefBool(@"java.auto_ram", NO);
    setPrefInt(@"java.allocated_memory", heap);
    NSLog(@"[CXC] качество %@, куча %ld МБ (%@)", [self titleFor:q], (long)heap, self.memoryDescription);

    // настройки игры трогаем только при смене качества — свои правки игрока в игре не затираются.
    // Метка — файлом рядом с options.txt (не в настройках Amethyst: те молча не сохраняют незнакомые ключи)
    // «:3» — версия пресетов: при её смене пресет применяется заново (0.1.5: дальность 5 без права на память;
    // 0.1.7: «Максимум» — дальность 8 вместо 10, на подгрузке чанков подтормаживало)
    NSString *key = [[self keyFor:q] stringByAppendingString:@":3"];
    NSString *optionsPath = [gameDir stringByAppendingPathComponent:@"options.txt"];
    NSString *markPath = [gameDir stringByAppendingPathComponent:@".cxc-quality"];
    NSString *applied = [NSString stringWithContentsOfFile:markPath encoding:NSUTF8StringEncoding error:nil];
    if ([applied isEqualToString:key] && [NSFileManager.defaultManager fileExistsAtPath:optionsPath]) {
        return;
    }
    NSMutableArray *lines = [self readOptions:optionsPath];
    NSDictionary *preset;
    switch (q) {
        case CXCQualityMax:
            preset = @{@"renderDistance": @"8", @"simulationDistance": @"6", @"graphicsMode": @"1", @"particles": @"0",
                @"maxFps": @"60", @"ao": @"true", @"entityShadows": @"true", @"biomeBlendRadius": @"2",
                @"mipmapLevels": @"2", @"renderClouds": @"\"fast\"", @"entityDistanceScaling": @"1.0"};
            break;
        case CXCQualityBalanced:
            preset = @{@"renderDistance": @"7", @"simulationDistance": @"5", @"graphicsMode": @"0", @"particles": @"1",
                @"maxFps": @"60", @"ao": @"true", @"entityShadows": @"false", @"biomeBlendRadius": @"1",
                @"mipmapLevels": @"0", @"renderClouds": @"\"false\"", @"entityDistanceScaling": @"0.75"};
            break;
        default:
            preset = @{@"renderDistance": @"5", @"simulationDistance": @"5", @"graphicsMode": @"0", @"particles": @"2",
                @"maxFps": @"30", @"ao": @"false", @"entityShadows": @"false", @"biomeBlendRadius": @"0",
                @"mipmapLevels": @"0", @"renderClouds": @"\"false\"", @"entityDistanceScaling": @"0.5"};
    }
    for (NSString *k in preset) {
        [self set:k value:preset[k] in:lines];
    }
    // чанки строятся в фоне, кадр их не ждёт
    [self set:@"prioritizeChunkUpdates" value:@"0" in:lines];
    if (!getEntitlementValue(@"com.apple.developer.kernel.increased-memory-limit")) {
        // без права на расширенную память (~3,3 ГБ на всё) — дальность 5: вдвое меньше чанков при входе в мир
        [self set:@"renderDistance" value:@"5" in:lines];
        [self set:@"simulationDistance" value:@"5" in:lines];
    }
    [self setLitePack:(q != CXCQualityMax) in:lines];
    NSString *text = [[lines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
    if ([text writeToFile:optionsPath atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
        [key writeToFile:markPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"[CXC] options.txt: пресет «%@»", [self titleFor:q]);
    }
}

#pragma mark - Шейдеры

+ (BOOL)autoShaders {
    // 25.10: с шейдерами Sodium через пару минут падает на realloc (OutOfMemoryError при запасе 1,6 ГБ, причина
    // ищется — SCRUM-363). Пока «Авто» = выключены; вручную «Вкл» по-прежнему можно. Было: только на «Максимуме»
    return NO;
}

+ (BOOL)effectiveShaders {
    NSString *s = getPrefObject(@"cubexcraft.shaders");
    if ([s isEqual:@"on"]) return YES;
    if ([s isEqual:@"off"]) return NO;
    return self.autoShaders;
}

// Профиль MEDIUM нашего пака (Complementary Reimagined, shaders.properties): с HIGH на iPhone 16 Pro было 20 кадров
// (тени 2048 на 192 блока, лучи света, отражения на блоках). Тени — на дальность прорисовки «Максимума» (8 чанков).
static NSString *const kShaderProfileMedium = @"SHADOW_QUALITY=1 shadowDistance=128.0 ENTITY_SHADOWS_DEFINE=-1 "
    "WATER_REFLECT_QUALITY=2 BLOCK_REFLECT_QUALITY=1 LIGHTSHAFT_QUALI_DEFINE=1 SSAO_QUALI_DEFINE=2 FXAA_DEFINE=1 "
    "DETAIL_QUALITY=2 CLOUD_QUALITY=2 ANISOTROPIC_FILTER=0 COLORED_LIGHTING=0";

// iris.properties — key=value; пак — наш CubeXCraft_shaders (Complementary под GregTech) из сборки ПК.
// С шейдерами — профиль MEDIUM и 75 % разрешения (video.resolution Amethyst): шейдеры считают каждый пиксель,
// а у 16 Pro экран 2622×1206; 75 % — вдвое меньше пикселей, на такой плотности экрана почти не заметно.
// Всё — только при смене выбора (метка «:2» — версия этих настроек): правки игрока в игре не затираются.
+ (void)applyShadersToGameDir:(NSString *)gameDir {
    BOOL on = self.effectiveShaders;
    NSString *key = on ? @"on:2" : @"off:2";
    NSString *path = [gameDir stringByAppendingPathComponent:@"config/iris.properties"];
    NSString *markPath = [gameDir stringByAppendingPathComponent:@".cxc-shaders"];
    NSString *applied = [NSString stringWithContentsOfFile:markPath encoding:NSUTF8StringEncoding error:nil];
    if ([applied isEqualToString:key] && [NSFileManager.defaultManager fileExistsAtPath:path]) {
        return;
    }
    NSString *pack = nil;
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:[gameDir stringByAppendingPathComponent:@"shaderpacks"] error:nil]) {
        if ([name hasPrefix:@"CubeXCraft_shaders"] && [name hasSuffix:@".zip"]) pack = name;
    }
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if (line.length) [lines addObject:line];
    }
    NSMutableDictionary *values = [@{@"enableShaders": on ? @"true" : @"false", @"disableUpdateMessage": @"true"} mutableCopy];
    if (pack) values[@"shaderPack"] = pack;
    for (NSString *k in values) {
        NSString *want = [NSString stringWithFormat:@"%@=%@", k, values[k]];
        NSUInteger i = [lines indexOfObjectPassingTest:^BOOL(NSString *line, NSUInteger idx, BOOL *stop) {
            return [line hasPrefix:[k stringByAppendingString:@"="]];
        }];
        if (i == NSNotFound) [lines addObject:want]; else lines[i] = want;
    }
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *out = [[lines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
    if (![out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]) return;
    if (on && pack) {
        // настройки пака у Iris — shaderpacks/<пак>.txt
        NSString *profile = [[kShaderProfileMedium componentsSeparatedByString:@" "] componentsJoinedByString:@"\n"];
        NSString *packOptions = [[gameDir stringByAppendingPathComponent:@"shaderpacks"]
            stringByAppendingPathComponent:[pack stringByAppendingString:@".txt"]];
        [[profile stringByAppendingString:@"\n"] writeToFile:packOptions atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    setPrefInt(@"video.resolution", on ? 75 : 100);
    [key writeToFile:markPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSLog(@"[CXC] iris.properties: шейдеры %@ (%@)%@", on ? @"включены" : @"выключены", pack ?: @"пак не найден",
        on ? @", профиль MEDIUM, разрешение 75 %" : @", разрешение 100 %");
}

@end
