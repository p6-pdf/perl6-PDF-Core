use v6;
use Test;
plan 7;

use PDF::IO::IndObj;
use PDF::Grammar::PDF;
use PDF::Grammar::PDF::Actions;
use PDF::Grammar::Test :is-json-equiv;

my $actions = PDF::Grammar::PDF::Actions.new;

my $input = '42 5 obj true endobj';
PDF::Grammar::PDF.parse($input, :$actions, :rule<ind-obj>)
    // die "parse failed";
my $ast = $/.ast;
my $ind-obj = PDF::IO::IndObj.new( |%$ast, :$input );
is $ind-obj.obj-num, 42, '$.obj-num';
is $ind-obj.gen-num, 5, '$.gen-num';
isa-ok $ind-obj.object, Bool;
is $ind-obj.object, True, '$.object';
my $content = $ind-obj.content;
isa-ok $content, Pair;
is-json-equiv $content, (:bool), '$.content';
is-json-equiv $ind-obj.ast, $ast, 'ast regeneration';
