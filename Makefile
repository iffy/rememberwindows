.PHONY: pkg dmg
VERSION := $(shell changer current-version)
SIGNER := Developer ID Installer: ONE PART RAIN, LLC

# Direct installation to user LaunchAgents

dist/rememberwindows: rememberwindows.swift
	mkdir -p dist
	swiftc rememberwindows.swift -o dist/rememberwindows

install: dist/rememberwindows com.github.iffy.rememberwindows.plist
	sudo cp dist/rememberwindows /usr/local/bin/rememberwindows
	sudo chmod +x /usr/local/bin/rememberwindows
	cp com.github.iffy.rememberwindows.plist ~/Library/LaunchAgents/
	launchctl load -w ~/Library/LaunchAgents/com.github.iffy.rememberwindows.plist

uninstall:
	launchctl unload -w ~/Library/LaunchAgents/com.github.iffy.rememberwindows.plist
	rm ~/Library/LaunchAgents/com.github.iffy.rememberwindows.plist
	sudo rm /usr/local/bin/rememberwindows

# Packaging for user LaunchAgents

pkging/root/usr/local/bin/rememberwindows: dist/rememberwindows
	mkdir -p pkging/root/usr/local/bin
	cp dist/rememberwindows pkging/root/usr/local/bin/rememberwindows
	chmod 755 pkging/root/usr/local/bin/rememberwindows
	sudo chown root:wheel pkging/root/usr/local/bin/rememberwindows

pkging/scripts/com.github.iffy.rememberwindows.plist: com.github.iffy.rememberwindows.plist
	mkdir -p pkging/resources
	cp com.github.iffy.rememberwindows.plist pkging/scripts/com.github.iffy.rememberwindows.plist
	chmod 644 pkging/scripts/com.github.iffy.rememberwindows.plist

dist/rememberwindows-component.pkg: CHANGELOG.md pkging/root/usr/local/bin/rememberwindows pkging/scripts/com.github.iffy.rememberwindows.plist pkging/scripts/postinstall
	pkgbuild --root ./pkging/root \
		--identifier com.github.iffy.rememberwindows \
		--version "$(VERSION)" \
		--install-location / \
		--scripts ./pkging/scripts \
		dist/rememberwindows-component.pkg

dist/rememberwindows-installer.pkg: CHANGELOG.md dist/rememberwindows-component.pkg
	productbuild \
		--package dist/rememberwindows-component.pkg \
		--version "$(VERSION)" \
		--sign "$(SIGNER)" \
		dist/rememberwindows-installer.pkg

pkg: dist/rememberwindows-installer.pkg
	echo "Package created at dist/rememberwindows-installer.pkg"

dist/rememberwindows.dmg: dist/rememberwindows-installer.pkg
	mkdir -p dist
	hdiutil create -volname "Remember Windows" -srcfolder dist/rememberwindows-installer.pkg -ov -format UDZO dist/rememberwindows.dmg

dmg: dist/rememberwindows.dmg
	echo "DMG created at dist/rememberwindows.dmg"

clean:
	rm -f rememberwindows
	-rm -rf dist
	-rm -rf pkging/root
	-rm -rf pkging/resources