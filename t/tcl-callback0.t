# Tcl.pm-only (no Tkx) equivalent of tcl-callback.t

use warnings;
use strict;
use Test;

plan tests => 7;

use Tcl;

my $i = new Tcl;
$i->Init;

$i->call("set", "foo", sub {
    ok @_, 2;
    ok "@_", "a b c";
});
ok $i->call("set", "foo"), qr/^::perl::CODE\(0x/;
$i->Eval('[set foo] a {b c}');

$i->call("set", "foo", [sub {
    ok @_, 4;
    ok "@_", "a b c d e f";
}, "d", "e f"]);
$i->Eval('[set foo] a {b c}');

$i->call("set", "foo", [sub {
    ok @_, 6;
    ok "@_", "2 3 a b c d";
}, Tcl::Ev('[expr 1+1]', '[expr 1+2]'), "c", "d"]);
$i->Eval('eval [set foo] a b');
