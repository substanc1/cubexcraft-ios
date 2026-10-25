// © 2026 CubeXCraft (https://www.cubexcraft.site). GPL-3.0 with additional terms (GPLv3 §7: attribution, origin, trademarks), see CUBEXCRAFT.md.
// Аккаунт CubeXCraft: вход логином/паролем сайта (+ подтверждение в Telegram, если привязан), токен лаунчера —
// в связке ключей, перед каждым запуском — свежий токен игры (POST /game/session), как у десктопа.
#import "BaseAuthenticator.h"
#import "../cubexcraft/CXCApi.h"

@implementation CubeXCraftAuthenticator

// "8f3c…" (32 символа) → "8f3c….-….-….-….-…."
static NSString *dashedUUID(NSString *uuid) {
    if (uuid.length != 32) {
        return uuid;
    }
    return [NSString stringWithFormat:@"%@-%@-%@-%@-%@",
        [uuid substringWithRange:NSMakeRange(0, 8)], [uuid substringWithRange:NSMakeRange(8, 4)],
        [uuid substringWithRange:NSMakeRange(12, 4)], [uuid substringWithRange:NSMakeRange(16, 4)],
        [uuid substringFromIndex:20]];
}

- (id)initWithLogin:(NSString *)login password:(NSString *)password {
    self = [self initWithInput:login];
    self.authData[@"input"] = @{@"login": login, @"password": password};
    return self;
}

- (void)report:(NSString *)status {
    if (self.statusHandler) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusHandler(status);
        });
    }
}

- (void)acceptLogin:(NSDictionary *)json callback:(Callback)callback {
    NSDictionary *user = json[@"user"];
    NSString *username = user[@"username"];
    [CXCApi setLauncherToken:json[@"accessToken"] for:username];
    self.authData[@"type"] = @"cubexcraft";
    self.authData[@"username"] = username;
    self.authData[@"profileId"] = dashedUUID([user[@"uuid"] stringByReplacingOccurrencesOfString:@"-" withString:@""]);
    self.authData[@"expiresAt"] = @0;
    self.authData[@"profilePicURL"] = [NSString stringWithFormat:@"%@/texture/skin/%@.png", CXC_SITE, username];
    // токен игры берётся перед запуском; до этого — заглушка
    self.authData[@"accessToken"] = self.authData[@"accessToken"] ?: @"0";
    [self.authData removeObjectForKey:@"input"];
    callback(nil, [super saveChanges]);
}

- (void)wait2FA:(NSString *)challenge bot:(NSString *)bot until:(NSDate *)deadline callback:(Callback)callback {
    if (self.cancelled) {
        [CXCApi cancel2FA:challenge];
        callback(@"Вход отменён", NO);
        return;
    }
    if ([deadline timeIntervalSinceNow] < 0) {
        callback(@"Время на подтверждение вышло — попробуйте ещё раз", NO);
        return;
    }
    [CXCApi poll2FA:challenge callback:^(NSDictionary *json, NSInteger status, NSString *error) {
        if (error) {
            self.lastStatus = status;
            callback(error, NO);
        } else if (json[@"accessToken"]) {
            [self acceptLogin:json callback:callback];
        } else {
            [self wait2FA:challenge bot:bot until:deadline callback:callback];
        }
    }];
}

- (void)loginWithCallback:(Callback)callback {
    NSDictionary *input = self.authData[@"input"];
    [CXCApi loginWithLogin:input[@"login"] password:input[@"password"] callback:^(NSDictionary *json, NSInteger status, NSString *error) {
        if (error) {
            self.lastStatus = status;
            callback(error, NO);
            return;
        }
        NSDictionary *twofa = json[@"twofa"];
        if (twofa) {
            NSString *bot = twofa[@"bot"] ?: @"@CubeXCraft_2FA_bot";
            [self report:[NSString stringWithFormat:@"Подтвердите вход в Telegram: %@ → «Это я»", bot]];
            NSTimeInterval ttl = [twofa[@"expiresIn"] doubleValue] ?: 300;
            [self wait2FA:twofa[@"challenge"] bot:bot until:[NSDate dateWithTimeIntervalSinceNow:ttl] callback:callback];
            return;
        }
        if (!json[@"accessToken"]) {
            callback(@"Сервер не выдал токен — попробуйте ещё раз", NO);
            return;
        }
        [self acceptLogin:json callback:callback];
    }];
}

// Перед запуском: свежий токен игры (7 дней) — его видят аргументы процесса, токен лаунчера туда не идёт
- (void)refreshTokenWithCallback:(Callback)callback {
    NSString *username = self.authData[@"username"];
    NSString *token = [CXCApi launcherTokenFor:username];
    if (!token) {
        callback(@"Войдите в аккаунт CubeXCraft заново", NO);
        return;
    }
    [self report:@"Вход в CubeXCraft…"];
    [self requestGameSession:token attempt:0 callback:callback];
}

- (void)requestGameSession:(NSString *)token attempt:(int)attempt callback:(Callback)callback {
    [CXCApi post:@"/game/session" token:token body:nil callback:^(NSDictionary *json, NSInteger status, NSString *error) {
        if (status == 401 && [json[@"error"] isEqual:@"2fa"] && attempt < 6) {
            // раз в 7 дней сессию надо подтвердить в боте; сервер ждёт до 45 с на каждом запросе
            [self report:@"Подтвердите вход в Telegram-боте CubeXCraft"];
            [self requestGameSession:token attempt:attempt + 1 callback:callback];
            return;
        }
        if (status == 401 || status == 403) {
            [CXCApi setLauncherToken:nil for:self.authData[@"username"]];
            callback(error ?: @"Войдите в аккаунт CubeXCraft заново", NO);
            return;
        }
        if (error || !json[@"accessToken"]) {
            callback(error ?: @"Сервер не выдал токен игры", NO);
            return;
        }
        self.authData[@"accessToken"] = json[@"accessToken"];
        self.authData[@"profileId"] = dashedUUID(json[@"uuid"]);
        self.authData[@"username"] = json[@"username"] ?: self.authData[@"username"];
        callback(nil, [super saveChanges]);
    }];
}

- (NSString *)launcherToken {
    return [CXCApi launcherTokenFor:self.authData[@"username"]];
}

- (void)logout {
    NSString *token = self.launcherToken;
    if (token) {
        [CXCApi post:@"/auth/logout" token:token body:nil callback:^(NSDictionary *j, NSInteger s, NSString *e) {}];
    }
    [CXCApi setLauncherToken:nil for:self.authData[@"username"]];
}

@end
