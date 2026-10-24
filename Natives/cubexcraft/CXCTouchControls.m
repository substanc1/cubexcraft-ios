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

static NSString *cxcPx(CGFloat pt) {
    return [NSString stringWithFormat:@"px(%.2f)", pt];
}

void CXCPrepareTouchControls(UIWindow *window) {
    CGSize screen = window.bounds.size;
    CGFloat H = MIN(screen.width, screen.height);
    UIEdgeInsets insets = window.safeAreaInsets;
    // поле управления = безопасная зона окна игры (Amethyst считал её из портрета и без нижней полосы)
    setPrefObject(@"control.control_safe_area", NSStringFromUIEdgeInsets(UIEdgeInsetsMake(insets.top, insets.left, insets.bottom, insets.right)));

    NSString *lang = getPrefObject(@"cubexcraft.lang");
    if (![lang isKindOfClass:NSString.class] || lang.length == 0) {
        lang = [NSLocale.preferredLanguages.firstObject hasPrefix:@"ru"] ? @"ru" : @"en";
    }
    BOOL ru = [lang isEqualToString:@"ru"];
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
        @[label(@"Пауза", @"Pause"), @(GLFW_KEY_ESCAPE)]
    ];
    CGFloat groupW = pct(20), gap = pct(1.5);
    CGFloat total = group.count * groupW + (group.count - 1) * gap;
    for (NSUInteger i = 0; i < group.count; i++) {
        NSString *x = [NSString stringWithFormat:@"(${screen_width} - %@) / 2 + %@", cxcPx(total), cxcPx(i * (groupW + gap))];
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
