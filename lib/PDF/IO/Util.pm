use v6;

module PDF::IO::Util {

    #= resample a buffer as n-bit to m-bit unsigned integers
    proto sub resample( $, $, $ --> Array) is export(:resample) {*};
    multi sub resample( $nums!, 8, 4)  { my uint8  @s = flat $nums.list.map: { ($_ +> 4, $_ +& 15) } }
    multi sub resample( $nums!, 4, 8)  { my uint8  @s = flat $nums.list.map: -> \hi, \lo { hi +< 4  +  lo } }
    multi sub resample( $nums!, 8, 16) { my uint16 @s = flat $nums.list.map: -> \hi, \lo { hi +< 8  +  lo } }
    multi sub resample( $nums!, 8, 32) { my uint32 @s = flat $nums.list.map: -> \b1, \b2, \b3, \b4 { b1 +< 24  +  b2 +< 16  +  b3 +< 8  +  b4 } }
    multi sub resample( $nums!, 16, 8) { my uint8  @s = flat $nums.list.map: { ($_ +> 8, $_) } }
    multi sub resample( $nums!, 32, 8) { my uint8  @s = flat $nums.list.map: { ($_ +> 24, $_ +> 16, $_ +> 8, $_) } }
    multi sub resample( $nums!, UInt $n!, UInt $ where $n) { $nums }

    sub get-bit($num, $bit) { $num +> ($bit) +& 1 }
    sub set-bit($bit) { 1 +< ($bit) }
    multi sub resample( $nums!, UInt $n!, UInt $m!) is default {
        warn "unoptimised $n => $m bit sampling";
        flat gather {
            my int $m0 = 1;
            my int $sample = 0;

            for $nums.list -> $num is copy {
                for 1 .. $n -> int $n0 {

                    $sample += set-bit( $m - $m0)
                        if get-bit( $num, $n - $n0);

                    if ++$m0 > $m {
                        take $sample;
                        $sample = 0;
                        $m0 = 1;
                    }
                }
            }

            take $sample if $m0 > 1;
        }
    }
    #| variable resampling, e.g. to decode/encode:
    #|   obj 123 0 << /Type /XRef /W [1, 3, 1]
    multi sub resample( $nums!, 8, Array $W!)  {
        my uint $j = 0;
        my @samples;
        while $j < +$nums {
            my @sample = $W.keys.map: -> $i {
                my uint $s = 0;
                for 1 .. $W[$i] {
                    $s *= 256;
                    $s += $nums[$j++];
                }
                $s;
            }
            @samples.push: @sample;
        }
	@samples;
    }

    multi sub resample( $num-sets, Array $W!, 8)  {
	my uint8 @sample;
         for $num-sets.list -> Array $nums {
            my uint $i = 0;
            for $nums.list -> uint $num is copy {
                my uint8 @bytes;
                for 1 .. $W[$i++] {
                    @bytes.unshift: $num;
                    $num div= 256;
                }
                @sample.append: @bytes;
            }
        }
	flat @sample;
    }

}