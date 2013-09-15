#!/usr/bin/env perl
# 
# TODO
#   instructions
#   understand other value formats
#
# FUTURE
#   configurable bar size
#   configurable box size
#   configurable margins
#
# LICENSE
#   This is free and unencumbered software released into the public domain.
#
#   Anyone is free to copy, modify, publish, use, compile, sell, or
#   distribute this software, either in source code form or as a compiled
#   binary, for any purpose, commercial or non-commercial, and by any
#   means.
#
#   In jurisdictions that recognize copyright laws, the author or authors
#   of this software dedicate any and all copyright interest in the
#   software to the public domain. We make this dedication for the benefit
#   of the public at large and to the detriment of our heirs and
#   successors. We intend this dedication to be an overt act of
#   relinquishment in perpetuity of all present and future rights to this
#   software under copyright law.
#
#   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
#   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
#   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
#   IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
#   OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
#   ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
#   OTHER DEALINGS IN THE SOFTWARE.
#
#   For more information, please refer to <http://unlicense.org/>


use strict;
use warnings;
use POSIX;


our %CONFIG;
our %LAYOUT;
our @VALUES;
our %TEMPLATES;


our %COLORS = (
    # digit, multiplier, tolerance
    Bk => [0, 0, undef],
    Bn => [1, 1, '1'],
    Rd => [2, 2, '2'],
    Og => [3, 3, undef],
    Yw => [4, 4, undef],
    Gn => [5, 5, '½'],
    Bl => [6, 6, '¼'],
    Vt => [7, 7, undef],
    Gy => [8, 8, undef],
    Wt => [9, 9, undef],
    Gd => [undef, -1, '5'],
    Sr => [undef, -2, '10'],
);
our %COLOR_DIGIT;
our %COLOR_MULTIPLIER;
our %COLOR_TOLERANCE;
our %DIGIT_COLOR;
our %MULTIPLIER_COLOR;
our %TOLERANCE_COLOR;


sub DEBUG_DUMP {
    my $obj = shift;
    my $lvl = shift || 0;
    my $ind = '    ' x $lvl;
    if ( 'HASH' eq ref $obj ) {
        foreach my $key ( sort keys %$obj ) {
            my $val = $obj->{$key} // '';
            if ( ref $val ) {
                print "$ind$key -- ", ref($val), "\n";
                DEBUG_DUMP($val, $lvl + 1);
            }
            else {
                print "$ind$key -- $val\n";
            }
        }
        return;
    }
    if ( 'ARRAY' eq ref $obj ) {
        foreach my $key ( 0 .. $#{$obj} ) {
            my $val = $obj->[$key] // '';
            if ( ref $val ) {
                print "$ind$key -- ", ref($val), "\n";
                DEBUG_DUMP($val, $lvl + 1);
            }
            else {
                print "$ind$key -- $val\n";
            }
        }
        return;
    }
    print "$ind$obj\n";
}


# also strips extension (if any)
sub basename {
    my $f = shift || die;
    my @f = split '/', $f;
    $f = pop(@f);
    @f = split m/\./, $f;
    pop(@f) if scalar(@f) > 1;
    $f = join '.', @f;
    return $f;
}


# turns a string value into an array of colors
sub value_to_colors {
    my $value = shift // die;
    my $mult = 0;
    my @colors;
    if ('0' eq $value) {
        return [ 'Bk' ];
    }
    if ( 'k' eq substr($value, -1) ) {
        $value = substr($value, 0, length($value)-1);
        $mult += 3;
    }
    if ( 'M' eq substr($value, -1) ) {
        $value = substr($value, 0, length($value)-1);
        $mult += 6;
    }
    if ( $value < 10 ) {
        $value *= 1000;
        $mult -= 3;
    }
    my @values = split m//, $value;
    push @colors, $DIGIT_COLOR{shift(@values)};
    push @colors, $DIGIT_COLOR{shift(@values)};
    $mult += scalar(@values);
    push @colors, $MULTIPLIER_COLOR{$mult};
    return \@colors;
}


sub sort_colors {
    return $COLOR_MULTIPLIER{$a} <=> $COLOR_MULTIPLIER{$b};
}


# supports comments
sub file_read {
    my $file = shift || die;
    open(F, "<$file") or die("FAILED to open $file");
    my $content = join '', <F>;
    close(F) or die("FAILED to close $file");
    $content =~ s/#.*$//gm;
    return $content;
}


sub file_write {
    my $file = shift || die;
    my $body = shift || die;
    open(F, ">$file") or die("FAILED to open $file");
    print F $body;
    close(F) or die("FAILED to close $file");
}


