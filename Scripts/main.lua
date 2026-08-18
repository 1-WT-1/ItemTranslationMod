local _print = print
local print = function(msg)
    _print(tostring(msg) .. "\n")
end

local ModVersion = "1.4.0"
print(string.format("[ItemTranslationMod] v%s Initializing...", ModVersion))

local ItemTranslations = {}
local ItemTranslationsLower = {}
local SearchReplacements = {}
local TranslationCache = {}
local TranslationCacheSize = 0
local MAX_CACHE_SIZE = 1000
local SearchStringCache = {}

local CurrentLocale = ""
local DebugMode = false
local SearchLanguage = "both"

local function ProcessBlockComments(line, inBlockComment)
    if inBlockComment then
        local endIdx = string.find(line, "*/", 1, true)
        if endIdx then
            inBlockComment = false
            line = string.sub(line, endIdx + 2)
        else
            return "", true
        end
    end
    
    while true do
        local startIdx = string.find(line, "/*", 1, true)
        if not startIdx then break end
        
        local endIdx = string.find(line, "*/", startIdx + 2, true)
        if endIdx then
            line = string.sub(line, 1, startIdx - 1) .. string.sub(line, endIdx + 2)
        else
            inBlockComment = true
            line = string.sub(line, 1, startIdx - 1)
            break
        end
    end
    
    return line, inBlockComment
end

local function LoadSettings()
    local filepath = "ue4ss/Mods/ItemTranslationMod/settings.txt"
    local file = io.open(filepath, "r")
    if file then
        local isFirstLine = true
        local inBlockComment = false
        for line in file:lines() do
            if isFirstLine then
                if string.sub(line, 1, 3) == "\239\187\191" then
                    line = string.sub(line, 4)
                end
                isFirstLine = false
            end

            line, inBlockComment = ProcessBlockComments(line, inBlockComment)

            local isBlank = string.match(line, "^%s*$")
            local isComment = string.match(line, "^%s*[#]") or string.match(line, "^%s*%-%-") or string.match(line, "^%s*//")
            
            if not isBlank and not isComment then
                local key, value = string.match(line, "^%s*([^=]+)%s*=%s*(.-)%s*$")
                
                if key == "Language" and value ~= "" then
                    CurrentLocale = value
                    print("[ItemTranslationMod] Found setting. Language set to: " .. CurrentLocale)
                elseif key == "Debug" then
                    DebugMode = (string.lower(value) == "true" or value == "1")
                    print("[ItemTranslationMod] Debug mode set to: " .. tostring(DebugMode))
                elseif key == "SearchLanguage" then
                    local sl = string.lower(value)
                    if sl == "translated" or sl == "english" or sl == "both" then
                        SearchLanguage = sl
                    end
                    print("[ItemTranslationMod] SearchLanguage set to: " .. tostring(SearchLanguage))
                end
            end
        end
        file:close()
    else
        print("[ItemTranslationMod] Warning: Could not find settings.txt.")
    end
end

LoadSettings()

