.PHONY: deb deb-arm64 clean

deb:
	dpkg-buildpackage -us -uc -b

# Build on an arm64 host:
deb-arm64:
	sed 's/^Architecture: amd64/Architecture: arm64/' debian/control > debian/control.build
	mv debian/control debian/control.bak
	mv debian/control.build debian/control
	dpkg-buildpackage -aarm64 -us -uc -b; rc=$$?; mv debian/control.bak debian/control; exit $$rc

clean:
	dh_clean 2>/dev/null || rm -rf build debian/.debhelper debian/files debian/nexory-tunnel debian/debhelper-build-stamp
	rm -f ../nexory-tunnel_*.deb ../nexory-tunnel_*.changes ../nexory-tunnel_*.buildinfo
