// © 2026 CubeXCraft (https://www.cubexcraft.site). GPL-3.0 with additional terms (GPLv3 §7: attribution, origin, trademarks), see CUBEXCRAFT.md.
#import <CoreText/CoreText.h>

#import "CXCTouchControls.h"
#import "../LauncherPreferences.h"
#include "../glfw_keycodes.h"
#include "../utils.h"

// Цвета дизайна (ARGB); Amethyst читает их intValue — храним знаковыми, как его strokeColor = -1
#define CXC_BG          ((int)0xFF0B0509)
#define CXC_BG_HALF     ((int)0x800B0509)
#define CXC_RED         ((int)0xFFFF2A3C)
#define CXC_RED_35      ((int)0x55FF2A3C)
#define CXC_TEXT        ((int)0xFFF0E2E3)
#define CXC_YELLOW      ((int)0xFFFCEE0A)
#define CXC_YELLOW_DARK ((int)0xFF2B2703)
#define CXC_YELLOW_35   ((int)0x59FCEE0A)

// Скругление в процентах Amethyst: cornerRadius = min(w, h) / 200 * value
static CGFloat cxcRadius(CGFloat radiusPt, CGFloat w, CGFloat h) {
    return radiusPt * 200.0 / MIN(w, h);
}

static NSMutableDictionary *cxcButton(NSString *name, int keycode, CGFloat w, CGFloat h, NSString *x, NSString *y,
    BOOL inGame, BOOL inMenu) {
    return [@{
        @"name": name,
        @"keycodes": @[@(keycode), @0, @0, @0],
        @"dynamicX": x,
        @"dynamicY": y,
        @"width": @(w),
        @"height": @(h),
        @"opacity": @0.8,
        @"bgColor": @(CXC_BG),
        @"strokeColor": @(CXC_RED),
        @"strokeWidth": @1.5,
        @"cornerRadius": @(cxcRadius(6, w, h)),
        @"isToggle": @NO,
        @"isSwipeable": @NO,
        @"passThruEnabled": @NO,
        @"displayInGame": @(inGame),
        @"displayInMenu": @(inMenu),
        @"cxcStyle": @YES,
        @"textColor": @(CXC_TEXT)
    } mutableCopy];
}

// язык лаунчера (cubexcraft.lang), иначе системы
static BOOL cxcRussian(void) {
    NSString *lang = getPrefObject(@"cubexcraft.lang");
    if (![lang isKindOfClass:NSString.class] || lang.length == 0) {
        lang = [NSLocale.preferredLanguages.firstObject hasPrefix:@"ru"] ? @"ru" : @"en";
    }
    return [lang isEqualToString:@"ru"];
}

static NSString *cxcPx(CGFloat pt) {
    return [NSString stringWithFormat:@"px(%.2f)", pt];
}

