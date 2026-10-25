// © 2026 CubeXCraft (https://www.cubexcraft.site). GPL-3.0 with additional terms (GPLv3 §7: attribution, origin, trademarks), see CUBEXCRAFT.md.
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import "CXCApi.h"

static NSString *const kKeychainService = @"site.cubexcraft.launcher";

@implementation CXCApi

#pragma mark - Токен лаунчера в связке ключей

+ (NSMutableDictionary *)keychainQuery:(NSString *)username {
    return @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kKeychainService,
        (__bridge id)kSecAttrAccount: username.lowercaseString
    }.mutableCopy;
}

+ (NSString *)launcherTokenFor:(NSString *)username {
    NSMutableDictionary *query = [self keychainQuery:username];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess || !result) {
        return nil;
    }
    NSData *data = (__bridge_transfer NSData *)result;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

+ (void)setLauncherToken:(NSString *)token for:(NSString *)username {
    NSMutableDictionary *query = [self keychainQuery:username];
    SecItemDelete((__bridge CFDictionaryRef)query);
    if (token.length == 0) {
        return;
    }
    query[(__bridge id)kSecValueData] = [token dataUsingEncoding:NSUTF8StringEncoding];
    query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    SecItemAdd((__bridge CFDictionaryRef)query, NULL);
}

#pragma mark - HTTP

+ (NSMutableURLRequest *)requestFor:(NSString *)path method:(NSString *)method token:(NSString *)token body:(NSDictionary *)body {
    NSURL *url = [NSURL URLWithString:[path hasPrefix:@"http"] ? path : [CXC_API stringByAppendingString:path]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = method;
    // 2FA и первый «настоящий» запрос после 7 дней сервер держит до 50 с
    req.timeoutInterval = 70;
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [req setValue:@"ios" forHTTPHeaderField:@"X-Launcher-Platform"];
    NSString *version = NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"0";
    [req setValue:version forHTTPHeaderField:@"X-Launcher-Version"];
    if (token.length) {
        [req setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    }
    if (body) {
        [req setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
        req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    }
    return req;
}

+ (NSString *)errorFor:(NSDictionary *)json status:(NSInteger)status netError:(NSError *)netError {
    if (netError) {
        return [NSString stringWithFormat:@"Нет связи с сервером CubeXCraft (%@)", netError.localizedDescription];
    }
    if (status >= 200 && status < 300) {
        return nil;
    }
    if ([json[@"message"] isKindOfClass:NSString.class] && [json[@"message"] length]) {
        return json[@"message"];
    }
    if ([json[@"error"] isEqual:@"auth"]) return @"Сессия истекла — войдите снова";
    if ([json[@"error"] isEqual:@"2fa"]) return @"Подтвердите вход в Telegram-боте";
    if ([json[@"error"] isEqual:@"banned"]) return @"Аккаунт заблокирован";
    if ([json[@"error"] isEqual:@"rate"]) return @"Слишком много попыток — подождите минуту";
    return [NSString stringWithFormat:@"Ошибка сервера (%ld)", (long)status];
}

+ (void)send:(NSMutableURLRequest *)req callback:(CXCApiCallback)callback {
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *netError) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        NSDictionary *json = nil;
        if (data.length) {
            id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            json = [parsed isKindOfClass:NSDictionary.class] ? parsed : nil;
        }
        callback(json, status, [self errorFor:json status:status netError:netError]);
    }] resume];
}

// для страницы лаунчера: любой метод, тело — JSON (у GET тела нет)
+ (void)request:(NSString *)method path:(NSString *)path token:(NSString *)token body:(NSDictionary *)body callback:(CXCApiCallback)callback {
    BOOL get = [method isEqualToString:@"GET"];
    [self send:[self requestFor:path method:method token:token body:get ? nil : (body ?: @{})] callback:callback];
}

+ (void)get:(NSString *)path token:(NSString *)token callback:(CXCApiCallback)callback {
    [self send:[self requestFor:path method:@"GET" token:token body:nil] callback:callback];
}

+ (void)post:(NSString *)path token:(NSString *)token body:(NSDictionary *)body callback:(CXCApiCallback)callback {
    [self send:[self requestFor:path method:@"POST" token:token body:body ?: @{}] callback:callback];
}

+ (NSDictionary *)sync:(NSMutableURLRequest *)req status:(NSInteger *)statusOut error:(NSString **)errorOut {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSDictionary *result;
    __block NSInteger status;
    __block NSString *error;
    [self send:req callback:^(NSDictionary *json, NSInteger st, NSString *err) {
        result = json;
        status = st;
        error = err;
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    if (statusOut) *statusOut = status;
    if (errorOut) *errorOut = error;
    return error ? nil : result;
}

+ (NSDictionary *)getSync:(NSString *)path token:(NSString *)token error:(NSString **)error {
    return [self sync:[self requestFor:path method:@"GET" token:token body:nil] status:nil error:error];
}

+ (NSDictionary *)postSync:(NSString *)path token:(NSString *)token body:(NSDictionary *)body status:(NSInteger *)status error:(NSString **)error {
    return [self sync:[self requestFor:path method:@"POST" token:token body:body ?: @{}] status:status error:error];
}

#pragma mark - Вход

+ (void)loginWithLogin:(NSString *)login password:(NSString *)password callback:(CXCApiCallback)callback {
    NSString *device = [NSString stringWithFormat:@"%@ (%@ %@)", UIDevice.currentDevice.name,
        UIDevice.currentDevice.systemName, UIDevice.currentDevice.systemVersion];
    if (device.length > 120) {
        device = [device substringToIndex:120];
    }
    [self post:@"/auth/login" token:nil body:@{
        @"login": login,
        @"password": password,
        @"device": device,
        @"twofa": @"poll"
    } callback:callback];
}

+ (void)poll2FA:(NSString *)challenge callback:(CXCApiCallback)callback {
    [self post:@"/auth/2fa" token:nil body:@{@"challenge": challenge} callback:callback];
}

+ (void)cancel2FA:(NSString *)challenge {
    [self post:@"/auth/2fa/cancel" token:nil body:@{@"challenge": challenge} callback:^(NSDictionary *j, NSInteger s, NSString *e) {}];
}

@end
