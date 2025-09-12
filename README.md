On recent versions of macOS, windows often get gathered to the main monitor after waking from sleep. This script tries to keep windows where they were before sleeping.

Pull requests welcome.

## Installation

```
git clone https://github.com/iffy/rememberwindows.git
cd rememberwindows
make
make install
```

Try locking and unlocking your computer and see if the windows stay where they should.

## Log files

This will log to:

- `/var/log/rememberwindows.log`
- `/var/log/rememberwindows.err`

## Unintall

To remove everything run:

```
make uninstall
```