void CXCPrepareTouchControls(UIWindow *window) {
    CGSize screen = window.bounds.size;
    CGFloat H = MIN(screen.width, screen.height);
    UIEdgeInsets insets = window.safeAreaInsets;
    // поле управления = безопасная зона окна игры (Amethyst считал её из портрета и без нижней полосы)
    setPrefObject(@"control.control_safe_area", NSStringFromUIEdgeInsets(UIEdgeInsetsMake(insets.top, insets.left, insets.bottom, insets.right)));

    BOOL ru = cxcRussian();
    NSString *lang = ru ? @"ru" : @"en";
    NSString *(^label)(NSString *, NSString *) = ^(NSString *r, NSString *e) {
        return (ru ? r : e).uppercaseString;
    };
    CGFloat (^pct)(CGFloat) = ^(CGFloat p) { return H * p / 100.0; };
    // от правого/нижнего края безопасной зоны
    NSString *(^fromRight)(CGFloat) = ^(CGFloat m) {
        return [NSString stringWithFormat:@"${screen_width} - ${width} - %@", cxcPx(m)];
    };
    NSString *(^fromBottom)(CGFloat) = ^(CGFloat m) {
        return [NSString stringWithFormat:@"${screen_height} - ${height} - %@", cxcPx(m)];
    };

    NSMutableArray *buttons = [NSMutableArray new];

    // справа внизу: прыжок, присесть, бег, выброс
    CGFloat jump = pct(26);
    NSMutableDictionary *b = cxcButton(label(@"Прыжок", @"Jump"), GLFW_KEY_SPACE, jump, jump,
        fromRight(pct(3)), fromBottom(pct(5)), YES, NO);
    b[@"bgColor"] = @(CXC_RED_35);
    b[@"strokeWidth"] = @2;
    b[@"cornerRadius"] = @100;
    b[@"cxcKeepWhenCollapsed"] = @YES;
    [buttons addObject:b];

    CGFloat crouch = pct(19);
    b = cxcButton(label(@"Присесть", @"Sneak"), GLFW_KEY_LEFT_SHIFT, crouch, crouch,
        fromRight(pct(31)), fromBottom(pct(5)), YES, NO);
    b[@"cornerRadius"] = @100;
    b[@"cxcKeepWhenCollapsed"] = @YES;
    [buttons addObject:b];

    CGFloat rowH = pct(13.4);
    b = cxcButton(label(@"Бег", @"Sprint"), GLFW_KEY_LEFT_CONTROL, pct(23), rowH,
        fromRight(pct(3)), fromBottom(pct(33)), YES, NO);
    b[@"isToggle"] = @YES;
    b[@"bgColor"] = @(CXC_YELLOW_DARK);
    b[@"strokeColor"] = @(CXC_YELLOW);
    b[@"textColor"] = @(CXC_YELLOW);
    b[@"toggleColor"] = @(CXC_YELLOW_35);
    b[@"cxcKeepWhenCollapsed"] = @YES;
    [buttons addObject:b];

    [buttons addObject:cxcButton(label(@"Выброс", @"Drop"), GLFW_KEY_Q, pct(20), rowH,
        fromRight(pct(31)), fromBottom(pct(33)), YES, NO)];

    // СКМ — взять блок под прицелом (владелец 25.10; у дизайнера кнопки нет): в ряд перед «Выброс», шаг 1,5 % H
    [buttons addObject:cxcButton(label(@"Взять", @"Pick"), SPECIALBTN_MOUSEMID, pct(20), rowH,
        fromRight(pct(52.5)), fromBottom(pct(33)), YES, NO)];

    // сверху по центру: «Скрыть» сворачивает кнопки, кроме ходьбы (у дизайнера — «Меню», владелец 25.10: «не пойму,
    // что делает кнопка меню», «скрытие, которое не убирает возможность ходить»); за ней группа, шаг 1,5 % H
    NSArray *group = @[
        @[label(@"Скрыть", @"Hide"), @(SPECIALBTN_TOGGLECTRL)],
        @[label(@"Чат", @"Chat"), @(GLFW_KEY_T)],
        @[label(@"Инвентарь", @"Inventory"), @(GLFW_KEY_E)],
        @[label(@"Игроки", @"Players"), @(GLFW_KEY_TAB)],
        @[label(@"Вид 1/3", @"View 1/3"), @(GLFW_KEY_F5)],
        // F3 — экран отладки: кадры, координаты (владелец 25.10: «верни кнопку дебаг-меню, чтоб скрывалась при скрытии»)
        @[@"F3", @(GLFW_KEY_F3)],
        @[label(@"Пауза", @"Pause"), @(GLFW_KEY_ESCAPE)]
    ];
    CGFloat groupW = pct(20), gap = pct(1.5);
    CGFloat total = group.count * groupW + (group.count - 1) * gap;
    // за группой — круглая «i» (подсказка по управлению); центруем всё вместе, чтобы влезало и на iPhone SE
    CGFloat totalAll = total + gap + rowH;
    for (NSUInteger i = 0; i < group.count; i++) {
        NSString *x = [NSString stringWithFormat:@"(${screen_width} - %@) / 2 + %@", cxcPx(totalAll), cxcPx(i * (groupW + gap))];
        b = cxcButton(group[i][0], [group[i][1] intValue], groupW, rowH, x, cxcPx(pct(3)), YES, i == 0);
        if (i == 0) {
            b[@"cxcAltName"] = label(@"Показать", @"Show");
        }
        if ([group[i][1] intValue] == GLFW_KEY_TAB) {
            b[@"isToggle"] = @YES;
            b[@"toggleColor"] = @(CXC_RED_35);
        }
        [buttons addObject:b];
    }

    // «i» — как работает управление (владелец 25.10: «кнопочку i, она должна быть заметна и скрываться по «Скрыть»»)
    b = cxcButton(@"i", SPECIALBTN_CXC_HELP, rowH, rowH,
        [NSString stringWithFormat:@"(${screen_width} - %@) / 2 + %@", cxcPx(totalAll), cxcPx(total + gap)], cxcPx(pct(3)), YES, NO);
    b[@"cornerRadius"] = @100;
    b[@"strokeWidth"] = @2;
    b[@"bgColor"] = @(CXC_YELLOW_DARK);
    b[@"strokeColor"] = @(CXC_YELLOW);
    b[@"textColor"] = @(CXC_YELLOW);
    b[@"cxcFontSize"] = @22;
    [buttons addObject:b];

    // в инвентаре и меню — «Назад» справа сверху
    [buttons addObject:cxcButton(label(@"Назад", @"Back"), GLFW_KEY_ESCAPE, pct(20), rowH,
        fromRight(pct(3)), cxcPx(pct(3)), NO, YES)];

    // слева внизу — джойстик ходьбы
    CGFloat stick = pct(36);
    NSMutableDictionary *joystick = cxcButton(@"", 0, stick, stick, cxcPx(pct(3)), fromBottom(pct(5)), YES, NO);
    joystick[@"bgColor"] = @(CXC_BG_HALF);
    joystick[@"thumbColor"] = @(CXC_RED_35);
    joystick[@"absolute"] = @NO;
    joystick[@"forwardLock"] = @NO;
    joystick[@"cxcKeepWhenCollapsed"] = @YES;

    NSDictionary *layout = @{
        @"version": @8,
        @"scaledAt": @(getPrefFloat(@"control.button_scale")),
        @"mControlDataList": buttons,
        @"mDrawerDataList": @[],
        @"mJoystickDataList": @[joystick]
    };
    // удержание пальца для ЛКМ (ломать, бить): 0,3 с вместо 0,4; тап дольше 0,25 с ПКМ уже не считается
    setPrefObject(@"control.press_duration", @300);

    NSString *path = [NSString stringWithFormat:@"%s/controlmap/cubexcraft.json", getenv("AME_HOME")];
    NSData *json = [NSJSONSerialization dataWithJSONObject:layout options:NSJSONWritingPrettyPrinted error:nil];
    if ([json writeToFile:path atomically:YES]) {
        setPrefObject(@"control.default_ctrl", @"cubexcraft.json");
    }
    NSLog(@"[CXC] управление: экран %.0f×%.0f, безопасная зона %@, %@", screen.width, screen.height,
        NSStringFromUIEdgeInsets(insets), lang);
}

