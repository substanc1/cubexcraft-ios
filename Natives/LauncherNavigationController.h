#import <UIKit/UIKit.h>

NSMutableArray<NSDictionary *> *localVersionList, *remoteVersionList;

@interface LauncherNavigationController : UINavigationController

@property(nonatomic) UIProgressView *progressViewMain, *progressViewSub;
@property(nonatomic) UILabel* progressText;

- (void)enterModInstallerWithPath:(NSString *)path hitEnterAfterWindowShown:(BOOL)hitEnter;
- (void)fetchLocalVersionList;
- (void)setInteractionEnabled:(BOOL)enable forDownloading:(BOOL)downloading;

// Лаунчер CubeXCraft (CXCWebLauncherViewController): события запуска вместо системных окон — prepError, jit
@property(nonatomic, copy) void (^cxcEvents)(NSString *type, NSDictionary *data);
- (void)startDownloadForVersionId:(NSString *)versionId;
- (NSProgress *)cxcTaskProgress;
- (void)cxcRetryJIT;
- (void)cxcCancel;

@end
