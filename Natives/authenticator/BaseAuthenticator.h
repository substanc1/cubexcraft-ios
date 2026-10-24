#import "Foundation/Foundation.h"

typedef void(^Callback)(id status, BOOL success);

@interface BaseAuthenticator : NSObject

@property(class) BaseAuthenticator *current;

@property NSMutableDictionary *authData;

+ (id)loadSavedName:(NSString *)name;
+ (NSDictionary *)tokenDataOfProfile:(NSString *)profile;

- (id)initWithInput:(NSString *)string;
- (void)loginWithCallback:(Callback)callback;
- (void)refreshTokenWithCallback:(Callback)callback;
- (BOOL)saveChanges;

@end

@interface LocalAuthenticator : BaseAuthenticator
@end

@interface MicrosoftAuthenticator : BaseAuthenticator

+ (void)clearTokenDataOfProfile:(NSString *)profile;

@end

// Аккаунт CubeXCraft (сайт cubexcraft.site): input — @{login, password}
@interface CubeXCraftAuthenticator : BaseAuthenticator

@property(nonatomic, copy) void (^statusHandler)(NSString *status);   // «подтвердите в Telegram» и т. п.
@property(atomic) BOOL cancelled;
@property(atomic) NSInteger lastStatus;   // HTTP-код последней ошибки входа (0 — нет связи)

- (id)initWithLogin:(NSString *)login password:(NSString *)password;
- (NSString *)launcherToken;
- (void)logout;

@end