sub lookups_compute {
    foreach my $c ( keys %COLORS ) {
        my($dig, $mult, $tol) = @{$COLORS{$c}};
        if ( defined $dig ) {
            $DIGIT_COLOR{$dig} = $c;
            $COLOR_DIGIT{$c} = $dig;
        }
        if ( defined $mult ) {
            $MULTIPLIER_COLOR{$mult} = $c;
            $COLOR_MULTIPLIER{$c} = $mult;
        }
        if ( defined $tol ) {
            $TOLERANCE_COLOR{$tol} = $c;
            $COLOR_TOLERANCE{$c} = $tol;
        }
    }
}


sub values_read {
    my $file = shift || die;
    my $content = file_read($file);
    $content =~ s/,/ /g;
    $content =~ s/\s+/ /g;
    $content =~ s/^ //;
    $content =~ s/ $//;
    foreach my $value ( split ' ', $content ) {
        if ($value =~ m/^([^=]+)=(.*)/ ) {
            $CONFIG{$1} = $2;
        }
        else {
            push @VALUES, $value;
        }
    }
}


sub config_compute {
    # defaults
    $CONFIG{'envelopes-across'} ||= 2;
    $CONFIG{'envelopes-down'}   ||= 3;
    $CONFIG{'resolution'}       ||= 100;
    $CONFIG{'envelope-height'}  ||= 3;
    $CONFIG{'envelope-width'}   ||= 4;
    $CONFIG{'fold-width'}       ||= 0.375;
    $CONFIG{'tolerance'}        ||= 5;  # percent

    # cleanup
    if ( $CONFIG{'tolerance'} and '%' eq substr($CONFIG{'tolerance'}, -1) ) {
        $CONFIG{'tolerance'} = substr($CONFIG{'tolerance'}, 0, -1);
    }

    # computed
    $CONFIG{'envelopes'} = scalar(@VALUES);
    $CONFIG{'envelopes-per-page'} = $CONFIG{'envelopes-across'} * $CONFIG{'envelopes-down'};
    $CONFIG{'pages'} = ceil($CONFIG{'envelopes'} / $CONFIG{'envelopes-per-page'});
    if ( $CONFIG{'tolerance-color'} and not $CONFIG{'tolerance'} ) {
        $CONFIG{'tolerance'} = $COLOR_TOLERANCE{$CONFIG{'tolerance-color'}};
    }
    if ( $CONFIG{'tolerance'} and not $CONFIG{'tolerance-color'} ) {
        $CONFIG{'tolerance-color'} = $TOLERANCE_COLOR{$CONFIG{'tolerance'}};
    }
}


sub X {
    my $x = shift;
    $x -= 1 if $x == $LAYOUT{'page-E'};
    $x += 1 if $x == $LAYOUT{'page-W'};
    return $x;
}


sub Y {
    my $y = shift;
    $y += 1 if $y == $LAYOUT{'page-N'};
    $y -= 1 if $y == $LAYOUT{'page-S'};
    return $y;
}