local function LoadTranslations(lang)
    if lang == "" then return 0 end
    print("[ItemTranslationMod] Attempting to load translations for: " .. tostring(lang))
    local filepath = "ue4ss/Mods/ItemTranslationMod/Translations/" .. tostring(lang) .. ".txt"
    local file = io.open(filepath, "r")
    
    if not file then
        print("[ItemTranslationMod] Warning: Could not find translation file at: " .. filepath)
        return 0
    end

    ItemTranslations = {}
    ItemTranslationsLower = {}
    SearchReplacements = {}
    local count = 0
    local delimiter = "|"
    local isFirstLine = true
    local isFirstValidLine = true
    local inBlockComment = false
    
    for line in file:lines() do
        if isFirstLine then
            if string.sub(line, 1, 3) == "\239\187\191" then
                line = string.sub(line, 4)
            end
            isFirstLine = false
        end
        
        line, inBlockComment = ProcessBlockComments(line, inBlockComment)
        
        local isBlank = string.match(line, "^%s*$")
        local isComment = string.match(line, "^%s*[#]") or string.match(line, "^%s*%-%-") or string.match(line, "^%s*//")
        
        if not isBlank and not isComment then
            local isLocaleHeader = false
            
            if isFirstValidLine then
                isFirstValidLine = false
                local match_delim = string.match(line, "^locale%s*([%S])")
                
                if match_delim then
                    delimiter = match_delim
                    print("[ItemTranslationMod] Custom delimiter found. Set to '" .. delimiter .. "'")
                    isLocaleHeader = true
                end
            end
            
            if not isLocaleHeader then
                local equals_idx = string.find(line, delimiter, 1, true)
                if equals_idx then
                    local key = string.sub(line, 1, equals_idx - 1):match("^%s*(.-)%s*$")
                    local value = string.sub(line, equals_idx + 1)
                    
                    value = string.gsub(value, "\\#", "\001")
                    value = string.gsub(value, "\\//", "\002")
                    value = string.gsub(value, "\\%-%-", "\003")
                    
                    value = string.gsub(value, "%s*#.*$", "")
                    value = string.gsub(value, "%s*//.*$", "")
                    value = string.gsub(value, "%s*%-%-.*$", "")
                    
                    value = string.gsub(value, "\001", "#")
                    value = string.gsub(value, "\002", "//")
                    value = string.gsub(value, "\003", "--")
                    value = value:match("^%s*(.-)%s*$")
                    
                    if key and value and key ~= "" then
                        ItemTranslations[key] = value
                        ItemTranslationsLower[key:lower()] = value
                        table.insert(SearchReplacements, { 
                            raw_eng = key,
                            eng = key:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1"), 
                            loc = value 
                        })
                        count = count + 1
                    end
                end
            end
        end
    end
    
    file:close()

    table.sort(SearchReplacements, function(a, b)
        return #a.raw_eng > #b.raw_eng
    end)
    
    print("[ItemTranslationMod] Successfully loaded " .. tostring(count) .. " translations from " .. filepath)
    return count
end

local function TranslateTextBlock(CurrentText)
    if CurrentText == "" then return CurrentText end
    
    if TranslationCache[CurrentText] then
        return TranslationCache[CurrentText]
    end
    
    if ItemTranslations[CurrentText] then
        if not TranslationCache[CurrentText] then
            if TranslationCacheSize > MAX_CACHE_SIZE then
                TranslationCache = {}
                TranslationCacheSize = 0
            end
            TranslationCache[CurrentText] = ItemTranslations[CurrentText]
            TranslationCacheSize = TranslationCacheSize + 1
        end
        return TranslationCache[CurrentText]
    end
    
    local NewText = string.gsub(CurrentText, "([^\n]+)", function(line)
        local leading_space, core_text, trailing_space = line:match("^(%s*)(.-)(%s*)$")
        
        if core_text == "" then return line end
        
        if ItemTranslations[core_text] then
            return leading_space .. ItemTranslations[core_text] .. trailing_space
        end
        
        local prefix, rest = core_text:match("^([%+%-]?%d+%.?%d*[%a%%/]*%s+)(.+)$")
        if prefix and rest then
            if ItemTranslations[rest] then
                return leading_space .. prefix .. ItemTranslations[rest] .. trailing_space
            end
        end
        
        -- TIP:
        local word_prefix, spaces, word_rest = core_text:match("^([^:]+:)(%s+)(.+)$")
        if word_prefix and spaces and word_rest then
            local translated_prefix = ItemTranslations[word_prefix]
            if translated_prefix then
                local translated_rest = ItemTranslations[word_rest] or word_rest
                if translated_prefix == "" then
                    return leading_space .. translated_rest .. trailing_space
                else
                    return leading_space .. translated_prefix .. spaces .. translated_rest .. trailing_space
                end
            end
        end
        
        return line
    end)
    
    if not TranslationCache[CurrentText] then
        if TranslationCacheSize > MAX_CACHE_SIZE then
            TranslationCache = {}
            TranslationCacheSize = 0
        end
        TranslationCache[CurrentText] = NewText
        TranslationCacheSize = TranslationCacheSize + 1
    end
    
    return NewText
end

