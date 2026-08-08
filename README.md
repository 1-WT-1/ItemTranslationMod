# Item Translation Mod

## Install

1. Get UE4SS. <https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest> UE4ss installation: <https://github.com/UE4SS-RE/RE-UE4SS#basic-installation>
2. Copy the `ItemTranslationMod` folder into the `ue4ss/Mods` directory.
3. Start the game. UE4SS loads the mod automatically because the folder contains an `enabled.txt` file.

## Choose Your Language

1. Open `settings.txt` in the mod folder.
2. Change the `Language` value to match your translation file name in the `Translations` folder (for example, `Language=de`).
3. Save the file.

## Edit the Translations

1. Open the `Translations` folder in the mod directory.
2. Create or edit a text file for your language code (for example, `example.txt`).
3. Add a new line for each item that you want to translate.
4. Put the exact English name on the left side of the pipe character `|`. Put your translated name on the right side.

### Custom Delimiters (Optional)

You can change the separator. Add `locale` followed by your custom character and language code to the very first line of the file.
Example (`example.txt` using `=` as the separator):

```
locale=example
```

1. Save the text file.
2. Click **Restart All Mods** in the UE4SS window to load the new text.
