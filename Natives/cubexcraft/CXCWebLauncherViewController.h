// © 2026 CubeXCraft (https://www.cubexcraft.site). GPL-3.0 with additional terms (GPLv3 §7: attribution, origin, trademarks), see CUBEXCRAFT.md.
// Лаунчер CubeXCraft (SCRUM-363): экраны по дизайну — страница cxc-ui/index.html в WKWebView, всё остальное
// (вход, API сайта, сборка, JIT, запуск игры) — родной код. Приложение открывается сразу в него.
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CXCWebLauncherViewController : UIViewController
@end

// Корень окна: LauncherNavigationController (его код запуска игры) без своих панелей, внутри — лаунчер
UIViewController *CXCLauncherRoot(void);

// Перед экраном игры: повернуть окно горизонтально и дождаться поворота (iPhone), затем done
void CXCRotateToLandscape(UIWindow *window, void (^done)(void));

NS_ASSUME_NONNULL_END