local function HookTooltip()
    print("[ItemTranslationMod] Attempting to register hook on SetItem...")
    RegisterHook("/Game/Classes/GUI/New/Components/ItemTooltip.ItemTooltip_C:SetItem", function(Context, Item)
        local TooltipWidget = Context:get()
        if not TooltipWidget or not TooltipWidget:IsValid() then return end
        
        if TooltipWidget.ItemName and TooltipWidget.ItemName:IsValid() then
            local CurrentName = TooltipWidget.ItemName:GetText():ToString()
            if CurrentName ~= "" then
                if DebugMode then
                    print("[ItemTranslationMod] Raw ItemName: " .. tostring(CurrentName))
                end
                
                local TranslatedName = ItemTranslations[CurrentName]
                if TranslatedName then
                    TooltipWidget.ItemName:SetText(FText(TranslatedName))
                    if DebugMode then
                        print("[ItemTranslationMod] Translated ItemName: " .. tostring(TranslatedName))
                    end
                end
            end
        end
        
        if TooltipWidget.ItemDescription and TooltipWidget.ItemDescription:IsValid() then
            local CurrentDesc = TooltipWidget.ItemDescription:GetText():ToString()
            if CurrentDesc ~= "" then
                if DebugMode then
                    print("[ItemTranslationMod] Raw ItemDescription: " .. string.gsub(CurrentDesc, "\n", "\\n"))
                end
                
                local NewDesc = TranslateTextBlock(CurrentDesc)
                
                if NewDesc ~= CurrentDesc then
                    TooltipWidget.ItemDescription:SetText(FText(NewDesc))
                    if DebugMode then
                        print("[ItemTranslationMod] Translated Description: " .. string.gsub(NewDesc, "\n", "\\n"))
                    end
                end
            end
        end
        
        if TooltipWidget.ResistanceList and TooltipWidget.ResistanceList:IsValid() then
            local CurrentRes = TooltipWidget.ResistanceList:GetText():ToString()
            if CurrentRes ~= "" then
                if DebugMode then
                    print("[ItemTranslationMod] Raw ResistanceList: " .. string.gsub(CurrentRes, "\n", "\\n"))
                end
                
                local NewRes = TranslateTextBlock(CurrentRes)
                
                if NewRes ~= CurrentRes then
                    TooltipWidget.ResistanceList:SetText(FText(NewRes))
                    if DebugMode then
                        print("[ItemTranslationMod] Translated ResistanceList: " .. string.gsub(NewRes, "\n", "\\n"))
                    end
                end
            end
        end
    end)
    print("[ItemTranslationMod] ItemTooltip hook registered successfully!")
end

local function HookInspectScreen()
    print("[ItemTranslationMod] Attempting to register hook on InspectItemScreen_C:Construct...")
    RegisterHook("/Game/Classes/GUI/New/InspectItemScreen.InspectItemScreen_C:Construct", function(Context)
        local InspectWidget = Context:get()
        if not InspectWidget or not InspectWidget:IsValid() then return end
        
        if InspectWidget.TextBlock_ItemName and InspectWidget.TextBlock_ItemName:IsValid() then
            local CurrentName = InspectWidget.TextBlock_ItemName:GetText():ToString()
            if CurrentName ~= "" then
                if DebugMode then
                    print("[ItemTranslationMod] Inspect Screen - Raw ItemName: " .. tostring(CurrentName))
                end
                
                local TranslatedName = ItemTranslations[CurrentName]
                if TranslatedName then
                    InspectWidget.TextBlock_ItemName:SetText(FText(TranslatedName))
                    if DebugMode then
                        print("[ItemTranslationMod] Inspect Screen - Translated ItemName: " .. tostring(TranslatedName))
                    end
                end
            end
        end
        
        if InspectWidget.TextBlock_Description and InspectWidget.TextBlock_Description:IsValid() then
            local CurrentDesc = InspectWidget.TextBlock_Description:GetText():ToString()
            if CurrentDesc ~= "" then
                if DebugMode then
                    print("[ItemTranslationMod] Inspect Screen - Raw ItemDescription: " .. string.gsub(CurrentDesc, "\n", "\\n"))
                end
                
                local NewDesc = TranslateTextBlock(CurrentDesc)
                
                if NewDesc ~= CurrentDesc then
                    InspectWidget.TextBlock_Description:SetText(FText(NewDesc))
                    if DebugMode then
                        print("[ItemTranslationMod] Inspect Screen - Translated Description: " .. string.gsub(NewDesc, "\n", "\\n"))
                    end
                end
            end
        end
        
        if InspectWidget.TextBlock_ResistanceList and InspectWidget.TextBlock_ResistanceList:IsValid() then
            local CurrentRes = InspectWidget.TextBlock_ResistanceList:GetText():ToString()
            if CurrentRes ~= "" then
                if DebugMode then
                    print("[ItemTranslationMod] Inspect Screen - Raw ResistanceList: " .. string.gsub(CurrentRes, "\n", "\\n"))
                end
                
                local NewRes = TranslateTextBlock(CurrentRes)
                
                if NewRes ~= CurrentRes then
                    InspectWidget.TextBlock_ResistanceList:SetText(FText(NewRes))
                    if DebugMode then
                        print("[ItemTranslationMod] Inspect Screen - Translated ResistanceList: " .. string.gsub(NewRes, "\n", "\\n"))
                    end
                end
            end
        end
    end)
    print("[ItemTranslationMod] InspectItemScreen hook registered successfully!")