// «i» в игре — как работает управление (владелец 25.10: «кнопочку i, где будет открываться, как работает управление
// на телефоне»). Поверх игры, касания в игру не уходят; закрывается «Понятно» или тапом мимо панели.
static const NSInteger CXC_HELP_TAG = 0xC1C1;

static UIColor *cxcColor(uint32_t rgb, CGFloat alpha) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0
        blue:(rgb & 0xFF) / 255.0 alpha:alpha];
}

@interface CXCHelpOverlay : UIView
@property(nonatomic, weak) UIView *panel;
@end

@implementation CXCHelpOverlay
- (void)cxcClose {
    [UIView animateWithDuration:0.15 animations:^{
        self.alpha = 0;
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}
- (void)cxcTapOutside:(UITapGestureRecognizer *)gesture {
    if (!CGRectContainsPoint(self.panel.frame, [gesture locationInView:self])) {
        [self cxcClose];
    }
}
// касания — только подсказке, не камере игры
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
@end

void CXCShowControlsHelp(UIView *host) {
    if ([host viewWithTag:CXC_HELP_TAG]) {
        return;
    }
    BOOL ru = cxcRussian();
    // @"#" — заголовок раздела
    NSArray<NSArray<NSString *> *> *rows = ru ? @[
        @[@"#", @"ЖЕСТЫ"],
        @[@"Палец по экрану", @"Обзор — повернуть камеру."],
        @[@"Тап", @"Поставить блок, открыть, использовать (ПКМ)."],
        @[@"Удержание", @"Ломать и бить (ЛКМ): держите палец на месте 0,3 с."],
        @[@"Тап двумя пальцами", @"Взять блок под прицелом в руку (СКМ)."],
        @[@"Тап по хотбару", @"Выбрать предмет в руку."],
        @[@"#", @"КНОПКИ"],
        @[@"Джойстик", @"Слева внизу — ходьба."],
        @[@"Прыжок", @"Прыгнуть; в воде — всплыть."],
        @[@"Присесть", @"Красться; не даёт упасть с края блока."],
        @[@"Бег", @"Включает и выключает бег — жёлтая, пока бег включён."],
        @[@"Выброс", @"Выбросить предмет из руки."],
        @[@"Взять", @"Взять блок под прицелом в руку."],
        @[@"Скрыть / Показать", @"Спрятать кнопки — остаются ходьба, прыжок, присесть и бег."],
        @[@"Чат", @"Открыть чат."],
        @[@"Инвентарь", @"Открыть инвентарь."],
        @[@"Игроки", @"Список игроков — включить и выключить."],
        @[@"Вид 1/3", @"Вид от первого или третьего лица."],
        @[@"F3", @"Экран отладки: кадры в секунду, координаты."],
        @[@"Пауза", @"Меню паузы и настройки."],
        @[@"Назад", @"В инвентаре и меню — закрыть окно."],
        @[@"i", @"Эта подсказка."]
    ] : @[
        @[@"#", @"GESTURES"],
        @[@"Swipe", @"Look around — turn the camera."],
        @[@"Tap", @"Place a block, open, use (right click)."],
        @[@"Hold", @"Break and attack (left click): keep the finger still for 0.3 s."],
        @[@"Two-finger tap", @"Pick the block you are looking at (middle click)."],
        @[@"Tap the hotbar", @"Pick the item to hold."],
        @[@"#", @"BUTTONS"],
        @[@"Joystick", @"Bottom left — walk."],
        @[@"Jump", @"Jump; in water — swim up."],
        @[@"Sneak", @"Sneak; keeps you from falling off edges."],
        @[@"Sprint", @"Turns sprinting on and off — yellow while it is on."],
        @[@"Drop", @"Drop the item in your hand."],
        @[@"Pick", @"Pick the block you are looking at."],
        @[@"Hide / Show", @"Hide the buttons — walking, jump, sneak and sprint stay."],
        @[@"Chat", @"Open the chat."],
        @[@"Inventory", @"Open the inventory."],
        @[@"Players", @"Player list — on and off."],
        @[@"View 1/3", @"First or third person view."],
        @[@"F3", @"Debug screen: frames per second, coordinates."],
        @[@"Pause", @"Pause menu and settings."],
        @[@"Back", @"In the inventory and menus — close the window."],
        @[@"i", @"This help."]
    ];

    CXCHelpOverlay *overlay = [[CXCHelpOverlay alloc] initWithFrame:host.bounds];
    overlay.tag = CXC_HELP_TAG;
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.backgroundColor = cxcColor(0x040204, 0.86);

    UIEdgeInsets safe = host.safeAreaInsets;
    CGRect area = UIEdgeInsetsInsetRect(host.bounds,
        UIEdgeInsetsMake(MAX(safe.top, 12), MAX(safe.left, 16), MAX(safe.bottom, 12), MAX(safe.right, 16)));
    CGFloat pw = MIN(area.size.width, 680), ph = area.size.height;
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(CGRectGetMidX(area) - pw / 2, area.origin.y, pw, ph)];
    panel.backgroundColor = cxcColor(0x0B0509, 0.97);
    panel.layer.borderColor = cxcColor(0xFF2A3C, 1).CGColor;
    panel.layer.borderWidth = 1;
    [overlay addSubview:panel];
    overlay.panel = panel;

    UILabel *title = [UILabel new];
    title.text = ru ? @"// КАК РАБОТАЕТ УПРАВЛЕНИЕ" : @"// HOW THE CONTROLS WORK";
    title.font = CXCControlFont(12);
    title.textColor = cxcColor(0xFCEE0A, 1);
    title.frame = CGRectMake(16, 12, pw - 32, 18);
    [panel addSubview:title];

    CGFloat footer = 52;
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 36, pw, ph - 36 - footer)];
    scroll.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    [panel addSubview:scroll];

    CGFloat nameW = MIN(170, pw * 0.3), x2 = 16 + nameW + 12, descW = pw - x2 - 16, y = 2;
    for (NSArray<NSString *> *row in rows) {
        if ([row[0] isEqualToString:@"#"]) {
            UILabel *head = [UILabel new];
            head.text = row[1];
            head.font = CXCControlFont(10);
            head.textColor = cxcColor(0xFF2A3C, 1);
            head.frame = CGRectMake(16, y + 8, pw - 32, 14);
            [scroll addSubview:head];
            y += 30;
            continue;
        }
        UILabel *name = [UILabel new];
        name.text = row[0];
        name.font = CXCControlFont(11);
        name.textColor = cxcColor(0xF0E2E3, 1);
        name.numberOfLines = 0;
        CGSize nameSize = [name sizeThatFits:CGSizeMake(nameW, CGFLOAT_MAX)];
        UILabel *desc = [UILabel new];
        desc.text = row[1];
        desc.font = [UIFont systemFontOfSize:13];
        desc.textColor = cxcColor(0xC4A8AC, 1);
        desc.numberOfLines = 0;
        CGSize descSize = [desc sizeThatFits:CGSizeMake(descW, CGFLOAT_MAX)];
        CGFloat rowH = MAX(nameSize.height, descSize.height);
        name.frame = CGRectMake(16, y, nameW, nameSize.height);
        desc.frame = CGRectMake(x2, y, descW, descSize.height);
        [scroll addSubview:name];
        [scroll addSubview:desc];
        UIView *line = [[UIView alloc] initWithFrame:CGRectMake(16, y + rowH + 6, pw - 32, 1)];
        line.backgroundColor = cxcColor(0x2A0810, 1);
        [scroll addSubview:line];
        y += rowH + 13;
    }
    scroll.contentSize = CGSizeMake(pw, y + 4);

    UIButton *ok = [UIButton buttonWithType:UIButtonTypeCustom];
    [ok setTitle:(ru ? @"ПОНЯТНО" : @"GOT IT") forState:UIControlStateNormal];
    ok.titleLabel.font = CXCControlFont(13);
    [ok setTitleColor:cxcColor(0xFFD6D9, 1) forState:UIControlStateNormal];
    ok.backgroundColor = cxcColor(0xFF2A3C, 0.12);
    ok.layer.borderColor = cxcColor(0xFF2A3C, 1).CGColor;
    ok.layer.borderWidth = 1.5;
    ok.frame = CGRectMake(pw - 16 - 160, ph - footer + 8, 160, 36);
    [ok addTarget:overlay action:@selector(cxcClose) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:ok];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:overlay action:@selector(cxcTapOutside:)];
    tap.cancelsTouchesInView = NO;
    [overlay addGestureRecognizer:tap];

    overlay.alpha = 0;
    [host addSubview:overlay];
    [UIView animateWithDuration:0.15 animations:^{
        overlay.alpha = 1;
    }];
}

UIFont *CXCControlFont(CGFloat size) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *url = [NSBundle.mainBundle URLForResource:@"JetBrainsMono" withExtension:@"ttf" subdirectory:@"cxc-ui/fonts"];
        if (url) {
            CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, NULL);
        }
    });
    // шрифт переменный: толщина — осью wght
    UIFontDescriptor *descriptor = [UIFontDescriptor fontDescriptorWithFontAttributes:@{
        UIFontDescriptorFamilyAttribute: @"JetBrains Mono",
        (NSString *)kCTFontVariationAttribute: @{@(0x77676874): @700}
    }];
    UIFont *font = [UIFont fontWithDescriptor:descriptor size:size];
    if (![font.familyName isEqualToString:@"JetBrains Mono"]) {
        font = [UIFont monospacedSystemFontOfSize:size weight:UIFontWeightBold];
    }
    return font;
}
