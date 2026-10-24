// Лаунчер CubeXCraft (SCRUM-363): экраны по дизайну — страница cxc-ui/index.html в WKWebView, всё остальное
// (вход, API сайта, сборка, JIT, запуск игры) — родной код. Приложение открывается сразу в него.
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CXCWebLauncherViewController : UIViewController
@end

// Корень окна: LauncherNavigationController (его код запуска игры) без своих панелей, внутри — лаунчер
UIViewController *CXCLauncherRoot(void);

NS_ASSUME_NONNULL_END
