local _print = print
local print = function(msg)
    _print(tostring(msg) .. "\n")
end

local ModVersion = "1.1.2"
print(string.format("[ItemTranslationMod] v%s Initializing...", ModVersion))

local ItemTranslations = {}
local TranslationCache = {}
local TranslationCacheSize = 0
local MAX_CACHE_SIZE = 1000

local CurrentLocale = ""
local DebugMode = false

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
                        count = count + 1
                    end
                end
            end
        end
    end
    
    file:close()
    
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
        
        local prefix, rest = core_text:match("^([%+%-]?%d+%.?%d*[x%%]?%s+)(.+)$")
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
    print("[ItemTranslationMod] Hook registered successfully!")
end

local loadedCount = LoadTranslations(CurrentLocale)

if loadedCount > 0 then
    local success = pcall(HookTooltip)

    if not success then
        print("[ItemTranslationMod] Blueprint not loaded yet. Waiting for ItemTooltip_C to be constructed...")
        local isHooked = false
        NotifyOnNewObject("/Game/Classes/GUI/New/Components/ItemTooltip.ItemTooltip_C", function(ConstructedObject)
            if not isHooked then
                print("[ItemTranslationMod] ItemTooltip_C instance constructed! Registering hook now.")
                success = pcall(HookTooltip)
                if success then
                    isHooked = true
                    print("[ItemTranslationMod] Cleaning up NotifyOnNewObject listener.")
                    return true
                end
            end
        end)
    end
else
    print("[ItemTranslationMod] No translations loaded. The mod will remain inactive.")
end

print(string.format("[ItemTranslationMod] v%s loaded successfully.", ModVersion))
