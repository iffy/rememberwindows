rememberwindows: rememberwindows.swift
	swiftc rememberwindows.swift -o rememberwindows

install: rememberwindows com.github.iffy.rememberwindows.plist
	sudo cp rememberwindows /usr/local/bin/rememberwindows
	sudo chmod +x /usr/local/bin/rememberwindows
	cp com.github.iffy.rememberwindows.plist ~/Library/LaunchAgents/
	launchctl load -w ~/Library/LaunchAgents/com.github.iffy.rememberwindows.plist

uninstall:
	launchctl unload -w ~/Library/LaunchAgents/com.github.iffy.rememberwindows.plist
	rm ~/Library/LaunchAgents/com.github.iffy.rememberwindows.plist
	-sudo rm /var/log/rememberwindows.log
	-sudo rm /var/log/rememberwindows.err
	sudo rm /usr/local/bin/rememberwindows

clean:
	rm -f rememberwindows
