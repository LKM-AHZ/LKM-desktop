# quick_actions 1.1.1

Published source: https://pub.dev/packages/quick_actions/versions/1.1.1
Archive SHA-256: `1d3397c1ce5cd91b732c675bc82571d316d6de8241d774927b4ea3680c860e1a`.

Native community source: https://gitcode.com/CPF-Flutter/flutter_packages.git
Fixed commit: `8443fcb8a96f707750206cf25d7c9361869b3ac1`; inspected branch `br_quick_actions-v1.1.0_ohos_dev`.

Published Dart API and original Android/iOS declarations are unchanged.
Adds ../quick_actions_ohos native backend using current interface 1.1.0's
standard method channel, without legacy Pigeon or a forked interface. Static
profile entries configure the four shared app shortcuts; API20+ shortcutManager
performs real visibility updates and clear. Unknown runtime IDs fail because
this public API cannot create arbitrary dynamic shortcut definitions. Static
labels/icons are profile resources; runtime label/icon changes are not promised.
Cold launches are consumed once, warm launches use the same shared callback.
Host EntryAbility forwards flutter_quick_action from onCreate/onNewWant; real
launcher rendering and lifecycle require device acceptance.

Existing licenses retained; additional native Apache license is bundled via
Flutter licenses. Examples/tests/build caches omitted.