end

local function HookItemCardSearch()
    print("[ItemTranslationMod] Attempting to register hook on ItemCard_C:PrepSearchString...")
    RegisterHook("/Game/Classes/GUI/New/Components/ItemCard.ItemCard_C:PrepSearchString", function(Context)
        local ItemCardWidget = Context:get()
        if not ItemCardWidget or not ItemCardWidget:IsValid() then return end
        
        local OriginalSearchString = ItemCardWidget:GetPropertyValue("SearchString") or ItemCardWidget.SearchString
        if type(OriginalSearchString) == "userdata" then
            if OriginalSearchString.ToString then
                OriginalSearchString = OriginalSearchString:ToString()
            elseif OriginalSearchString.get then
                OriginalSearchString = OriginalSearchString:get()
            end
        end

        if OriginalSearchString and type(OriginalSearchString) == "string" then
            if DebugMode then
                print("[ItemTranslationMod] ItemCard PrepSearchString Fired. Raw: " .. string.gsub(OriginalSearchString, "\n", "\\n"))
            end
            if OriginalSearchString ~= "" then
                local TranslatedSearch = SearchStringCache[OriginalSearchString]
                if not TranslatedSearch then
                    TranslatedSearch = OriginalSearchString
                    for i = 1, #SearchReplacements do
                        TranslatedSearch = TranslatedSearch:gsub(SearchReplacements[i].eng, SearchReplacements[i].loc)
                    end
                    SearchStringCache[OriginalSearchString] = TranslatedSearch
                end
                
                if TranslatedSearch ~= OriginalSearchString then
                    local NewSearchString = TranslatedSearch
                    if SearchLanguage == "both" then
                        NewSearchString = OriginalSearchString .. "\n" .. TranslatedSearch
                    end
                    
                    if DebugMode then
                        print("[ItemTranslationMod] SearchString successfully translated to:\n" .. string.gsub(TranslatedSearch, "\n", "\\n"))
                    end
                    
                    local success, err = pcall(function()
                        ItemCardWidget:SetPropertyValue("SearchString", NewSearchString)
                    end)
                    
                    if DebugMode then
                        if success then
                            print("[ItemTranslationMod] Appended Translated SearchString for ItemCard.")
                        else
                            print("[ItemTranslationMod] ERROR setting SearchString: " .. tostring(err))
                        end
                    end
                end
            end
        end
    end)
    print("[ItemTranslationMod] ItemCardSearch hook registered successfully!")
end

local isSelectorHooked = false

local function GetTranslation(text)
    if not text or text == "" then return nil end
    if ItemTranslations[text] then return ItemTranslations[text] end
    if ItemTranslationsLower[text:lower()] then return ItemTranslationsLower[text:lower()] end
    return nil
end

local function TranslateSelectorWidget(selector)
    if not selector or not selector:IsValid() then return end
    pcall(function()
        if selector.TextBlock_Setting and selector.TextBlock_Setting:IsValid() then
            local currentDisplayed = selector.TextBlock_Setting:GetText():ToString()
            local rawText = nil

            if selector.Settings then
                local idx = (selector.IndexOutPut or 0) + 1
                if selector.Settings[idx] then
                    rawText = selector.Settings[idx]:ToString()
                end
            end

            local candidates = {}
            if rawText and rawText ~= "" then
                table.insert(candidates, rawText)
            end
            if currentDisplayed and currentDisplayed ~= "" then
                table.insert(candidates, currentDisplayed)
            end

            local translatedText = nil
            for _, candidate in ipairs(candidates) do
                local found = GetTranslation(candidate)
                if found then
                    translatedText = found
                    break
                end
            end

            if translatedText and translatedText ~= currentDisplayed then
                local displayText = string.upper(translatedText)
                selector.TextBlock_Setting:SetText(FText(displayText))
                if DebugMode then
                    print(string.format("[ItemTranslationMod] Translated Selector Value: '%s' -> '%s'", currentDisplayed, translatedText))
                end
            elseif DebugMode and currentDisplayed ~= "" and not translatedText then
                print(string.format("[ItemTranslationMod] Selector skipped (no key for '%s' or '%s')", tostring(rawText), tostring(currentDisplayed)))
            end
        end
    end)
