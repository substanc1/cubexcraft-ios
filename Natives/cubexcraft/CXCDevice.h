// Качество под телефон: «Авто» выбирает по памяти устройства, игрок может переключить вручную.
//   Максимум      — 8+ ГБ (iPhone 15 Pro, 16, 16 Pro, 17): полные текстуры 32×, красивая графика, дальность 8, шейдеры;
//   Сбалансировано — 6 ГБ (iPhone 13 Pro/14/15): лёгкий пак 16×, быстрая графика, дальность 7;
//   Лёгкий        — 4 ГБ и меньше (iPhone 13 и старше): лёгкий пак, дальность 5, 30 FPS, без частиц.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CXCQuality) {
    CXCQualityLight = 0,
    CXCQualityBalanced = 1,
    CXCQualityMax = 2
};

@interface CXCDevice : NSObject

+ (CXCQuality)autoQuality;
+ (CXCQuality)effectiveQuality;            // с учётом выбора игрока (cubexcraft.quality)
+ (NSString *)titleFor:(CXCQuality)quality;
+ (NSString *)keyFor:(CXCQuality)quality;            // max / balanced / light
+ (BOOL)hasIncreasedMemory;                          // право increased-memory-limit (ставили iloader CubeXCraft)

// JIT на iOS 17.4+ включает StikDebug (App Store), а ему нужен включённый LocalDevVPN
+ (BOOL)stikDebugInstalled;
+ (BOOL)vpnActive;                                   // какой-нибудь VPN включён (туннель LocalDevVPN — utun)
+ (NSString *)memoryDescription;           // «8 ГБ, доступно приложению ~3,9 ГБ»

// Куча Java (МБ) под выбранное качество и реальный запас памяти процесса
+ (NSInteger)heapMBForQuality:(CXCQuality)quality;
// Перед запуском: куча в настройках Amethyst + options.txt сборки (только при смене качества)
+ (void)applyQualityToGameDir:(NSString *)gameDir;

// Шейдеры Iris (cubexcraft.shaders: auto / on / off; «Авто» — только на «Максимуме»)
+ (BOOL)autoShaders;
+ (BOOL)effectiveShaders;
// Перед запуском: config/iris.properties (только при смене выбора — включение в самой игре не затирается)
+ (void)applyShadersToGameDir:(NSString *)gameDir;

@end

NS_ASSUME_NONNULL_END
