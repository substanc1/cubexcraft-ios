#import <os/proc.h>
#import <UIKit/UIKit.h>
#import "CXCDevice.h"
#import "../LauncherPreferences.h"
#import "../utils.h"

@implementation CXCDevice

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
            NSLog(@"[CXC] память: до выгрузки %llu МБ", (unsigned long long)(os_proc_available_memory() >> 20));
        });
        dispatch_resume(timer);
    });
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
    NSString *key = [self keyFor:q];
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
            preset = @{@"renderDistance": @"10", @"simulationDistance": @"6", @"graphicsMode": @"1", @"particles": @"0",
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
    [self setLitePack:(q != CXCQualityMax) in:lines];
    NSString *text = [[lines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
    if ([text writeToFile:optionsPath atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
        [key writeToFile:markPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"[CXC] options.txt: пресет «%@»", [self titleFor:q]);
    }
}

@end
