# Common functionality for postgresql-common self tests
#
# (C) 2005-2009 Martin Pitt <mpitt@debian.org>
# (C) 2013-2025 Christoph Berg <myon@debian.org>
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.

package TestLib;
use strict;
use Exporter;
use IPC::Run qw(run);
use Test::More;
use Time::HiRes qw(usleep);
use PgCommon qw/get_versions change_ugid next_free_port/;

our $VERSION = 1.00;
our @ISA = ('Exporter');
our @EXPORT = qw/os_release ps ok_dir exec_as deb_installed rpm_installed package_version
    version_ge program_ok is_program_out like_program_out unlike_program_out
    pidof pid_env check_clean
    @ALL_MAJORS @MAJORS $delay/;

our @ALL_MAJORS = get_versions(); # not affected by PG_VERSIONS/-v
our @MAJORS = $ENV{PG_VERSIONS} ? split (/\s+/, $ENV{PG_VERSIONS}) : @ALL_MAJORS;
our $delay = 500_000; # 500ms

# architectures where LLVM JIT is enabled and postgresql-NN-jit is built
our @JIT_ARCHS = qw(amd64 arm64 mips64el ppc64 ppc64el s390x);

# called if a test fails; spawn a shell if the environment variable
# FAILURE=shell is set
sub fail_debug { 
    if ($ENV{'FAILURE'} eq 'shell') {
	if ((system 'bash') != 0) {
	    exit 1;
	}
    }
}

# parse /etc/os-release and return (os, version number)
sub os_release {
    open OS, "/etc/os-release" or return (undef, undef);
    my ($os, $osversion);
    while (<OS>) {
        $os = $1 if /^ID=(.*)/;
        $osversion = $1 if /^VERSION_ID="?([^"]*)/;
    }
    close OS;
    $osversion = 'unstable' if ($os eq 'debian' and not defined $osversion);
    return ($os, $osversion);
}

# Return whether a given deb is installed.
# Arguments: <deb name>
sub deb_installed {
    open (DPKG, "dpkg-query --showformat '\${db:Status-Status}' --show $_[0] 2>/dev/null|") or die "call dpkg-query: $!";
    my $result = <DPKG>;
    close DPKG;
    return $result eq "installed";
}

# Return whether a given rpm is installed.
# Arguments: <rpm name>
sub rpm_installed {
    open (RPM, "rpm -qa $_[0] 2>/dev/null|") or die "call rpm: $!";
    my $out = <RPM>; # returns void or the package name
    close RPM;
    return ($out =~ /./);
}

# Return a package version
# Arguments: <package>
sub package_version {
    my $package = shift;
    if ($PgCommon::rpm) {
        return `rpm --queryformat '%{VERSION}' -q $package`;
    } else {
        my $version = `dpkg-query -f '\${Version}' --show $package`;
        chomp $version;
        return $version;
    }
}

# Return whether a version is greater or equal to another one
# Arguments: <ver1> <ver2>
sub version_ge {
    my ($v1, $v2) = @_;
    use IPC::Open2;
    open2(\*CHLD_OUT, \*CHLD_IN, 'sort', '-Vr');
    print CHLD_IN "$v1\n";
    print CHLD_IN "$v2\n";
    close CHLD_IN;
    my $v_ge = <CHLD_OUT>;
    chomp $v_ge;
    return $v_ge eq $v1;
}

# Return if LLVM JIT is enabled on this architecture
sub have_jit ()
{
    my $arch = `dpkg --print-architecture`;
    chomp $arch;
    return grep {$arch eq $_} (@JIT_ARCHS);
}

# Return the user, group, and command line of running processes for the given
# program.
sub ps {
    return `ps h -o user,group,args -C $_[0] | grep '$_[0]' | sort -u`;
}

# Return array of pids that match the given command name (we require a leading
# slash so the postgres children are filtered out)
sub pidof {
    my $prg = shift;
    open F, '-|', 'ps', 'h', '-C', $prg, '-o', 'pid,cmd' or die "open: $!";
    my @pids;
    while (<F>) {
        if ((index $_, "/$prg") >= 0) {
            push @pids, (split)[0];
        }
    }
    close F;
    return @pids;
}

# Return an reference to an array of all entries but . and .. of the given directory.
sub dircontent {
    my $dir = $_[0];
    opendir D, $dir or return ["opendir $dir: $!"];
    my @e = grep { $_ ne '.' && $_ ne '..' } readdir (D);
    closedir D;
    return [sort @e];
}

# Return environment of given PID
sub pid_env {
    my ($user, $pid) = @_;
    my $path = "/proc/$pid/environ";
    my @lines;
    open E, "su -c 'cat $path' $user |" or warn "open $path: $!";
    {
        local $/;
        @lines = split '\0', <E>;
    }
    close E;
    my %env;
    foreach (@lines) {
        my ($k, $v) = (split '=');
        $env{$k} = $v;
    }
    return %env;
}

