use v6;

class PDF::IO::Crypt {

    use OpenSSL:ver(v0.1.4..*);
    use OpenSSL::Digest;

    use PDF::DAO::Dict;
    use PDF::IO::Util :resample;
    use PDF::DAO::Type::Encrypt;

    has UInt $!R;         #| encryption revision
    has Bool $!EncryptMetadata;
    has uint8 @!O;        #| computed owner password
    has UInt $!key-bytes; #| encryption key length
    has uint8 @!doc-id;   #| /ID entry in document root
    has uint8 @!U;        #| computed user password
    has uint8 @!P;        #| permissions, unpacked as uint8
    has $.key is rw;      #| encryption key
    has Bool $.is-owner is rw; #| authenticated against, or created by, owner

    # Taken from [PDF 1.7 Algorithm 3.2 - Standard Padding string]
     our @Padding  = 
	0x28, 0xbf, 0x4e, 0x5e,
	0x4e, 0x75, 0x8a, 0x41,
	0x64, 0x00, 0x4e, 0x56,
	0xff, 0xfa, 0x01, 0x08,
	0x2e, 0x2e, 0x00, 0xb6,
	0xd0, 0x68, 0x3e, 0x80,
	0x2f, 0x0c, 0xa9, 0xfe,
	0x64, 0x53, 0x69, 0x7a;

    sub format-pass(Str $pass --> List) {
	my uint8 @pass-padded = flat $pass.NFKC.list, @Padding;
	@pass-padded[0..31];
    }

    submethod TWEAK(:$doc!, Str :$owner-pass, |c) {
        $owner-pass
            ?? self.generate( :$doc, :$owner-pass, |c)
            !! self.load( :$doc, |c)
    }

    #| perform initial document encryption
    method generate(:$doc!,
                    Str  :$owner-pass!,
                    Str  :$user-pass = '',
                    UInt :$!R = 3,  #| revision (2 is faster)
                    UInt :$V = self.type eq 'AESV2' ?? 4 !! 2,
                    Bool :$!EncryptMetadata = True,
                    UInt :$Length = $V > 1 ?? 128 !! 40,
                    Int  :$P = -64,  #| permissions mask
                    --> PDF::DAO::Type::Encrypt
        ) {

        die "this document is already encrypted"
            if $doc.Encrypt;

	die "invalid encryption key length: $Length"
            unless 40 <= $Length <= 128
            && ($V > 1 || $Length == 40)
	    && $Length %% 8;

	$!key-bytes = $Length +> 3;
	$doc.generate-id
	    unless $doc<ID>;

	@!doc-id = $doc<ID>[0].ords;
	my uint8 @p8 = resample([ $P ], 32, 8).reverse;
	@!P = @p8;

        my uint8 @owner-pass = format-pass($owner-pass);
        my uint8 @user-pass = format-pass($user-pass);

	@!O = self.compute-owner( @owner-pass, @user-pass );

        @!U = self.compute-user( @user-pass, :$!key );
        $!is-owner = True;

        my $O = hex-string => [~] @!O.map: *.chr;
        my $U = hex-string => [~] @!U.map: *.chr;

        my %dict = :$O, :$U, :$P, :$!R, :$V, :Filter<Standard>;

        if $V >= 4 {
            %dict<CF> = {
                :StdCF{
                    :CFM{ :name(self.type) },
                },
            };
            %dict<StmF> = :name<StdCF>;
            %dict<StrF> = :name<StdCF>;
        }

        %dict<Length> = $Length unless $V == 1;
        %dict<EncryptMetadata> = False
            if $!R >= 4 && ! $!EncryptMetadata;

        my $enc = $doc.Encrypt = %dict;

        # make it indirect. keep the trailer size to a minimum
        $enc.is-indirect = True;
        $enc;
    }

    method load(PDF::DAO::Dict :$doc!,
                UInt :$!R!,
                Bool :$!EncryptMetadata = True,
                UInt :$V!,
                Int  :$P!,
                Str  :$O!,
                Str  :$U!,
                UInt :$Length = 40,
                Str  :$Filter = 'Standard',
               ) {

        with $doc<ID>[0] {
	    @!doc-id = .ords;
        }
        else {
            die 'This PDF lacks an ID.  The document cannot be decrypted'
        }
	@!P = resample([ $P ], 32, 8).reverse;
	@!O = $O.ords;
	@!U = $U.ords;

	die "Only the Standard encryption filter is supported"
	    unless $Filter eq 'Standard';

	my uint $key-bits = $V == 1 ?? 40 !! $Length;
        $key-bits *= 8 if $key-bits <= 16;  # assume bytes
	die "invalid encryption key length: $key-bits"
	    unless 40 <= $key-bits <= 128
	    && $key-bits %% 8;

	$!key-bytes = $key-bits +> 3;
    }

