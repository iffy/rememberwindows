On recent versions of macOS, windows often get gathered to the main monitor after waking from sleep. This script tries to keep windows where they were before sleeping. Pull requests welcome.

[Get it here](https://github.com/iffy/rememberwindows/releases/latest)

## Installation on command line

```
git clone https://github.com/iffy/rememberwindows.git
cd rememberwindows
make
make install # this will prompt for your password
```

Try locking and unlocking your computer and see if the windows stay where they should.

## Manual run

This is what is run during lock/unlock:

```
dist/rememberwindows capture windowdata.json
dist/rememberwindows reposition windowdata.json
```

This is a long-running process that monitors for lock/unlock events and does the window moving. If you're experiencing issues, disable the launchd service (`make uninstall`) and run it manually:

```
dist/rememberwindows monitor
```

## Uninstall

To remove everything run:

```
make uninstall
```

## Making a new release

```
make dmg
```
