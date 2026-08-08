local ModVersion = "1.0.0"
print(string.format("[ItemTranslationMod] v%s Initializing...", ModVersion))

local ItemTranslations = {}
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

local function HookTooltip()
    print("[ItemTranslationMod] Attempting to register hook on SetItem...")
    RegisterHook("/Game/Classes/GUI/New/Components/ItemTooltip.ItemTooltip_C:SetItem", function(Context, Item)
        local TooltipWidget = Context:get()
        
        if TooltipWidget:IsValid() and TooltipWidget.ItemName and TooltipWidget.ItemName:IsValid() then
            local CurrentName = TooltipWidget.ItemName:GetText():ToString()
            
            if DebugMode then
                print("[ItemTranslationMod] Hovering item: " .. tostring(CurrentName))
            end
            
            local TranslatedName = ItemTranslations[CurrentName]
            if TranslatedName then
                TooltipWidget.ItemName:SetText(FText(TranslatedName))
                if DebugMode then
                    print("[ItemTranslationMod] Translated to: " .. tostring(TranslatedName))
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
