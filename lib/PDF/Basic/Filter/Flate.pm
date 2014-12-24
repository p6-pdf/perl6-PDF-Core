use v6;
# based on Perl 5's PDF::API::Basic::PDF::Filter::ASCIIHexDecode

class PDF::Basic::Filter::Flate;

use Compress::Zlib;

# Maintainer's Note: Flate is described in the PDF 1.7 spec in section 3.3.3.
# See also http://www.libpng.org/pub/png/book/chapter09.html - PNG predictors

method encode(Str $input) {

    if $input ~~ m{(<-[\x0 .. \xFF]>)} {
        die 'illegal wide byte: U+' ~ $0.ord.base(16)
    }

    compress( $input.encode('latin-1') ).decode('latin-1');
}

multi method post-prediction(Buf $decoded, 
                             Int :$Predictor! where { $_ <= 1}, #| predictor function
    ) {
    $decoded; # noop
}

multi method post-prediction(Buf $decoded, 
                             Int :$Predictor! where { $_ == 2}, #| predictor function
    ) {
    die "Flate/LZW TIFF predictive filters - NYI";
}

multi method post-prediction(Buf $decoded,               #| input stream
                             Int :$Predictor! where { $_ >= 10 and $_ <= 15}, #| predictor function
                             Int :$Columns = 1,          #| number of samples per row
                             Int :$Colors = 1,           #| number of colors per sample
                             Int :$BitsPerComponent = 8, #| number of bits per color
    ) {


    my $bytes-per-col = floor(($Colors * $BitsPerComponent  +  7) / 8);
    my $bytes-per-row = $bytes-per-col * $Columns;
    my @output;

    my $idx = 0;
    my @up = 0 xx $bytes-per-row;

    loop {
        # PNG prediction can vary from row to row
        last unless $idx < +$decoded;
        my $filter-byte = $decoded[$idx++];
        my @out;

        given $filter-byte {
            when 0 {
                # None
                @out.push: $decoded[$idx++]
                    for 1 .. $bytes-per-row;
            }
            when 1 {
                # Sub - 11
                for 1 .. $bytes-per-row -> $i {
                    my $left-byte = $i <= $bytes-per-col ?? 0 !! @out[* - $bytes-per-col];
                    @out.push: ($decoded[$idx++] + $left-byte) % 256;
                }
            }
            when 2 {
                # Up - 12
                for 1 .. $bytes-per-row {
                    my $up-byte = @up[ +@out ];
                    @out.push: ($decoded[$idx++] + $up-byte) % 256;
                }
            }
            when  3 {
                # Average - 13
                for 1 .. $bytes-per-row -> $i {
                    my $left-byte = $i <= $bytes-per-col ?? 0 !! @out[* - $bytes-per-col];
                    my $up-byte = @up[ +@out ];
                    @out.push: ($decoded[$idx++] + floor( ($left-byte + $up-byte)/2 )) % 256;
                }
            }
            when 4 {
                # Paeth - 14
                for 1 .. $bytes-per-row -> $i {
                    my $left-byte = $i <= $bytes-per-col ?? 0 !! @out[* - $bytes-per-col];
                    my $up-byte = @up[ +@out ];
                    my $up-left-byte = $i <= $bytes-per-col ?? 0 !! @up[ +@out - $bytes-per-col];
                    my $p = $left-byte + $up-byte - $up-left-byte;
                    
                    my $pa = abs($p - $left-byte);
                    my $pb = abs($p - $up-byte);
                    my $pc = abs($p - $up-left-byte);
                    my $nearest;

                    if $pa <= $pb and $pa <= $pc {
                        $nearest = $left-byte;
                    }
                    elsif $pb <= $pc {
                        $nearest = $up-byte;
                    }
                    else {
                        $nearest = $up-left-byte
                    }

                    @out.push: ($decoded[$idx++] + $nearest) % 256;
                }
            }
            default {
                die "bad predictor byte: $_";
            }
        }

        @up = @out;
        @output.push: @out;
    }
    return buf8.new: @output;
}

multi method post-prediction(Buf $decoded, 
                             Int :$Predictor
    ) {
    die "Uknown Flate/LZW predictor function: $Predictor";
}

method decode(Str $input, Hash :$dict = {} --> Str) {

    my $buf = uncompress( $input.encode('latin-1') );

    my $decode-params = $dict<DecodeParams> // $dict;

    $buf = $.post-prediction( $buf, |%$decode-params )
        if $dict<Predictor>.defined;

    $buf.decode('latin-1');
}