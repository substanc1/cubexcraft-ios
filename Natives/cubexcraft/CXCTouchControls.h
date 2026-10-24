// Управление CubeXCraft в игре (SCRUM-363): раскладка по дизайну touch-controls.json — размеры и отступы в % высоты
// экрана, отступы от безопасной зоны. Пишется перед каждым запуском игры под текущий экран и язык.
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// controlmap/cubexcraft.json + control.default_ctrl и control.control_safe_area; window — уже горизонтальное окно игры
void CXCPrepareTouchControls(UIWindow *window);

// JetBrains Mono 700 из приложения (подписи кнопок), запасной — моноширинный системный
UIFont *CXCControlFont(CGFloat size);

NS_ASSUME_NONNULL_END