sub layout {
    my $resolution = $CONFIG{'resolution'};
    my $list;

    # inches to pixels
    $LAYOUT{'envelope-width'}  = $CONFIG{'envelope-width'}  * $resolution;
    $LAYOUT{'envelope-height'} = $CONFIG{'envelope-height'} * $resolution;
    $LAYOUT{'fold-width'}      = $CONFIG{'fold-width'}      * $resolution;
    $LAYOUT{'fold-height'}     = $LAYOUT{'envelope-height'} / 3.0;

    $LAYOUT{'page-N'} = 0;
    $LAYOUT{'page-E'} = $CONFIG{'envelopes-across'} * $LAYOUT{'envelope-width'};
    $LAYOUT{'page-S'} = $CONFIG{'envelopes-down'}   * $LAYOUT{'envelope-height'};
    $LAYOUT{'page-W'} = 0;

    # cuts
    $list = [];
    for ( my $i = 0; $i <= $CONFIG{'envelopes-across'}; $i++ ) {
        my $x = ($i * $LAYOUT{'envelope-width'});
        push @$list, X($x);
    }
    $LAYOUT{'cuts-vert'} = $list;
    $list = [];
    for ( my $i = 0; $i <= $CONFIG{'envelopes-down'}; $i++ ) {
        my $y = ($i * $LAYOUT{'envelope-height'});
        push @$list, Y($y);
    }
    $LAYOUT{'cuts-horz'} = $list;

    # folds
    $list = [];
    for ( my $i = 0; $i < $CONFIG{'envelopes-across'}; $i++ ) {
        my $xW = ( $i      * $LAYOUT{'envelope-width'});
        my $xE = (($i + 1) * $LAYOUT{'envelope-width'});
        $xW += $LAYOUT{'fold-width'};
        $xE -= $LAYOUT{'fold-width'};
        push @$list, X($xW);
        push @$list, X($xE);
    }
    $LAYOUT{'folds-vert'} = $list;
    $list = [];
    for ( my $i = 0; $i < $CONFIG{'envelopes-down'}; $i++ ) {
        my $y = $i * $LAYOUT{'envelope-height'};
        push @$list, Y($y +      $LAYOUT{'fold-height'} );
        push @$list, Y($y + (2 * $LAYOUT{'fold-height'}));
    }
    $LAYOUT{'folds-horz'} = $list;

    # envelopes
    my @envelopes;
    my $ix = 0;
    my $iy = 0;
    for ( my $e = 0; $e < $CONFIG{'envelopes-per-page'}; $e++ ) {
        my %envelope;
        my $N =  $iy      * $LAYOUT{'envelope-height'};
        my $E = ($ix + 1) * $LAYOUT{'envelope-width'};
        my $S = ($iy + 1) * $LAYOUT{'envelope-height'};
        my $W =  $ix      * $LAYOUT{'envelope-width'};
        $envelope{'ix'} = $ix;
        $envelope{'iy'} = $iy;
        $envelope{'N'} = Y($N);
        $envelope{'E'} = X($E);
        $envelope{'S'} = Y($S);
        $envelope{'W'} = X($W);
        for my $l ( 0 .. 2 ) {
            my $name = "leaf$l";
            $envelope{"$name-N"} = $N + (($l + 0) * $LAYOUT{'fold-height'});
            $envelope{"$name-E"} = $E + (      -1 * $LAYOUT{'fold-width'} );
            $envelope{"$name-S"} = $N + (($l + 1) * $LAYOUT{'fold-height'});
            $envelope{"$name-W"} = $W + (       1 * $LAYOUT{'fold-width'} );
            $envelope{"$name-cx"} = ($envelope{"$name-E"} + $envelope{"$name-W"}) / 2;
            $envelope{"$name-cy"} = ($envelope{"$name-N"} + $envelope{"$name-S"}) / 2;
            for my $k ( qw/ E W cx / ) {
                $envelope{"$name-$k"} = X($envelope{"$name-$k"});
            }
            for my $k ( qw/ N S cy / ) {
                $envelope{"$name-$k"} = Y($envelope{"$name-$k"});
            }
        }
        $ix++;
        if ( $ix == $CONFIG{'envelopes-across'} ) {
            $iy++;
            $ix = 0;
        }
        push @envelopes, \%envelope;
    }
    $LAYOUT{'envelopes'} = \@envelopes;
}


sub templates_read {
    my $separator = <DATA>;
    chomp $separator;
    my $key;
    my $val = '';
    foreach my $line ( <DATA> ) {
        chomp $line;
        if ( $line =~ m/^\Q$separator\E (.+)$/ ) {
            $TEMPLATES{$key} = $val if $key;
            $key = $1;
            $val = '';
            next;
        }
        $val .= $line . "\n";
    }
    $TEMPLATES{$key} = $val;
}


sub template_replace {
    my $name = shift || die;
    my $data = shift || {};
    my $body = $TEMPLATES{$name} || '';
    while ( $body =~ m/{{([^}]+)}}/ ) {
        my $key = $1;
        my $val = $key;
        my $eval = 0;
        if ( '=' eq substr($val, 0, 1) ) {
            $val = substr($val, 1);
            $eval = 1;
        }
        foreach my $k ( keys %$data ) {
            my $v = $data->{$k} // '';
            $val =~ s/(^|\s)\Q$k\E(\s|$)/$1$v$2/gm;
        }
        if ( $eval ) {
            $val = eval($val);
            print STDERR "FAILED to evaluate {{$key}}\n" if $@;
        }
        $body =~ s/{{\Q$key\E}}/$val/g;
    }
    return $body;
}