end

local function TranslateAllActiveSelectors()
    local selectors = FindAllOf("Setting_Selector_Widget_C")
    if selectors and #selectors > 0 then
        for _, selector in ipairs(selectors) do
            TranslateSelectorWidget(selector)
        end
    end
end

local function HookCharacterEditorSelectors()
    local function TryRegisterSelectorHooks()
        if isSelectorHooked then return true end

        local basePath = "/Game/Classes/GUI/SubWidgets/Setting_Selector_Widget.Setting_Selector_Widget_C:"
        local nextFunc = basePath .. "BndEvt__Setting_Selector_Widget_Button_Next_K2Node_ComponentBoundEvent_0_OnButtonClickedEvent__DelegateSignature"
        local prevFunc = basePath .. "BndEvt__Setting_Selector_Widget_Button_Prev_K2Node_ComponentBoundEvent_1_OnButtonClickedEvent__DelegateSignature"

        local hookCount = 0

        local ok1, err1 = pcall(function()
            RegisterHook(nextFunc, function(Context)
                local selector = Context:get()
                if not selector or not selector:IsValid() then return end
                if DebugMode then
                    print("[ItemTranslationMod] Button_Next clicked!")
                end
                ExecuteWithDelay(10, function()
                    if selector and selector:IsValid() then
                        TranslateSelectorWidget(selector)
                    end
                end)
            end)
        end)
        if ok1 then
            hookCount = hookCount + 1
            print("[ItemTranslationMod] Button_Next hook registered!")
        elseif DebugMode then
            print("[ItemTranslationMod] Button_Next hook failed: " .. tostring(err1))
        end

        local ok2, err2 = pcall(function()
            RegisterHook(prevFunc, function(Context)
                local selector = Context:get()
                if not selector or not selector:IsValid() then return end
                if DebugMode then
                    print("[ItemTranslationMod] Button_Prev clicked!")
                end
                ExecuteWithDelay(10, function()
                    if selector and selector:IsValid() then
                        TranslateSelectorWidget(selector)
                    end
                end)
            end)
        end)
        if ok2 then
            hookCount = hookCount + 1
            print("[ItemTranslationMod] Button_Prev hook registered!")
        elseif DebugMode then
            print("[ItemTranslationMod] Button_Prev hook failed: " .. tostring(err2))
        end

        if hookCount > 0 then
            isSelectorHooked = true
        end
        return hookCount > 0
    end

    pcall(function()
        NotifyOnNewObject("/Script/UMG.UserWidget", function(Widget)
            if not Widget or not Widget:IsValid() then return end
            local fullName = Widget:GetFullName()
            if fullName and fullName:find("^Character_Editor_Widget_C") then
                if DebugMode then
                    print("[ItemTranslationMod] Character_Editor_Widget_C constructed. Translating selector values...")
                end
                
                TryRegisterSelectorHooks()

                ExecuteWithDelay(100, function()
                    TranslateAllActiveSelectors()
                end)
            end
        end)
    end)
end

local isSettingsHooked = false

