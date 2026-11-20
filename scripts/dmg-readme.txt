PROMPT FORGE: INSTALL

1. Drag "Prompt Forge" onto the Applications folder.

2. First launch: the app isn't notarized by Apple, so macOS will block it once.
   Fix it with ONE of these:
   - Open Terminal and run:
       xattr -dr com.apple.quarantine "/Applications/Prompt Forge.app"
   - Or try to open it, then go to System Settings > Privacy & Security
     and click "Open Anyway".

3. Pick how it talks to an AI: Prompt Forge > Settings (Cmd+,) > Provider.
   The default is your Claude subscription through Claude Code
   (install it and run `claude` once to log in).

4. To read and replace selected text in other apps, allow
   Prompt Forge in System Settings > Privacy & Security > Accessibility.

Use it: select text anywhere, press Control+Option+Space, pick an action.
