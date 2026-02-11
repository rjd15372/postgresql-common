Format: 3.0 (native)
Source: percona-postgresql-common
Binary: percona-postgresql-common, percona-postgresql-common-dev, postgresql-common, postgresql-client-common, percona-postgresql-server-dev-all, percona-postgresql, percona-postgresql-client, percona-postgresql-doc, percona-postgresql-contrib, percona-postgresql-all
Architecture: all
Version: 280
Debtransform-Release: 1
Debtransform-Tar: percona-postgresql-common-280.tar.gz
Maintainer: Percona Development Team <info@percona.com>
Testsuite: autopkgtest
Testsuite-Triggers: build-essential, debhelper, fakeroot, hunspell-en-us, iproute2, locales-all, logrotate, netcat-openbsd, perl, postgresql, postgresql-all, postgresql-doc, procps
Build-Depends: debhelper (>= 9), debhelper (>= 10.1) | dh-systemd (>= 1.19), libreadline-dev
Package-List:
 percona-postgresql deb database optional arch=all
 percona-postgresql-all deb database optional arch=all
 percona-postgresql-client deb database optional arch=all
 percona-postgresql-common deb database optional arch=all
 percona-postgresql-common-dev deb database optional arch=all
 percona-postgresql-contrib deb database optional arch=all
 percona-postgresql-doc deb doc optional arch=all
 percona-postgresql-server-dev-all deb database optional arch=all
 postgresql-client-common deb database optional arch=all
 postgresql-common deb database optional arch=all
Checksums-Sha1:
 ac577c4378332d49f3d0d1834e9bfbfbbed204e1 166344 percona-postgresql-common_280.tar.xz
Checksums-Sha256:
 603cc75813f8d4b811e9a14457c1579d497740148231a505ce9925ba261fd933 166344 percona-postgresql-common_280.tar.xz
Files:
 6caefbea7cfbcba23bef826678f3e265 166344 percona-postgresql-common_280.tar.xz