sub page_render {
    my $basename = shift || die;
    my $pagenum = shift // die;
    my @values = @_;
    my %data;   # used for multiple templates
    my $file = "$basename$pagenum.svg";

    print "==== RENDER $file == @values\n";

    my @hbars;
    my @vbars;
    my @digits;
    my @multipliers;
    my @tolerances;
    foreach my $color ( sort sort_colors keys(%COLORS) ) {
        %data = (
            color       => $color,
            digit       => $COLOR_DIGIT{$color},
            multiplier  => $COLOR_MULTIPLIER{$color},
            tolerance   => $COLOR_TOLERANCE{$color},
        );
        push @hbars,        template_replace('HBAR',        \%data);
        push @vbars,        template_replace('VBAR',        \%data);
        push @digits,       template_replace('DIGIT',       \%data) if defined $data{'digit'};
        push @multipliers,  template_replace('MULTIPLIER',  \%data) if defined $data{'multiplier'};
        push @tolerances,   template_replace('TOLERANCE',   \%data) if defined $data{'tolerance'};
    }

    my @cuts;
    foreach my $x ( @{$LAYOUT{'cuts-vert'}} ) {
        %data = (
            N => Y($LAYOUT{'page-N'}),
            E => $x,
            S => Y($LAYOUT{'page-S'}),
            W => $x,
        );
        my $cut = template_replace('CUT', \%data);
        push @cuts, $cut;
    }
    foreach my $y ( @{$LAYOUT{'cuts-horz'}} ) {
        %data = (
            N => $y,
            E => X($LAYOUT{'page-E'}),
            S => $y,
            W => X($LAYOUT{'page-W'}),
        );
        my $cut = template_replace('CUT', \%data);
        push @cuts, $cut;
    }

    my @folds;
    foreach my $x ( @{$LAYOUT{'folds-vert'}} ) {
        %data = (
            N => Y($LAYOUT{'page-N'}),
            E => $x,
            S => Y($LAYOUT{'page-S'}),
            W => $x,
        );
        my $fold = template_replace('FOLD', \%data);
        push @folds, $fold;
    }
    foreach my $y ( @{$LAYOUT{'folds-horz'}} ) {
        %data = (
            N => $y,
            E => X($LAYOUT{'page-E'}),
            S => $y,
            W => X($LAYOUT{'page-W'}),
        );
        my $fold = template_replace('FOLD', \%data);
        push @folds, $fold;
    }

    my @envelopes;
    foreach my $envelope ( @{$LAYOUT{'envelopes'}} ) {
        my $value = shift @values;
        next unless defined $value;
        my $template = 'ENVELOPE';
        %data = %$envelope;
        $data{'fold-width'} = $LAYOUT{'fold-width'};
        if ( $TEMPLATES{"ENVELOPE SPECIAL $value"} ) {
            $template = "ENVELOPE SPECIAL $value";
        }
        else {
            $template = "ENVELOPE VALUE $value" if $TEMPLATES{"ENVELOPE VALUE $value"};
            my $colors = value_to_colors($value);
            $data{'value'} = $value;
            $data{'tolerance'} = $CONFIG{'tolerance'};
            $data{'color-digit0'} = $colors->[0];
            $data{'color-digit1'} = $colors->[1];
            $data{'color-multiplier'} = $colors->[2];
            $data{'color-tolerance'} = $CONFIG{'tolerance-color'};
        }
        my $env = template_replace($template, \%data);
        push @envelopes, $env;
    }

    %data = (
        N           => $LAYOUT{'page-N'},
        E           => $LAYOUT{'page-E'},
        S           => $LAYOUT{'page-S'},
        W           => $LAYOUT{'page-W'},
        hbars       => join('', @hbars),
        vbars       => join('', @vbars),
        digits      => join('', @digits),
        multipliers => join('', @multipliers),
        tolerances  => join('', @tolerances),
        cuts        => join('', @cuts),
        folds       => join('', @folds),
        envelopes   => join("\n", @envelopes),
    );
    my $body = template_replace('PAGE', \%data);
    file_write($file, $body);
}


sub usage {
    my $error = shift;
    print STDERR "ERROR: $error\n" if $error;
    print "USAGE:  resistors.pl {values-file}\n";
    exit 1 if $error;
    exit 0;
}


sub main {
    my $values = shift || usage("missing values file");
    lookups_compute();
    values_read($values);
    config_compute();
    layout();
    templates_read();
    $values = basename($values);
    for ( my $page = 0; $page < $CONFIG{'pages'}; $page++ ) {
        my $beg = $page * $CONFIG{'envelopes-per-page'};
        my $end = $beg + $CONFIG{'envelopes-per-page'} - 1;
        $end = $CONFIG{'envelopes'} - 1 if $end >= $CONFIG{'envelopes'};
        page_render($values, $page, @VALUES[$beg .. $end]);
    }
}
main(@ARGV);


