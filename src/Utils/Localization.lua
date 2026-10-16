local _, addon = ...

if not addon:SupportsModernFeatures() then
    -- Existing provider controls retain their original English text. Modern
    -- saved language preferences must not affect or mutate a legacy client.
    function addon:Translate(text, ...)
        if select("#", ...) > 0 then return string.format(text, ...) end
        return text
    end
    return
end

-- English source strings are also the fallback. Locale affects presentation
-- only: provider IDs, condition keys, profiles and spell/item IDs stay stable.
local russian = {
    ["None available"] = "Нет доступных",
    ["No provider selected"] = "Провайдер не выбран",
    ["Provider: %s"] = "Провайдер: %s",
    ["Click for providers and settings."] = "Нажмите, чтобы выбрать провайдера или открыть настройки.",
    ["Drag to move around the minimap."] = "Перетаскивайте значок вокруг миникарты.",
    ["Providers"] = "Провайдеры",
    ["Current: %s"] = "Выбран: %s",
    ["No providers available."] = "Нет доступных провайдеров.",
    ["Enable a supported addon or use Assisted Combat."] = "Включите поддерживаемый аддон или используйте Assisted Combat.",
    ["Priority actions..."] = "Приоритеты...",
    ["Settings..."] = "Настройки...",
    ["Settings"] = "Настройки",
    ["Language"] = "Язык",
    ["Automatic"] = "Автоматически",
    ["Choose a supported language."] = "Выберите русский, английский или автоматический выбор языка.",
    ["Providers cannot be changed in combat. Try again after combat."] = "Сменить провайдера можно после боя.",
    ["This provider is no longer available. Choose another provider or reload the UI."] = "Провайдер недоступен. Выберите другой или перезагрузите интерфейс.",
    ["This provider could not start. Choose another provider or reload the UI."] = "Не удалось запустить провайдера. Выберите другой или перезагрузите интерфейс.",
    ["The provider could not be selected. Try again."] = "Не удалось выбрать провайдера. Попробуйте ещё раз.",
    ["Priority actions"] = "Приоритеты",
    ["Enable priority actions"] = "Включить приоритеты",
    ["Drag spells or items here."] = "Перетаскивайте сюда заклинания и предметы.",
    ["Priority: left to right"] = "Приоритет: слева направо",
    ["Add action"] = "Добавить",
    ["Add priority action"] = "Добавить действие",
    ["Action conditions"] = "Условия действия",
    ["If you want more conditions, try our new product"] = "Если вы хотите больше условий, попробуйте наш новый продукт",
    ["Press Ctrl+C to copy the link."] = "Нажмите Ctrl+C, чтобы скопировать ссылку.",
    ["Close"] = "Закрыть",
    ["Action"] = "Действие",
    ["Action %d"] = "Действие %d",
    ["Provider"] = "Провайдер",
    ["Spell"] = "Заклинание",
    ["Item"] = "Предмет",
    ["spell"] = "заклинание",
    ["item"] = "предмет",
    ["Add"] = "Добавить",
    ["Cancel"] = "Отмена",
    ["Done"] = "Готово",
    ["%d actions"] = "Действий: %d",
    ["%d action"] = "Действий: %d",
    ["Actions: %d"] = "Действий: %d",
    ["Priority %d  |  %s ID: %d"] = "Приоритет %d  |  %s ID: %d",
    ["%s  |  %s ID: %d"] = "%s  |  %s ID: %d",
    ["Rotation provider: %s"] = "Провайдер: %s",
    ["Runs after your priority actions when none of them applies."] = "Используется, когда ни одно из ваших приоритетных действий не подходит.",
    ["Fixed final action. Choose a provider from the minimap menu."] = "Всегда стоит в конце. Выбрать провайдера можно в меню миникарты.",
    ["Click to edit conditions. Drag to move."] = "Нажмите для настройки условий. Перетаскивайте для смены приоритета.",
    ["Uncheck to disable. Right-click to remove."] = "Снимите галочку, чтобы отключить. Правая кнопка — удалить.",
    ["Include this action in your priority."] = "Включить это действие.",
    ["Remove this action from your priority."] = "Удалить это действие.",
    ["Add a spell or item before the rotation provider."] = "Добавить заклинание или предмет перед провайдером.",
    ["Use + or drop your first spell or item here."] = "Нажмите + или перетащите сюда заклинание либо предмет.",
    ["Drag an individual spell or item here. Flyouts and pet abilities cannot be added."] = "Перетащите отдельное заклинание или предмет. Выпадающие списки и способности питомца не поддерживаются.",
    ["This action could not be added."] = "Не удалось добавить действие.",
    ["Enter a positive whole-number ID."] = "Введите целый ID больше нуля.",
    ["No data found. Check the ID and try again."] = "Данные не найдены. Проверьте ID и попробуйте ещё раз.",
    ["Toggle Major Cooldowns"] = "Основные мощные способности",
    ["Toggle Minor Cooldowns"] = "Дополнительные мощные способности",
    ["Toggle Interrupts"] = "Прерывания",
    ["Toggle Defensives"] = "Защитные способности",
    ["Toggle Potions"] = "Зелья",
    ["Toggle %s"] = "Переключить: %s",
    ["Choose a spell or item and enter a positive whole-number ID."] = "Выберите заклинание или предмет и введите целый ID больше нуля.",
    ["That action is already in this profile."] = "Это действие уже добавлено.",
    ["This action is already in your priority. Drag its icon to move it."] = "Действие уже добавлено. Перетащите его значок, чтобы изменить приоритет.",
    ["No data found for that ID. Try again after the client loads it."] = "Данные для этого ID ещё не загружены. Попробуйте ещё раз.",
    ["No data found for that ID."] = "Данные для этого ID не найдены.",
    ["Choose a whole-number priority position."] = "Введите целую позицию в списке приоритетов.",
    ["That action is not in this profile."] = "Этого действия нет в профиле.",
    ["Choose a whole-number move distance."] = "Введите целое число позиций для перемещения.",
    ["That action is already at the edge of the list."] = "Действие уже находится на краю списка.",
    ["Condition support is unavailable."] = "Условия недоступны.",
    ["The conditions could not be applied."] = "Не удалось применить условия.",
    ["Check the condition values."] = "Проверьте значения условий.",
    ["Unavailable condition"] = "Недоступное условие",
    ["Uncheck this condition to remove it."] = "Снимите галочку, чтобы удалить это условие.",
    ["This condition is unavailable on this client. The action will be skipped."] = "Это условие недоступно в вашей версии игры. Действие будет пропущено.",
    ["This version of WoW cannot check this condition. While it is checked, this action will not be suggested."] = "Эта версия WoW не может проверить условие. Пока оно включено, действие не предлагается.",
    ["In combat"] = "В бою",
    ["Enemy target"] = "Враждебная цель",
    ["Health"] = "Здоровье",
    ["Player resource"] = "Ресурс",
    ["Aura (unstabile)"] = "Аура (unstabile)",
    ["In range"] = "В радиусе",
    ["Proc"] = "Прок",
    ["Interrupt"] = "Прерывание",
    ["Delay after success"] = "Пауза после успеха",
    ["Usage limit"] = "Лимит применений",
    ["Enemies count"] = "Число врагов",
    ["Not mounted"] = "Не на транспорте",
    ["Player"] = "Игрок",
    ["Pet"] = "Питомец",
    ["Mouseover"] = "Курсор",
    ["Target"] = "Цель",
    ["Present"] = "Есть",
    ["Absent"] = "Нет",
    ["Unit"] = "Кого проверять",
    ["Comparison"] = "Сравнение",
    ["Percent"] = "Процент",
    ["Aura state"] = "Наличие ауры",
    ["Aura spell ID"] = "ID ауры",
    ["Seconds"] = "Секунды",
    ["Allowed uses"] = "Число применений",
    ["Window (ms)"] = "Период (мс)",
    ["Count per target"] = "Считать отдельно для каждой цели",
    ["Enemies"] = "Враги",
    ["per target"] = "на цель",
    ["s"] = "с",
    ["ms"] = "мс",
    ["uses /"] = "раз /",
    ["enemies"] = "врагов",
    ["Conditions must be a list."] = "Условия должны быть списком.",
    ["Use at most 24 conditions per action."] = "Для действия можно задать не более 24 условий.",
    ["Conditions must be a consecutive list."] = "В списке условий не должно быть пропусков.",
    ["Invalid condition."] = "Некорректное условие.",
    ["Unknown condition type."] = "Неизвестное условие.",
    ["Condition settings must be readable."] = "Настройки условия недоступны.",
    ["%s must be %s-%s%s."] = "Поле «%s»: от %s до %s%s.",
    [" (whole numbers)"] = " (целое число)",
    ["Choose a valid %s."] = "Выберите значение для поля «%s».",
    ["%s must be on or off."] = "Поле «%s» должно быть включено или выключено.",
    ["%s: %s to %s"] = "%s: от %s до %s",
    ["Only suggest this action while you are in combat."] = "Предлагать действие, только когда вы находитесь в бою.",
    ["Only suggest this action when your current target exists, is alive, and can be attacked."] = "Ваша текущая цель должна существовать, быть живой и доступной для атаки.",
    ["Choose whose health to check and a percentage. For example, Player < 50 requires your health to be below 50%. The selected character or pet must be alive and present."] = "Выберите, чьё здоровье проверять, и укажите процент. Например, Игрок < 50 — ваше здоровье ниже 50%. Курсор — цель под указателем мыши. Выбранная цель или питомец должны существовать и быть живы.",
    ["Check how full your main resource bar is, such as mana or energy. For example, >= 50 requires at least half of your maximum resource. The number is a percentage, not resource points."] = "Проверяет запас основного ресурса, например маны или энергии. >= 50 — осталось не менее половины максимума. Значение задаётся в процентах.",
    ["Choose who to check and enter the spell ID of a buff or debuff. Present requires that aura; Absent requires it to be missing. The aura ID can differ from the spell you cast. Auras from any caster count. Experimental: if WoW hides the aura data or the selected character or pet is unavailable, neither mode passes. Some clients only support checking Player."] = "Выберите цель и введите ID баффа или дебаффа. Есть — аура должна присутствовать; Нет — отсутствовать. Курсор — цель под указателем мыши. ID ауры может отличаться от ID заклинания. Учитываются ауры от любого персонажа. Экспериментально: если игра скрывает данные или цель недоступна, оба режима не срабатывают. В некоторых версиях игры можно проверить только игрока.",
    ["Only suggest this spell or item when your current target is within its range. Actions with no range requirement pass this condition."] = "Текущая цель должна находиться в радиусе действия заклинания или предмета. Для действий без ограничения дальности условие выполнено.",
    ["Only suggest this action while WoW shows the proc glow for its spell. For an item, this checks the spell used by that item."] = "Действие предлагается, пока игра подсвечивает его заклинание как прок. Для предмета проверяется заклинание, которое он применяет.",
    ["Only suggest this action while your living enemy target is casting or channeling a spell that can be interrupted. The target must also be within this action's range. Choose an action that can interrupt if you want to stop the cast."] = "Живая враждебная цель должна применять заклинание, которое можно прервать, и находиться в радиусе действия. Чтобы остановить заклинание, добавьте способность прерывания.",
    ["Wait the chosen number of seconds after you successfully use this action before suggesting it again. A cancelled or interrupted cast does not start the wait. Set 0 for no delay."] = "После успешного применения действие не предлагается указанное число секунд. Отмена или прерывание заклинания не запускают паузу. 0 — без паузы.",
    ["Stop suggesting this action after the chosen number of uses within the time window (1000 ms = 1 second). For example, 2 uses / 5000 ms blocks suggestions after two uses in the last 5 seconds. A cast counts as soon as it starts, even if interrupted. Enable per target for a separate count on each target. Set allowed uses to 0 to block this action."] = "Ограничивает число применений за выбранный период. 1000 мс = 1 секунда. Например, 2 раза / 5000 мс — не более двух применений за последние 5 секунд. Применение считается с начала, даже если его прервали. «На цель» ведёт отдельный счёт для каждой цели. Лимит 0 блокирует действие.",
    ["Check the number of enemies within this action's range. For example, >= 3 requires three or more enemies. Counts your living enemy target and other enemies detected in combat. If the full count is unknown, only checks using > or >= can pass."] = "Проверяет число врагов в радиусе действия. Например, >= 3 — три врага или больше. Учитываются живая враждебная цель и другие обнаруженные в бою враги. Если точное число неизвестно, могут сработать только проверки > и >=.",
    ["Only suggest this action when you are not riding a mount."] = "Действие предлагается, только когда вы не на транспорте.",
}

local choices = { auto = true, enUS = true, ruRU = true }

function addon:GetLanguage()
    local language = self:GetSettings().language
    return type(language) == "string" and choices[language] and language or "auto"
end

function addon:GetEffectiveLocale()
    local language = self:GetLanguage()
    if language ~= "auto" then return language end
    -- Addons can read the WoW interface locale, not the operating system's
    -- locale. Keep the default automatic so a client-language change follows it.
    return type(GetLocale) == "function" and GetLocale() == "ruRU" and "ruRU" or "enUS"
end

function addon:Translate(text, ...)
    if type(text) ~= "string" then return tostring(text or "") end
    local translated = self:GetEffectiveLocale() == "ruRU" and russian[text] or text
    translated = translated or text
    if select("#", ...) > 0 then return string.format(translated, ...) end
    return translated
end

function addon:SetLanguage(language)
    if type(language) ~= "string" or not choices[language] then return false, self:Translate("Choose a supported language.") end
    if self:GetLanguage() == language then return true end
    self:GetSettings().language = language
    self:SendMessage("WOWHAC_LANGUAGE_CHANGED", self:GetEffectiveLocale())
    return true
end
