use strict; 

use lib 't';
use TestLib;

use Test::More;

if (! TestLib::have_jit()) {
    ok 1, "No JIT tests on this architecture";
    done_testing();
    exit;
}

my ($os, $osversion) = os_release();

foreach my $v (@MAJORS) {
    if ($v < 11) {
        ok 1, "No JIT support on $v";
        next;
    }
    note "$v";

    program_ok 'root', "pg_createcluster $v main --start", 0;

    my $jit_default = $v == '11' ? 'off' : 'on';
    like_program_out 'postgres', "psql -Xatc 'show jit'", 0, qr/$jit_default/, "JIT is $jit_default by default";
    unlike_program_out 'postgres', "psql -c 'explain (analyze) select count(*) from pg_class'", 0, qr/JIT/,
        "No JIT on cheap query";

    if ($v > 11 and # skip JIT tests on 11, it supports only up to LLVM 15 (removed in trixie)
            not ($v >= 18 and $os eq 'ubuntu' and $osversion <= 20.04)) { # PG18 needs llvm 13+, but focal has only 10 and 12
        program_ok 'root', "pg_conftool $v main set seq_page_cost 100000", 0;
        program_ok 'root', "pg_conftool $v main set random_page_cost 100000", 0;
        program_ok 'root', "pg_ctlcluster $v main reload", 0;
        like_program_out 'postgres', "psql -c 'explain (analyze) select count(*) from pg_class'", 0, qr/Timing: Generation .* ms/,
            "Expensive query is JITed";
    }

    program_ok 'root', "pg_dropcluster --stop $v main", 0;
    check_clean;
}

done_testing();

# vim: filetype=perl