#   PIXELS
#       leaf0, leaf1, leaf2
#           N E S W cx cy
#       fold-width
#   STRINGS
#       value, tolerance
#       color-digit0, color-digit1, color-multiplier, color-tolerance
__DATA__
======================================================================
====================================================================== ENVELOPE
    <!-- envelope {{value}} {{tolerance}}% {{color-digit0}}{{color-digit1}}{{color-multiplier}}{{color-tolerance}} -->
    <g id="envelope-{{ix}}-{{iy}}" class="envelope">
        <use x="{{=leaf1-W + fold-width +  0}}" y="{{=leaf1-N - 15}}" xlink:href="#vbar-{{color-digit0}}" />
        <use x="{{=leaf1-W + fold-width + 10}}" y="{{=leaf1-N - 15}}" xlink:href="#vbar-{{color-digit1}}" />
        <use x="{{=leaf1-W + fold-width + 20}}" y="{{=leaf1-N - 15}}" xlink:href="#vbar-{{color-multiplier}}" />
        <use x="{{=leaf1-W + fold-width + 35}}" y="{{=leaf1-N - 15}}" xlink:href="#vbar-{{color-tolerance}}" />
        <use x="{{=leaf1-E - fold-width -  0}}" y="{{=leaf1-N - 15}}" xlink:href="#vbar-{{color-digit0}}" />
        <use x="{{=leaf1-E - fold-width - 10}}" y="{{=leaf1-N - 15}}" xlink:href="#vbar-{{color-digit1}}" />
        <use x="{{=leaf1-E - fold-width - 20}}" y="{{=leaf1-N - 15}}" xlink:href="#vbar-{{color-multiplier}}" />
        <use x="{{=leaf1-E - fold-width - 35}}" y="{{=leaf1-N - 15}}" xlink:href="#vbar-{{color-tolerance}}" />
        <use x="{{=leaf2-W + fold-width +  0}}" y="{{=leaf2-N - 15}}" xlink:href="#vbar-{{color-digit0}}" />
        <use x="{{=leaf2-W + fold-width + 10}}" y="{{=leaf2-N - 15}}" xlink:href="#vbar-{{color-digit1}}" />
        <use x="{{=leaf2-W + fold-width + 20}}" y="{{=leaf2-N - 15}}" xlink:href="#vbar-{{color-multiplier}}" />
        <use x="{{=leaf2-W + fold-width + 35}}" y="{{=leaf2-N - 15}}" xlink:href="#vbar-{{color-tolerance}}" />
        <use x="{{=leaf2-E - fold-width -  0}}" y="{{=leaf2-N - 15}}" xlink:href="#vbar-{{color-digit0}}" />
        <use x="{{=leaf2-E - fold-width - 10}}" y="{{=leaf2-N - 15}}" xlink:href="#vbar-{{color-digit1}}" />
        <use x="{{=leaf2-E - fold-width - 20}}" y="{{=leaf2-N - 15}}" xlink:href="#vbar-{{color-multiplier}}" />
        <use x="{{=leaf2-E - fold-width - 35}}" y="{{=leaf2-N - 15}}" xlink:href="#vbar-{{color-tolerance}}" />
        <use x="{{=leaf1-W - 15}}" y="{{=leaf1-cy - 20}}" xlink:href="#hbar-{{color-tolerance}}" />
        <use x="{{=leaf1-W - 15}}" y="{{=leaf1-cy -  5}}" xlink:href="#hbar-{{color-multiplier}}" />
        <use x="{{=leaf1-W - 15}}" y="{{=leaf1-cy +  5}}" xlink:href="#hbar-{{color-digit1}}" />
        <use x="{{=leaf1-W - 15}}" y="{{=leaf1-cy + 15}}" xlink:href="#hbar-{{color-digit0}}" />
        <use x="{{=leaf1-E - 15}}" y="{{=leaf1-cy - 20}}" xlink:href="#hbar-{{color-tolerance}}" />
        <use x="{{=leaf1-E - 15}}" y="{{=leaf1-cy -  5}}" xlink:href="#hbar-{{color-multiplier}}" />
        <use x="{{=leaf1-E - 15}}" y="{{=leaf1-cy +  5}}" xlink:href="#hbar-{{color-digit1}}" />
        <use x="{{=leaf1-E - 15}}" y="{{=leaf1-cy + 15}}" xlink:href="#hbar-{{color-digit0}}" />
        <use x="{{=leaf2-W - 15}}" y="{{=leaf2-cy - 20}}" xlink:href="#hbar-{{color-digit0}}" />
        <use x="{{=leaf2-W - 15}}" y="{{=leaf2-cy - 10}}" xlink:href="#hbar-{{color-digit1}}" />
        <use x="{{=leaf2-W - 15}}" y="{{=leaf2-cy +  0}}" xlink:href="#hbar-{{color-multiplier}}" />
        <use x="{{=leaf2-W - 15}}" y="{{=leaf2-cy + 15}}" xlink:href="#hbar-{{color-tolerance}}" />
        <use x="{{=leaf2-E - 15}}" y="{{=leaf2-cy - 20}}" xlink:href="#hbar-{{color-digit0}}" />
        <use x="{{=leaf2-E - 15}}" y="{{=leaf2-cy - 10}}" xlink:href="#hbar-{{color-digit1}}" />
        <use x="{{=leaf2-E - 15}}" y="{{=leaf2-cy +  0}}" xlink:href="#hbar-{{color-multiplier}}" />
        <use x="{{=leaf2-E - 15}}" y="{{=leaf2-cy + 15}}" xlink:href="#hbar-{{color-tolerance}}" />
        <text x="{{leaf1-cx}}" y="{{=leaf1-cy + 10}}" font-size="24pt" transform="rotate(180 {{leaf1-cx}},{{leaf1-cy}})">{{value}}<tspan font-size="12pt">Ω {{tolerance}}%</tspan></text>
        <text x="{{leaf2-cx}}" y="{{=leaf2-cy + 10}}" font-size="24pt">{{value}}<tspan font-size="12pt">Ω {{tolerance}}%</tspan></text>
        <use x="{{=leaf0-cx - 70}}" y="{{=leaf0-cy - 15}}" xlink:href="#digit-{{color-digit0}}" />
        <use x="{{=leaf0-cx - 35}}" y="{{=leaf0-cy - 15}}" xlink:href="#digit-{{color-digit1}}" />
        <use x="{{=leaf0-cx +  0}}" y="{{=leaf0-cy - 15}}" xlink:href="#multiplier-{{color-multiplier}}" />
        <use x="{{=leaf0-cx + 40}}" y="{{=leaf0-cy - 15}}" xlink:href="#tolerance-{{color-tolerance}}" />
    </g>
