// Установка и обновление сборки CubeXTech перед запуском: профиль с сайта → файлы сборки (моды, конфиги, пак) с
// проверкой SHA-1 → описание версии NeoForge для Amethyst (библиотеки с нашей раздачи, LWJGL — свой у Amethyst).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#define CXC_VERSION_ID @"CubeXTech"
#define CXC_PROFILE_NAME @"CubeXTech"

@interface CXCInstaller : NSObject

@property(nonatomic, readonly) NSProgress *progress;          // байты файлов сборки
@property(nonatomic, copy, nullable) void (^statusHandler)(NSString *status);
@property(atomic) BOOL cancelled;

// Профиль CubeXTech в launcher_profiles.json Amethyst (создать/обновить и выбрать)
+ (void)ensureLauncherProfile;
+ (BOOL)isCubeXCraftProfileSelected;
+ (NSString *)gameDirPath;

// Синхронно (фоновый поток): nil — успех, иначе текст ошибки
- (nullable NSString *)runWithLauncherToken:(NSString *)token;

@end

NS_ASSUME_NONNULL_END