# Check the contents of a directory.
# Arguments: <directory name> <ref to expected dir content> <test description>
sub ok_dir {
    my $content = dircontent $_[0];
    if (eq_set $content, $_[1]) {
	pass $_[2];
    } else {
	diag "Expected directory contents: [@{$_[1]}], actual contents: [@$content]\n";
	fail $_[2];
    }
}

# Execute a command as a different user and return the output. Prints the
# output of the command if exit code differs from expected one.
# Arguments: <user> <system command> <ref to output> [<expected exit code>] [<ref to stderr>]
# Returns: Program exit code
sub exec_as {
    my ($user, $cmd, $stdout_param, $status, $stderr_param) = @_;
    my $uid;
    if ($user =~ /\d+/) {
	$uid = int($user);
    } else {
	$uid = getpwnam $user;
        defined($uid) or die "TestLib::exec_as: target user '$user' does not exist";
    }
    change_ugid ($uid, (getpwuid $uid)[3]);
    die "changing euid: $!" if $> != $uid;
    if (not defined $stderr_param) {
        $cmd .= " 2>&1";
    }
    my ($stdout, $stderr);
    run(['/bin/sh', '-c', $cmd], \undef, \$stdout, \$stderr);
    my $result = $? >> 8;
    $< = $> = 0;
    $( = $) = 0;
    die "changing euid back to root: $!" if $> != 0;

    if (defined $status && $status != $result) {
        print "command '$cmd' did not exit with expected code $status but with $result:\n";
        print $$_[2];
        print $$_[4];
        fail_debug;
    }
    # copy stdout and stderr back to caller @_
    $_[2] = \$stdout;
    $_[4] = \$stderr;
    return $result;
}

# Execute a command as a particular user, and check the exit code
# Arguments: <user> <command> [<expected exit code>] [<description>]
sub program_ok {
    my ($user, $cmd, $exit, $description) = @_;
    $exit ||= 0;
    $description ||= $cmd;
    my $outref;
    ok ((exec_as $user, $cmd, \$outref, $exit) == $exit, $description);
}

# Execute a command as a particular user, and check the exit code and output
# (merged stdout/stderr).
# Arguments: <user> <command> <expected exit code> <expected output> [<description>]
sub is_program_out {
    my $outref;
    my $result = exec_as $_[0], $_[1], $outref;
    is $result, $_[2], $_[1] or fail_debug;
    is ($$outref, $_[3], (defined $_[4] ? $_[4] : "correct output of $_[1]")) or fail_debug;
}

# Execute a command as a particular user, and check the exit code and output
# against a regular expression (merged stdout/stderr).
# Arguments: <user> <command> <expected exit code> <expected output re> [<description>]
sub like_program_out {
    my $outref;
    my $result = exec_as $_[0], $_[1], $outref;
    is $result, $_[2], $_[1] or fail_debug;
    like ($$outref, $_[3], (defined $_[4] ? $_[4] : "correct output of $_[1]")) or fail_debug;
}

# Execute a command as a particular user, check the exit code, and check that
# the output does not match a regular expression (merged stdout/stderr).
# Arguments: <user> <command> <expected exit code> <expected output re> [<description>]
sub unlike_program_out {
    my $outref;
    my $result = exec_as $_[0], $_[1], $outref;
    is $result, $_[2], $_[1] or fail_debug;
    unlike ($$outref, $_[3], (defined $_[4] ? $_[4] : "correct output of $_[1]")) or fail_debug;
}

# Check that all PostgreSQL related directories are empty and no
# postgres processes are running. Should be called at the end
# of all tests. Does 8 tests.
sub check_clean {
    note "Cleanup";
    is (`pg_lsclusters -h`, '', 'Cleanup: No clusters left behind');
    my $ps = ps 'postgres';
    if ($ps ne "") {
        usleep $delay;
        $ps = ps 'postgres';
    }
    is ($ps, '', 'No postgres processes left behind');

    my @check_dirs = ('/etc/postgresql', '/var/lib/postgresql',
        '/var/run/postgresql');
    foreach (@check_dirs) {
        if (-d) {
            ok_dir $_, [], "No files in $_ left behind";
        } else {
            pass "Directory $_ does not exist";
        }
    }
    # we always want /var/log/postgresql/ to exist, so that logrotate does not
    # complain about missing directories
    ok_dir '/var/log/postgresql', [], "No files in /var/log/postgresql left behind";

    # prefer ss over netstat (until all debian/tests/control files in postgresql-* have been updated)
    unless (-x '/bin/netstat' and not -x '/bin/ss') {
        is `ss --no-header -tlp 'sport >= 5432 and sport <= 5439'`, '',
            'PostgreSQL TCP ports are closed';
    } else {
        is `netstat -avptn 2>/dev/null | grep ":543[2-9]\\b.*LISTEN"`, '',
            'PostgreSQL TCP ports are closed';
    }
    is next_free_port(), 5432, "Next free port is 5432";
}

1;