====================================================================== ENVELOPE VALUE 0
    <!-- envelope {{value}} Bk -->
    <g id="envelope-{{ix}}-{{iy}}" class="envelope">
        <use x="{{=leaf1-W + fold-width +  0}}" y="{{=leaf1-N - 15}}" xlink:href="#vbar-Bk" />
        <use x="{{=leaf1-E - fold-width -  0}}" y="{{=leaf1-N - 15}}" xlink:href="#vbar-Bk" />
        <use x="{{=leaf2-W + fold-width +  0}}" y="{{=leaf2-N - 15}}" xlink:href="#vbar-Bk" />
        <use x="{{=leaf2-E - fold-width -  0}}" y="{{=leaf2-N - 15}}" xlink:href="#vbar-Bk" />
        <use x="{{=leaf1-W - 15}}" y="{{=leaf1-cy + 0}}" xlink:href="#hbar-Bk" />
        <use x="{{=leaf1-E - 15}}" y="{{=leaf1-cy + 0}}" xlink:href="#hbar-Bk" />
        <use x="{{=leaf2-W - 15}}" y="{{=leaf2-cy - 0}}" xlink:href="#hbar-Bk" />
        <use x="{{=leaf2-E - 15}}" y="{{=leaf2-cy - 0}}" xlink:href="#hbar-Bk" />
        <text x="{{leaf1-cx}}" y="{{=leaf1-cy + 10}}" font-size="24pt" transform="rotate(180 {{leaf1-cx}},{{leaf1-cy}})">{{value}}<tspan font-size="12pt">Ω</tspan></text>
        <text x="{{leaf2-cx}}" y="{{=leaf2-cy + 10}}" font-size="24pt">{{value}}<tspan font-size="12pt">Ω</tspan></text>
        <use x="{{=leaf0-cx - 15}}" y="{{=leaf0-cy - 15}}" xlink:href="#digit-Bk" />
    </g>
