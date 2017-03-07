use v6;
use Test;
plan 31;

use PDF::DAO::Dict;

{
    # basic tests
    class TestDict
    is PDF::DAO::Dict {
        use PDF::DAO::Tie;
        has Int $.IntReq is entry(:required);
        has Hash $.DictInd is entry(:indirect);
    }

    my $dict;
    lives-ok { $dict = TestDict.new( :dict{ :IntReq(42) } ) }, 'dict sanity';
    is $dict.IntReq, 42, "dict accessor sanity";
    lives-ok { $dict.IntReq = 43 }, 'dict accessor assignment sanity';
    quietly {
        dies-ok { $dict.IntReq = 'urrgh' }, 'dict accessor assignment typecheck';
        is $dict.IntReq, 43, 'dict accessor typecheck';
        lives-ok { $dict = TestDict.new( :dict{ :IntReq<oops> } ) }, 'dict typecheck bypass';
        dies-ok {$dict.IntReq}, "dict accessor - typecheck";
        dies-ok { TestDict.new( :dict{ } ) }, 'dict without required - dies';
    }
    $dict = TestDict.new( :dict{ :IntReq(42), :DictInd{}, } );
    ok $dict.DictInd.is-indirect, 'indirect entry';
}

{
    # container tests
    class TestDict2
    is PDF::DAO::Dict {
        use PDF::DAO::Tie;
        has UInt @.Pos is entry;
        my subset NegInt of Int where * < 0;
        has UInt @.LenThree is entry(:len(3));
        has NegInt %.Neg is entry;
    }

    my $dict;
    lives-ok { $dict = TestDict2.new( :dict{ :Pos[3, 4], :Neg{ :n1(-7),  :n2(-8) } } ) }, 'container sanity';
    is $dict.Pos[1], 4, 'array container deref sanity';
    lives-ok { $dict.Pos[1] = 5 }, 'array assignment sanity';
    dies-ok { $dict.Pos[1] = -5 }, 'array assignment typecheck';

    is $dict.Neg<n2>,-8, 'hash container deref sanity';
    lives-ok { $dict.Neg<n2> = -5 }, 'hash assignment sanity';
    dies-ok { $dict.Neg<n2> = 5 }, 'hash assignment typecheck';

    dies-ok { $dict.LenThree = [10, 20] }, 'length check, invalid';
    lives-ok { $dict.LenThree = [10, 20, 30] }, 'length check, valid';
}

{
    # coercement tests
    my role MyRole {};
    class TestDict3
    is PDF::DAO::Dict {
        use PDF::DAO::Tie;

        multi sub coerce($v, MyRole) { $v does MyRole }
        has MyRole $.Coerced is entry(:&coerce);
    }

    my $dict = TestDict3.new( :dict{ :Coerced(42) } );
    is $dict.Coerced, 42, 'coercement';
    does-ok $dict.Coerced, MyRole, 'coercement';
}

{
    # inheritance tests
    class Node
        is PDF::DAO::Dict {
        use PDF::DAO::Tie;
        has PDF::DAO::Dict $.Resources is entry(:inherit);
        has PDF::DAO::Dict $.Parent is entry;
    }

    my $Parent = Node.new( :dict{ :Resources{ :got<parent> }  } );
    my $child-with-entry = Node.new( :dict{ :Resources{ :got<child> }, :$Parent, } );
    my $child-without-entry = Node.new( :dict{ :$Parent, } );
    my $orphan = Node.new( :dict{ } );
    my $two-deep = Node.new( :dict{ :Parent($child-without-entry) } );
    my $cyclical = Node.new( :dict{ } );
    $cyclical<Parent> = $cyclical;

    is $Parent.Resources<got>, 'parent', 'parent accessor';
    is $Parent<Resources><got>, 'parent', 'parent direct';

    is $child-with-entry.Resources<got>, 'child', 'child with';
    is $child-with-entry<Resources><got>, 'child', 'child with, direct';
    is $child-without-entry.Resources<got>, 'parent', 'child without';
    nok $child-without-entry<Resources>, 'child without, direct';
    nok $orphan.Resources, 'orphan';
    is $two-deep.Resources<got>, 'parent', 'child inheritance (2 levels)';

    $child-without-entry<Resources><got> = 'child';
    is $child-with-entry.Resources<got>, 'child', 'resources insertion, child';
    is $Parent.Resources<got>, 'parent', 'resources insertion, parent';

    dies-ok {$cyclical.Resources}, 'inheritance cycle detection';
}

done-testing;