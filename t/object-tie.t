use v6;
use Test;

use PDF::Reader;
use PDF::Writer;
use PDF::Storage::Serializer;
use PDF::Object;

sub prefix:</>($name){ PDF::Object.compose(:$name) };

my $reader = PDF::Reader.new();

$reader.open( 't/pdf/pdf.in' );

my $root-obj = $reader.root.object;
is-deeply $root-obj.reader, $reader, 'root object .reader';
is $root-obj.obj-num, 1, 'root object .obj-num';
is $root-obj.gen-num, 0, 'root object .gen-num';

# sanity

ok $root-obj<Type>:exists, 'root object existance';
ok $root-obj<Wtf>:!exists, 'root object non-existance';
lives-ok {$root-obj<Wtf> = 'Yup' }, 'key stantiation - lives';
ok $root-obj<Wtf>:exists, 'key stantiation';
is $root-obj<Wtf>, 'Yup', 'key stantiation';
lives-ok {$root-obj<Wtf>:delete}, 'key deletion - lives';
ok $root-obj<Wtf>:!exists, 'key deletion';

my $type = $root-obj<Type>;
is $type, 'Catalog', '$root-obj<Type>';

# start fetching indirect objects

my $Pages := $root-obj<Pages>;
is $Pages<Type>, 'Pages', 'Pages<Type>';
is-deeply $Pages.reader, $reader, 'root has deref - stickyness';

my $Kids = $Pages<Kids>;
is-deeply $Kids.reader, $reader, 'hash -> array deref - reader stickyness';
my $kid := $Kids[0];
is-deeply $kid.reader, $reader, 'array -> hash deref - reader stickyness';
is $kid<Type>, 'Page', 'Kids[0]<Type>';

is $Pages<Kids>[0]<Parent>.WHERE, $Pages.WHERE, '$Pages<Kids>[0]<Parent>.WHERE == $Pages.WHERE';

my $contents = $kid<Contents>;
is $contents.Length, 45, 'contents.Length';
is $contents.encoded, q:to'--END--'.chomp, 'contents.encoded';
BT
/F1 24 Tf
100 100 Td (Hello, world!) Tj
ET
--END--

# demonstrate low level construction of a PDF. First page is copied from an
# input PDF. Second page is constructed from scratch.

lives-ok {
    my $Resources = $Pages<Kids>[0]<Resources>;
    my $new-page = PDF::Object.compose( :dict{ :Type(/'Page'), :MediaBox[0, 0, 420, 595], :$Resources } );
    my $contents = PDF::Object.compose( :stream{ :decoded("BT /F1 24 Tf  100 250 Td (Bye for now!) Tj ET" ), :dict{ :Length(46) } } );
    $new-page<Contents> = $contents;
    $new-page<Parent> = $Pages;
    $Pages<Kids>.push: $new-page;
    $Pages<Count> = $Pages<Count> + 1;
    }, 'page addition';

$contents<Length> = 41;
is $contents.Length, 41, '$stream<Length> is tied to $stream.Length';
$contents<Length>:delete;
ok !$contents.Length.defined, '$stream<Length>:delete propagates to $stream.Length';

my $new-root = PDF::Object.compose( :dict{ :Type(/'Catalog') });
$new-root<Outlines> = $root-obj<Outlines>;
$new-root<Pages> = $root-obj<Pages>;

my $result = PDF::Storage::Serializer.new.body($new-root);
my $root = $result<trailer><dict><Root>;
my $objects = $result<objects>;

# write the two page pdf
my $ast = :pdf{ :version(1.2), :body{ :$objects } };
my $writer = PDF::Writer.new( :$root );
ok 't/hello-and-bye.pdf'.IO.spurt( $writer.write($ast), :enc<latin-1> ), 'output 2 page pdf';

done;