====================================================================== ENVELOPE SPECIAL color-key
    <!-- color-key -->
    <g id="color-key" class="color-key">
        <text x="{{=leaf0-W + 150}}" y="{{=leaf0-cy - 15}}" font-size="12pt">digits</text>
        <use x="0" y="0" transform="translate({{=leaf0-W + 5 + (25 * 0)}},{{=leaf0-cy - 10}}) scale(0.66)" xlink:href="#digit-Bk" />
        <use x="0" y="0" transform="translate({{=leaf0-W + 5 + (25 * 1)}},{{=leaf0-cy - 10}}) scale(0.66)" xlink:href="#digit-Bn" />
        <use x="0" y="0" transform="translate({{=leaf0-W + 5 + (25 * 2)}},{{=leaf0-cy - 10}}) scale(0.66)" xlink:href="#digit-Rd" />
        <use x="0" y="0" transform="translate({{=leaf0-W + 5 + (25 * 3)}},{{=leaf0-cy - 10}}) scale(0.66)" xlink:href="#digit-Og" />
        <use x="0" y="0" transform="translate({{=leaf0-W + 5 + (25 * 4)}},{{=leaf0-cy - 10}}) scale(0.66)" xlink:href="#digit-Yw" />
        <use x="0" y="0" transform="translate({{=leaf0-W + 5 + (25 * 5)}},{{=leaf0-cy - 10}}) scale(0.66)" xlink:href="#digit-Gn" />
        <use x="0" y="0" transform="translate({{=leaf0-W + 5 + (25 * 6)}},{{=leaf0-cy - 10}}) scale(0.66)" xlink:href="#digit-Bl" />
        <use x="0" y="0" transform="translate({{=leaf0-W + 5 + (25 * 7)}},{{=leaf0-cy - 10}}) scale(0.66)" xlink:href="#digit-Vt" />
        <use x="0" y="0" transform="translate({{=leaf0-W + 5 + (25 * 8)}},{{=leaf0-cy - 10}}) scale(0.66)" xlink:href="#digit-Gy" />
        <use x="0" y="0" transform="translate({{=leaf0-W + 5 + (25 * 9)}},{{=leaf0-cy - 10}}) scale(0.66)" xlink:href="#digit-Wt" />
        <text x="{{=leaf1-W + 150}}" y="{{=leaf1-cy - 15}}" font-size="12pt">multiplier</text>
        <use x="0" y="0" transform="translate({{=leaf1-W + 5 + (25 * 0)}},{{=leaf1-cy - 10}}) scale(0.66)" xlink:href="#multiplier-Bk" />
        <use x="0" y="0" transform="translate({{=leaf1-W + 5 + (25 * 1)}},{{=leaf1-cy - 10}}) scale(0.66)" xlink:href="#multiplier-Bn" />
        <use x="0" y="0" transform="translate({{=leaf1-W + 5 + (25 * 2)}},{{=leaf1-cy - 10}}) scale(0.66)" xlink:href="#multiplier-Rd" />
        <use x="0" y="0" transform="translate({{=leaf1-W + 5 + (25 * 3)}},{{=leaf1-cy - 10}}) scale(0.66)" xlink:href="#multiplier-Og" />
        <use x="0" y="0" transform="translate({{=leaf1-W + 5 + (25 * 4)}},{{=leaf1-cy - 10}}) scale(0.66)" xlink:href="#multiplier-Yw" />
        <use x="0" y="0" transform="translate({{=leaf1-W + 5 + (25 * 5)}},{{=leaf1-cy - 10}}) scale(0.66)" xlink:href="#multiplier-Gn" />
        <use x="0" y="0" transform="translate({{=leaf1-W + 5 + (25 * 6)}},{{=leaf1-cy - 10}}) scale(0.66)" xlink:href="#multiplier-Bl" />
        <use x="0" y="0" transform="translate({{=leaf1-W + 5 + (25 * 7)}},{{=leaf1-cy - 10}}) scale(0.66)" xlink:href="#multiplier-Vt" />
        <use x="0" y="0" transform="translate({{=leaf1-W + 5 + (25 * 8)}},{{=leaf1-cy - 10}}) scale(0.66)" xlink:href="#multiplier-Gy" />
        <use x="0" y="0" transform="translate({{=leaf1-W + 5 + (25 * 9)}},{{=leaf1-cy - 10}}) scale(0.66)" xlink:href="#multiplier-Wt" />
        <use x="0" y="0" transform="translate({{=leaf1-W + 5 + (25 *10)}},{{=leaf1-cy - 10}}) scale(0.66)" xlink:href="#multiplier-Gd" />
        <use x="0" y="0" transform="translate({{=leaf1-W + 5 + (25 *11)}},{{=leaf1-cy - 10}}) scale(0.66)" xlink:href="#multiplier-Sr" />
        <text x="{{=leaf2-W + 150}}" y="{{=leaf2-cy - 15}}" font-size="12pt">tolerance</text>
        <use x="0" y="0" transform="translate({{=leaf2-W + 5 + (25 * 1)}},{{=leaf2-cy - 10}}) scale(0.66)" xlink:href="#tolerance-Bn" />
        <use x="0" y="0" transform="translate({{=leaf2-W + 5 + (25 * 2)}},{{=leaf2-cy - 10}}) scale(0.66)" xlink:href="#tolerance-Rd" />
        <use x="0" y="0" transform="translate({{=leaf2-W + 5 + (25 * 5)}},{{=leaf2-cy - 10}}) scale(0.66)" xlink:href="#tolerance-Gn" />
        <use x="0" y="0" transform="translate({{=leaf2-W + 5 + (25 * 6)}},{{=leaf2-cy - 10}}) scale(0.66)" xlink:href="#tolerance-Bl" />
        <use x="0" y="0" transform="translate({{=leaf2-W + 5 + (25 *10)}},{{=leaf2-cy - 10}}) scale(0.66)" xlink:href="#tolerance-Gd" />
        <use x="0" y="0" transform="translate({{=leaf2-W + 5 + (25 *11)}},{{=leaf2-cy - 10}}) scale(0.66)" xlink:href="#tolerance-Sr" />
    </g>