    use OpenSSL::NativeLib;
    use NativeCall;

    sub RC4_set_key(Blob, int32, Blob) is native(&gen-lib) { ... }
    sub RC4(Blob, int32, Blob, Blob) is native(&gen-lib) { ... }

    method rc4-crypt(Blob $key, Blob $in) {
        # from openssl/rc4.h:
        # typedef struct rc4_key_st {
        #   RC4_INT x, y;
        #   RC4_INT data[256];
        # } RC4_KEY;

        constant RC4_INT = uint32;
        my \rc4 = Buf[RC4_INT].new;
        rc4.reallocate(258);
        RC4_set_key(rc4, $key.bytes, $key);
        my $out = buf8.new;
        $out.reallocate($in.bytes)
            if $in.bytes;
        RC4(rc4, $in.bytes, $in, $out);
        $out;
    }

    method !do-iter-crypt(Blob $code, @pass, $n=0, $m=19) {
        my Buf $crypt .= new: @pass;
	for $n ... $m -> \iter {
	    my Buf $key .= new: $code.map( * +^ iter );
	    $crypt = $.rc4-crypt($key, $crypt);
	}
	$crypt;
    }

    method compute-user(@pass-padded, :$key! is rw) {
	# Algorithm 3.2
	my uint8 @input = flat @pass-padded,       # 1, 2
	                       @!O,                # 3
                               @!P,                # 4
                               @!doc-id;           # 5


	@input.append: 0xff xx 4             # 6
	    if $!R >= 4 && ! $!EncryptMetadata;

	my uint $n = 5;
	my uint $reps = 1;

	if $!R >= 3 {                        # 8
	    $n = $!key-bytes;
	    $reps = 51;
	}

	$key = Buf.new: @input;

	for 1 .. $reps {
	    $key = md5($key);
	    $key.reallocate($n)
		unless $key.elems <= $n;
	}

	my Buf $pass .= new: @Padding;

	my \computed = do if $!R >= 3 {
	    # Algorithm 3.5 steps 1 .. 5
	    $pass.append: @!doc-id;
	    $pass = md5( $pass );
	    self!do-iter-crypt($key, $pass);
	}
	else {
	    # Algorithm 3.4
	    $.rc4-crypt($key, $pass);
	}

        computed.list;
    }

    method !auth-user-pass(@pass) {
	# Algorithm 3.6
        my $key;
	my uint8 @computed = $.compute-user( @pass, :$key );
	my uint8 @expected = $!R >= 3
            ?? @!U[0 .. 15]
            !! @!U;

	@computed eqv @expected
	    ?? $key
	    !! Nil
    }

    method !compute-owner-key(@pass-padded) {
        # Algorithm 3.7 steps 1 .. 4
	my Buf $key .= new: @pass-padded;   # 1

	my uint $n = 5;
	my uint $reps = 1;

	if $!R >= 3 {                       # 3
	    $n = $!key-bytes;
	    $reps = 51;
	}

	for 1..$reps {
	    $key = md5($key);
	    $key.reallocate($n)
		unless $key.elems <= $n;
	}

	$key;                               # 4
    }

    method compute-owner(@owner-pass, @user-pass) {
        # Algorithm 3.3
	my Buf \key = self!compute-owner-key( @owner-pass );    # Steps 1..4

        my Buf $owner .= new: @user-pass;
        
	if $!R == 2 {      # 2 (Revision 2 only)
	    $owner = $.rc4-crypt(key, $owner);
	}
	elsif $!R >= 3 {   # 2 (Revision 3 or greater)
	    $owner = self!do-iter-crypt(key, $owner);
	}

        $owner.list;
    }

    method !auth-owner-pass(@pass) {
	# Algorithm 3.7
	my Buf \key = self!compute-owner-key( @pass );    # 1
	my Buf $user-pass .= new: @!O;
	if $!R == 2 {      # 2 (Revision 2 only)
	    $user-pass = $.rc4-crypt(key, $user-pass);
	}
	elsif $!R >= 3 {   # 2 (Revision 3 or greater)
	    $user-pass = self!do-iter-crypt(key, $user-pass, 19, 0);
	}
	$.is-owner = True;
	self!auth-user-pass($user-pass.list);          # 3
    }

    method authenticate(Str $pass, Bool :$owner) {
	$.is-owner = False;
	my uint8 @pass = format-pass( $pass );
	self.key = (!$owner && self!auth-user-pass( @pass ))
	    || self!auth-owner-pass( @pass )
	    or die "unable to decrypt this PDF with the given password";
    }

}