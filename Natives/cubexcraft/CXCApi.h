// API лаунчера CubeXCraft (https://www.cubexcraft.site/api/launcher/v1) — тот же протокол, что у десктопа
// и Android: вход с 2FA через Telegram, профили сборок, манифесты файлов, токен игры.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#define CXC_SITE @"https://www.cubexcraft.site"
#define CXC_API CXC_SITE @"/api/launcher/v1"

// json — ответ (или nil), status — HTTP-код (0 — нет связи), error — текст ошибки по-русски (или nil)
typedef void (^CXCApiCallback)(NSDictionary * _Nullable json, NSInteger status, NSString * _Nullable error);

@interface CXCApi : NSObject

// Токен лаунчера (60 дней, скользящий) — в связке ключей, не в файлах
+ (nullable NSString *)launcherTokenFor:(NSString *)username;
+ (void)setLauncherToken:(nullable NSString *)token for:(NSString *)username;

+ (void)loginWithLogin:(NSString *)login password:(NSString *)password callback:(CXCApiCallback)callback;
// 2FA: ждёт до 20 с подтверждения в боте; ответ {status:'pending'} или {accessToken, user}
+ (void)poll2FA:(NSString *)challenge callback:(CXCApiCallback)callback;
+ (void)cancel2FA:(NSString *)challenge;

+ (void)get:(NSString *)path token:(nullable NSString *)token callback:(CXCApiCallback)callback;
+ (void)post:(NSString *)path token:(nullable NSString *)token body:(nullable NSDictionary *)body callback:(CXCApiCallback)callback;

// Синхронные обёртки для фонового установщика (не вызывать с главного потока)
+ (nullable NSDictionary *)getSync:(NSString *)path token:(nullable NSString *)token error:(NSString * _Nullable * _Nullable)error;
+ (nullable NSDictionary *)postSync:(NSString *)path token:(nullable NSString *)token body:(nullable NSDictionary *)body status:(NSInteger * _Nullable)status error:(NSString * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
