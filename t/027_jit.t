use strict; 

use lib 't';
use TestLib;

use Test::More;

my $arch = `dpkg --print-architecture`;
chomp $arch;
if (grep { $_ eq $arch} qw(alpha hppa hurd-i386 ia64 kfreebsd-amd64 kfreebsd-i386 loong64 m68k powerpc riscv64 sh4 sparc64 x32)) {
    ok 1, "No JIT tests on $arch";
    done_testing();
    exit;
}

foreach my $v (@MAJORS) {
    if ($v < 11) {
        ok 1, "No JIT support on $v";
        next;
    }
    note "$v";

    program_ok 'root', "pg_createcluster $v main --start", 0;

    my $jit_default = $v == '11' ? 'off' : 'on';
    like_program_out 'postgres', "psql -Xatc 'show jit'", 0, qr/$jit_default/, "JIT is $jit_default by default";
    program_ok 'root', "pg_conftool $v main set jit on", 0, "Turn on JIT on PG11" if ($v == 11);
    program_ok 'root', "pg_ctlcluster $v main reload", 0 if ($v == 11);

    unlike_program_out 'postgres', "psql -c 'explain (analyze) select count(*) from pg_class'", 0, qr/JIT/,
        "No JIT on cheap query";
    program_ok 'root', "pg_conftool $v main set seq_page_cost 100000", 0;
    program_ok 'root', "pg_conftool $v main set random_page_cost 100000", 0;
    program_ok 'root', "pg_ctlcluster $v main reload", 0;
    like_program_out 'postgres', "psql -c 'explain (analyze) select count(*) from pg_class'", 0, qr/Timing: Generation .* ms/,
        "Expensive query is JITed";

    program_ok 'root', "pg_dropcluster --stop $v main", 0;
    check_clean;
}

done_testing();

# vim: filetype=perl
