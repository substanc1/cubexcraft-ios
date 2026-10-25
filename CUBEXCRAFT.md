# CubeXCraft для iPhone

Лаунчер проекта [CubeXCraft](https://www.cubexcraft.site) для iPhone и iPad: вход в аккаунт CubeX, установка мобильной
сборки CubeXTech с серверов CubeXCraft и запуск игры.

Это модифицированная версия **Angel Aura Amethyst (iOS)** (https://github.com/AngelAuraMC/Amethyst-iOS), основанной на
PojavLauncher и Boardwalk. Распространяется по **GNU GPL v3.0** (файл `LICENSE`), как требует исходный проект.
Изменения CubeXCraft начались в октябре 2026 года: всё после коммита `9212a189` в истории этого репозитория.

## Лицензия и авторы
- Всё приложение, включая части CubeXCraft, распространяется по GPL-3.0. Исходный код — в этом репозитории; исходники каждой
  выложенной сборки лежат на сайте рядом с ней (`CubeXCraft-ios-<версия>-src.tar.gz`).
- Копирайты авторов Amethyst, PojavLauncher и сторонних компонентов сохранены (см. `README.md`, раздел про сторонние компоненты).
- Шрифты интерфейса (Unbounded, JetBrains Mono, Manrope) — SIL OFL 1.1, тексты лицензий в `Natives/resources/cxc-ui/fonts/`.
- Minecraft — товарный знак Mojang AB / Microsoft. Проект с Mojang и Microsoft не связан, файлов игры в репозитории нет.

## Дополнительные условия для частей CubeXCraft (GPLv3, пункт 7)
Части CubeXCraft — это файлы с шапкой CubeXCraft, `Natives/cubexcraft/`, `Natives/resources/cxc-ui/` и
`Natives/authenticator/CubeXCraftAuthenticator.m`. Они © 2026 CubeXCraft и распространяются по GPL-3.0 с такими условиями:
1. **(7b) Авторство.** Сохранять шапки CubeXCraft в этих файлах и указание авторов в разделе «О приложении».
2. **(7c) Происхождение.** Изменённую версию нужно явно помечать как изменённую и не выдавать за официальное приложение
   CubeXCraft: сменить название, идентификатор `site.cubexcraft.ios` и иконку.
3. **(7e) Товарные знаки.** Права на названия «CubeXCraft», «CubeX», «CubeXTech», их логотипы, иконки и другую графику
   проекта эта лицензия не даёт. Из изменённой версии их нужно убрать.

Официальные сборки — только с https://www.cubexcraft.site (через установщик CubeXCraft Installer). Доступ к аккаунтам,
API и игровым серверам CubeXCraft этой лицензией не предоставляется — он регулируется правилами CubeXCraft на сайте.
Уязвимости — см. `SECURITY.md`.

## Additional terms for the CubeXCraft parts (English)
The CubeXCraft parts listed above are © 2026 CubeXCraft and licensed under GPL-3.0 with these additional terms under
section 7: (b) keep the CubeXCraft copyright headers and the credits in the About section; (c) mark modified versions as
modified and do not present them as the official CubeXCraft app — change the name, the bundle id `site.cubexcraft.ios` and
the icon; (e) no rights are granted to the names «CubeXCraft», «CubeX», «CubeXTech», their logos, icons or other brand
artwork. Official builds come only from https://www.cubexcraft.site. Access to CubeXCraft accounts, the API and the game
servers is not part of this license.
