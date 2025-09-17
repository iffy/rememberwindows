.PHONY: pkg dmg

dist/rememberwindows: rememberwindows.swift
	mkdir -p dist
	swiftc rememberwindows.swift -o dist/rememberwindows
	codesign -f -s - dist/rememberwindows

install: dist/rememberwindows com.github.iffy.rememberwindows.plist
	sudo cp dist/rememberwindows /usr/local/bin/rememberwindows
	sudo chmod +x /usr/local/bin/rememberwindows
	cp com.github.iffy.rememberwindows.plist ~/Library/LaunchAgents/
	launchctl load -w ~/Library/LaunchAgents/com.github.iffy.rememberwindows.plist

uninstall:
	launchctl unload -w ~/Library/LaunchAgents/com.github.iffy.rememberwindows.plist
	rm ~/Library/LaunchAgents/com.github.iffy.rememberwindows.plist
	sudo rm /usr/local/bin/rememberwindows

clean:
	-rm -rf dist