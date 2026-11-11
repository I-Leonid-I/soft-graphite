# Проверка приватной libkgapi

Тесты используют FakeNetworkAccessManager и синтетические данные KDE, без Google
аккаунта и без сетевого CRUD. Нужны Qt6Test и зависимости сборки libkgapi.

Сначала выполните изолированный `launch.py --build-only` в копии core/ внутри
рабочей папки проекта (не в рабочей установке), задав
`SOFT_GRAPHITE_GOOGLE_BUILD_DIR` на подкаталог `scratch/`.
В скачанной source/ замените `autotests/core/fetchjobtest.cpp` этим файлом и
скопируйте mock-fixtures: `event*` в `autotests/calendar/data/`, `tasks*` в
`autotests/tasks/data/`. Fixtures сохраняют showHidden/фильтры на странице 2 и
эквивалентную сериализацию RRULE через KCalendarCore.

Переконфигурируйте ту же сборку с `-DBUILD_TESTING=ON` и соберите цели:
`fetchjobtest`, `event{create,delete,fetch,modify}jobtest`,
`task{create,delete,fetch,modify}jobtest`.
При запуске каждого бинарника обязательно задайте:

- `LD_LIBRARY_PATH` — bin/ свежей приватной сборки (иначе можно проверить системную Core);
- `SOFT_GRAPHITE_BUDGET_TEST_DIR` — отдельный новый подкаталог scratch/, чтобы тест
  не менял рабочий счётчик API;
- `QT_QPA_PLATFORM=offscreen`, `TMPDIR` — каталог scratch/ проекта.

`fetchjobtest` дополнительно удерживает 150 завершённых jobs и проверяет освобождение
QNetworkAccessManager/restart, а также отсутствие HTTP-повтора после 403/429/503.

`budget-test.cpp` — отдельный тест только заголовка `softgraphitebudget_p.h` из
пропатченной source/src/core. Соберите с C++20 и флагами pkg-config Qt6Core.
Без параметров проверяет пределы 15000 чтений/1000 записей; `--after-restart`
в новом процессе с тем же test-dir проверяет сохранение лимита. В другом новом
test-dir сначала `--pause`, затем новым процессом `--check-pause` проверяют паузу
и сохранение её после restart. Тест не отправляет запросов в сеть.

Не удаляйте рабочие файлы квоты; удалять можно только отдельные тестовые каталоги.