local function TranslateAllControlLabels()
    local rebindWidgets = FindAllOf("KeyRebind_Widget_C")
    if rebindWidgets and #rebindWidgets > 0 then
        for _, rw in ipairs(rebindWidgets) do
            if rw and rw:IsValid() then
                pcall(function()
                    if rw.TextBlock_Name and rw.TextBlock_Name:IsValid() then
                        local currentDisplayed = rw.TextBlock_Name:GetText():ToString()
                        if currentDisplayed and currentDisplayed ~= "" and not currentDisplayed:find("^FString:") then
                            local translated = GetTranslation(currentDisplayed)
                            if not translated and currentDisplayed:sub(-1) == ":" then
                                local noColon = currentDisplayed:sub(1, -2)
                                local tNoColon = GetTranslation(noColon)
                                if tNoColon then
                                    translated = tNoColon .. ":"
                                end
                            end

                            if translated and translated ~= currentDisplayed then
                                rw.TextBlock_Name:SetText(FText(string.upper(translated)))
                                if DebugMode then
                                    print(string.format("[ItemTranslationMod] Translated Control Label: '%s' -> '%s'", currentDisplayed, string.upper(translated)))
                                end
                            end
                        end
                    end
                end)
            end
        end
    end

    local moveWidgets = FindAllOf("KeyRebind_Movement_Widget_C")
    if moveWidgets and #moveWidgets > 0 then
        for _, mw in ipairs(moveWidgets) do
            if mw and mw:IsValid() then
                for _, tbName in ipairs({"TextBlock_Name", "TextBlock_Name_1", "TextBlock_Name_2", "TextBlock_Name_3", "TextBlock_Name_4"}) do
                    pcall(function()
                        local tb = mw[tbName]
                        if tb and tb:IsValid() then
                            local currentDisplayed = tb:GetText():ToString()
                            if currentDisplayed and currentDisplayed ~= "" and not currentDisplayed:find("^FString:") then
                                local translated = GetTranslation(currentDisplayed)
                                if not translated and currentDisplayed:sub(-1) == ":" then
                                    local noColon = currentDisplayed:sub(1, -2)
                                    local tNoColon = GetTranslation(noColon)
                                    if tNoColon then
                                        translated = tNoColon .. ":"
                                    end
                                end
                                if translated and translated ~= currentDisplayed then
                                    tb:SetText(FText(string.upper(translated)))
                                    if DebugMode then
                                        print(string.format("[ItemTranslationMod] Translated Movement Label: '%s' -> '%s'", currentDisplayed, string.upper(translated)))
                                    end
                                end
                            end
                        end
                    end)
                end
            end
        end
    end
end

local function HookSettingsControlLabels()
    local function TryRegisterSettingsHooks()
        if isSettingsHooked then return true end

        local tabFunc = "/Game/Classes/GUI/Menu_Settings_Widget.Menu_Settings_Widget_C:BndEvt__Menu_Settings_Widget_Button_Mode_KeyBinds_K2Node_ComponentBoundEvent_33_Pressed__DelegateSignature"
        local defFunc = "/Game/Classes/GUI/Menu_Settings_Widget.Menu_Settings_Widget_C:BndEvt__Menu_Settings_Widget_Button_Defaults_K2Node_ComponentBoundEvent_13_Pressed__DelegateSignature"

        local count = 0
        pcall(function()
            RegisterHook(tabFunc, function()
                ExecuteWithDelay(100, function()
                    TranslateAllControlLabels()
                end)
            end)
            count = count + 1
        end)

        pcall(function()
            RegisterHook(defFunc, function()
                ExecuteWithDelay(100, function()
                    TranslateAllControlLabels()
                end)
            end)
            count = count + 1
        end)

        if count > 0 then
            isSettingsHooked = true
            if DebugMode then
                print("[ItemTranslationMod] Settings KeyBinds hooks registered successfully!")
            end
        end
        return isSettingsHooked
    end

    pcall(function()
        NotifyOnNewObject("/Script/UMG.UserWidget", function(Widget)
            if not Widget or not Widget:IsValid() then return end
            local fullName = Widget:GetFullName()
            if fullName and fullName:find("^Menu_Settings_Widget_C") then
                if DebugMode then
                    print("[ItemTranslationMod] Menu_Settings_Widget_C constructed. Translating control labels...")
                end

                TryRegisterSettingsHooks()

                ExecuteWithDelay(100, function()
                    TranslateAllControlLabels()
                end)
            end
        end)
    end)
end

local function Init()
    local loadedCount = LoadTranslations(CurrentLocale)

    if loadedCount > 0 then
        local success1 = pcall(HookTooltip)
        local success2 = pcall(HookInspectScreen)
        local success3 = true
        if SearchLanguage ~= "english" then
            success3 = pcall(HookItemCardSearch)
        end
        local success4 = pcall(HookCharacterEditorSelectors)
        local success5 = pcall(HookSettingsControlLabels)

        if not (success1 and success2 and success3 and success4 and success5) then
            print("[ItemTranslationMod] Blueprints not loaded yet. Waiting for construction...")
            local isHooked = false

            RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
                if not isHooked then
                    pcall(HookTooltip)
                    pcall(HookInspectScreen)
                    if SearchLanguage ~= "english" then
                        pcall(HookItemCardSearch)
                    end
                    pcall(HookCharacterEditorSelectors)
                    pcall(HookSettingsControlLabels)
                    isHooked = true
                end
            end)
        end
    else
        print("[ItemTranslationMod] No translations loaded. The mod will remain inactive.")
    end

    print(string.format("[ItemTranslationMod] v%s loaded successfully.", ModVersion))
end

Init()
