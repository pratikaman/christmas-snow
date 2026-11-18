# 🎄 Christmas Snow for Mac

![Three little Santas out for a snowy Christmas Eve stroll](Artwork/christmas-eve.gif)

Santa’s boots are on your Dock. All three pairs. 🎅

While they make their rounds, snowflakes settle on your windows. Sweep your cursor through a little drift and watch the powder fly. If your MacBook senses movement, gently tilt it and the flakes will drift with you.

Click the **❄︎ snowflake in your menu bar** when you feel like changing the weather. Pick a light dusting or a snowstorm. Under **Santa Size**, choose Tiny, Small, Medium, or Large. Tiny is particularly good at sneaking past your open tabs.

For snow on individual tabs and Dock icons, choose **Enable Precise Tab and Dock Edges…** from the snowflake menu and allow Accessibility when your Mac asks. When it’s time to put the decorations away, **Quit Christmas Snow** sends everyone home.

## 🎁 Unwrap it on your Mac

You’ll need **macOS Ventura (13) or later**. Pick whichever way feels easier.

### 💬 Install with a prompt

Paste this into a coding assistant that can run commands on your Mac.

```text
Please install Christmas Snow from https://github.com/pratikaman/christmas-snow on my Mac. Check that Apple’s Command Line Tools are ready and help me install them if needed. Download the project, use its build.sh to install Christmas Snow.app in my personal Applications folder, then open it so the snow starts falling.
```

### ⌨️ Install with Terminal

If this is your first time using Apple’s Command Line Tools, paste this into Terminal and let the installer finish.

```sh
xcode-select --install
```

Then paste these lines together to download Christmas Snow, install it, and start the snowfall.

```sh
git clone --depth 1 https://github.com/pratikaman/christmas-snow.git christmas-snow && \
  ./christmas-snow/build.sh "$HOME/Applications/Christmas Snow.app" && \
  open "$HOME/Applications/Christmas Snow.app"
```

## 🧦 A little stocking of thanks

The three little walkers owe their rosy cheeks and excellent boots to pzUH at GameArt2D. [Meet the original Santa artwork on OpenGameArt.](https://opengameart.org/content/santa-claus-free-sprites)

Merry Christmas, and mind the footprints. ❄️