====================================================================== HBAR
        <symbol id="hbar-{{color}}"><rect class="bar {{color}}" x="0" y="0" width="30" height="5" rx="2" ry="2"/></symbol>
====================================================================== VBAR
        <symbol id="vbar-{{color}}"><rect class="bar {{color}}" x="0" y="0" width="5" height="30" rx="2" ry="2"/></symbol>
====================================================================== DIGIT
        <symbol id="digit-{{color}}" class="digit {{color}}">
            <rect class="box {{color}}" x="0" y="0" width="30" height="30"/>
            <text x="15" y="24" font-size="18pt">{{digit}}</text>
        </symbol>
====================================================================== MULTIPLIER
        <symbol id="multiplier-{{color}}" class="multiplier {{color}}">
            <rect class="box {{color}}" x="0" y="0" width="30" height="30"/>
            <text x="15" y="24" font-size="6pt">10<tspan font-size="14pt">{{multiplier}}</tspan></text>
        </symbol>
====================================================================== TOLERANCE
        <symbol id="tolerance-{{color}}" class="tolerance {{color}}">
            <rect class="box {{color}}" x="0" y="0" width="30" height="30"/>
            <text x="15" y="24" font-size="10pt">{{tolerance}}<tspan font-size="6pt">%</tspan></text>
        </symbol>
====================================================================== PAGE
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg 
    xmlns:svg="http://www.w3.org/2000/svg"
    xmlns:xlink="http://www.w3.org/1999/xlink"
    xmlns="http://www.w3.org/2000/svg"
    version="1.1"
    width="{{=E - W}}px"
    height="{{=S - N}}px">

    <defs>
        <style><![CDATA[
            text {
                font-family: Arial, sans-serif;
                text-anchor: middle;
            }
            symbol {
                overflow: visible;
            }
            .background {
                fill: #FFF;
                stroke: none;
            }
            .cut {
                fill: none;
                stroke: #000;
                stroke-width: 1;
            }
            .fold {
                fill: none;
                stroke: #BBB;
                stroke-width: 1;
            }
            .bar {
                stroke: none;
                stroke-width: 1;
            }
            .box {
                stroke-width: 2;
            }
            rect.Bk { fill: #000000; stroke: #000000; }
            rect.Bn { fill: #705000; stroke: #705000; }
            rect.Rd { fill: #E54444; stroke: #E54444; }
            rect.Og { fill: #FC8810; stroke: #FC8810; }
            rect.Yw { fill: #EEEE00; stroke: #EEEE00; }
            rect.Gn { fill: #00A000; stroke: #00A000; }
            rect.Bl { fill: #0000FF; stroke: #0000FF; }
            rect.Vt { fill: #C050DD; stroke: #C050DD; }
            rect.Gy { fill: #AAAAAA; stroke: #AAAAAA; }
            rect.Wt { fill: #FFFFFF; stroke: #AAAAAA; }
            rect.Gd { fill: #E0D000; stroke: #AAAAAA; }
            rect.Sr { fill: #DDDDDD; stroke: #AAAAAA; }
            symbol.Bk text { fill: #DDDDDD; stroke: none; }
            symbol.Bn text { fill: #DDDDDD; stroke: none; }
            symbol.Bl text { fill: #DDDDDD; stroke: none; }
            symbol.multiplier tspan { baseline-shift: 4pt; }
        ]]></style>

{{hbars}}
{{vbars}}
{{digits}}
{{multipliers}}
{{tolerances}}
    </defs>

    <rect class="background" x="{{W}}" y="{{N}}" width="{{=E - W}}" height="{{=S - N}}" />

{{cuts}}
{{folds}}
{{envelopes}}

</svg>
====================================================================== CUT
    <line class="cut" x1="{{W}}" x2="{{E}}" y1="{{N}}" y2="{{S}}" />
====================================================================== FOLD
    <line class="fold" x1="{{W}}" x2="{{E}}" y1="{{N}}" y2="{{S}}" />
