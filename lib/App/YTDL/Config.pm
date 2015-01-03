package # hide from PAUSE
App::YTDL::Config;

use warnings;
use strict;
use 5.010000;

use Exporter qw( import );
our @EXPORT_OK = qw( map_fmt_to_quality read_config_file set_options );

use File::Spec::Functions qw( catfile );
use File::Temp            qw();
use FindBin               qw( $RealBin $RealScript );
use List::Util            qw( max );
use Pod::Usage            qw( pod2usage );

use JSON                   qw();
use Term::Choose           qw( choose );
use Term::ReadLine::Simple qw();
use Text::LineFold         qw();

use App::YTDL::Helper     qw( term_size print_hash encode_fs choose_a_dir choose_a_number insert_sep );
use App::YTDL::YT_Quality qw( map_fmt_to_quality );



sub _menus {
    my $menus = {
        main => [
            [ 'show_help_text',  "  HELP"      ],
            [ 'show_path',       "  PATH"      ],
            [ 'group_download',  "- Download"  ],
            [ 'group_quality',   "- Quality"   ],
            [ 'group_history',   "- History"   ],
            [ 'group_directory', "- Directory" ],
            [ 'group_output',    "- Output"    ],
        ],
        group_download => [
            [ 'useragent',      "- UserAgent"           ],
            [ 'overwrite',      "- Overwrite"           ],
            [ 'max_len_f_name', "- Max filename length" ],
            [ 'retries',        "- Download retries"    ],
            [ 'timeout',        "- Timeout"             ],
        ],
        group_quality => [
            [ 'auto_quality', "- Auto quality mode"   ],
            [ 'preferred',    "- Preferred qualities" ],
        ],
        group_history => [
            [ 'log_info',     "- Logging"         ],
            [ 'max_channels', "- Channel history" ],
        ],
        group_directory => [
            [ 'video_dir',     "- Video directory"     ],
            [ 'extractor_dir', "- Extractor directory" ],
            [ 'channel_dir',   "- Channel directory"   ],
        ],
        group_output => [
            [ 'max_info_width', "- Max info width" ],
            [ 'kb_sec_len',     "- Digits 'k/s'"   ],
            [ 'new_first',      "- Sort order"     ],
        ],
    };
    return $menus;
}


sub set_options {
    my ( $opt ) = @_;
    my $menus = _menus();
    my @keys;
    for my $group ( keys %$menus ) {
        next if $group eq 'main';
        push @keys, map { $_->[0] } @{$menus->{$group}};
    }
    my $group = 'main';

    GROUP: while ( 1 ) {
        my $menu = $menus->{$group};

        OPTION: while ( 1 ) {
            my $back     = '  QUIT';
            my $continue = $group eq 'main' ? '  CONTINUE' : '  MENU';
            my @pre  = ( undef, $continue );
            my @real = map( $_->[1], @$menu );
            # Choose
            my $idx = choose(
                [ @pre, @real ],
                { prompt => "Options:", layout => 3, index => 1, clear_screen => 1, undef => $back }
            );
            if ( ! defined $idx ) {
                _write_config_file( $opt, $opt->{config_file}, @keys );
                exit;
            }
            my $choice = $idx <= $#pre ? $pre[$idx] : $menu->[$idx - @pre][0];
            if ( ! defined $choice ) {
                _write_config_file( $opt, $opt->{config_file}, @keys );
                exit;
            }
            if ( $choice =~ /^group_/ ) {
                $group = $choice;
                redo GROUP;
            }
            if ( $choice eq $continue ) {
                if ( $group =~ /^group_/ ) {
                    $group = 'main';
                    redo GROUP;
                }
                _write_config_file( $opt, $opt->{config_file}, @keys );
                delete $opt->{change};
                last GROUP;
            }
            if ( $choice eq "show_help_text" ) {
                pod2usage( { -exitval => 'NOEXIT', -verbose => 2 } );
            }
            elsif ( $choice eq "show_path" ) {
                my $version     = '  version  ';
                my $bin         = '    bin    ';
                my $video_dir   = ' video dir ';
                my $config_dir  = 'config dir ';
                my $path = {
                    $version    => $main::VERSION,
                    $bin        => catfile( $RealBin, $RealScript ),
                    $video_dir  => $opt->{video_dir},
                    $config_dir => $opt->{config_dir},

                };
                my $keys = [ $version, $bin, $video_dir, $config_dir ];
                print_hash( $path, { keys => $keys, preface => ' Close with ENTER' } );
            }
            elsif ( $choice eq "useragent" ) {
                my $prompt = 'Set the UserAgent: ';
                _local_read_line( $opt, $choice, $prompt );
                $opt->{useragent} = 'Mozilla/5.0' if $opt->{useragent} eq '';
                $opt->{useragent} = ''            if $opt->{useragent} eq '""';
            }
            elsif ( $choice eq "overwrite" ) {
                my $prompt = 'Overwrite files';
                _opt_yes_no( $opt, $choice, $prompt );
            }
            elsif ( $choice eq "log_info" ) {
                my $prompt = 'Enable info-logging';
                _opt_yes_no( $opt, $choice, $prompt );
            }
            elsif ( $choice eq "auto_quality" ) {
                my $prompt = 'Auto quality';
                my $list = [
                    'choose always manually',
                    'keep choice for the respective Playlist/Channel if possible',
                    'keep choice always if possible',
                    'use preferred qualities',
                    'use always default (best) quality',
                ];
                _opt_choose_from_list( $opt, $choice, $prompt, $list );
            }
            elsif ( $choice eq "preferred" ) {
                my ( $hash, $keys );
                my $ref = map_fmt_to_quality();
                for my $ar ( @$ref ) {
                    $hash->{$ar->[0]} = $ar->[1];
                    push @$keys, $ar->[0];
                }
                _opt_choose_a_list( $opt, $choice, $hash, $keys );
            }
            elsif ( $choice eq "retries" ) {
                my $prompt = 'Download retries';
                my $digits = 3;
                _opt_number_range( $opt, $choice, $prompt, 3 )
            }
            elsif ( $choice eq "timeout" ) {
                my $prompt = 'Connection timeout (s)';
                my $digits = 3;
                _opt_number_range( $opt, $choice, $prompt, 3 )
            }
            elsif ( $choice eq "max_info_width" ) {
                my $prompt = 'Maximum Info width';
                my $digits = 3;
                _opt_number_range( $opt, $choice, $prompt, 3 )
            }
            elsif ( $choice eq "max_len_f_name" ) {
                my $prompt = 'Maximum filename length';
                my $digits = 3;
                _opt_number_range( $opt, $choice, $prompt, 3 )
            }
            elsif ( $choice eq "kb_sec_len" ) {
                my ( $min, $max ) = ( 3, 9 );
                my $prompt = 'Digits for "k/s" (download speed)';
                _opt_number( $opt, $choice, $prompt, $min, $max );
            }
            elsif ( $choice eq "video_dir" ) {
                my $prompt = 'Video directory';
                _opt_choose_a_directory( $opt, $choice, $prompt );
            }
            elsif ( $choice eq "max_channels" ) {
                my $prompt = 'Channelhistory: save x channels. Disabled if x is 0';
                my $digits = 3;
                _opt_number_range( $opt, $choice, $prompt, 3 )
            }
            elsif ( $choice eq "extractor_dir" ) {
                my $prompt = 'Use extractor directory';
                my $list = [
                    'No',
                    'Yes',
                ];
                _opt_choose_from_list( $opt, $choice, $prompt, $list );
            }
            elsif ( $choice eq "channel_dir" ) {
                my $prompt = 'Use channel directory';
                my $list = [
                    'No',
                    'If chosen from a channel or list',
                    'Always',
                ];
                _opt_choose_from_list( $opt, $choice, $prompt, $list );
            }
            elsif ( $choice eq "new_first" ) {
                my $prompt = 'Latest videos on top of the list';
                _opt_yes_no( $opt, $choice, $prompt );
            }
            else { die $choice }
        }
    }
    return;
}


sub _opt_choose_a_directory {
    my( $opt, $choice, $prompt ) = @_;
    my $new_dir = choose_a_dir( { dir => $opt->{$choice} } );
    return if ! defined $new_dir;
    if ( $new_dir ne $opt->{$choice} ) {
        if ( ! eval {
            my $fh = File::Temp->new( TEMPLATE => 'XXXXXXXXXXXXXXX', UNLINK => 1, DIR => $new_dir );
            1 }
        ) {
            print "$@";
            choose( [ 'Press Enter:' ], { prompt => '' } );
        }
        else {
            $opt->{$choice} = $new_dir;
            $opt->{change}++;
        }
    }
}


sub _local_read_line {
    my ( $opt, $section, $prompt ) = @_;
    my $current = $opt->{$section} // '';
    my $trs = Term::ReadLine::Simple->new();
    # Readline
    my $string = $trs->readline( $prompt, { default => $current } );
    $opt->{$section} = $string;
    $opt->{change}++;
    return;
}


sub _opt_yes_no {
    my ( $opt, $section, $prompt ) = @_;
    my ( $yes, $no ) = ( 'YES', 'NO' );
    my $current = $opt->{$section} ? $yes : $no;
    # Choose
    my $choice = choose(
        [ undef, $yes, $no ],
        { prompt => $prompt . ' [' . $current . ']:', layout => 1, undef => '<<' }
    );
    return if ! defined $choice;
    $opt->{$section} = $choice eq $yes ? 1 : 0;
    $opt->{change}++;
    return;
}


sub _opt_number_range {
    my ( $opt, $section, $prompt, $digits ) = @_;
    my $current = $opt->{$section};
    $current = insert_sep( $current ); # $opt->{thsd_sep}
    # Choose_a_number
    my $choice = choose_a_number( $digits, { name => $prompt, current => $current } );
    return if ! defined $choice;
    $opt->{$section} = $choice eq '--' ? undef : $choice;
    $opt->{change}++;
    return;
}


sub _opt_number {
    my ( $opt, $section, $prompt, $min, $max ) = @_;
    my $current = $opt->{$section};
    # Choose
    my $choice = choose(
        [ undef, $min .. $max ],
        { prompt => $prompt . ' [' . $current . ']:', layout => 1, justify => 1, order => 0, undef => '<<' }
    );
    return if ! defined $choice;
    $opt->{$section} = $choice;
    $opt->{change}++;
    return;
}


sub _opt_choose_from_list {
    my ( $opt, $section, $prompt, $list ) = @_;
    my @options;
    my $len = length( scalar @$list );
    for my $i ( 0 .. $#$list ) {
        push @options, sprintf "%*d => %s", $len, $i, $list->[$i];
    }
    $prompt .= ' [' . ( $opt->{$section} // '--' ) . ']';
    my $value = choose( [ undef, @options ], { prompt => $prompt, layout => 3, undef => '<<' } );
    return if ! defined $value;
    $value = ( split / => /, $value )[0];
    $opt->{$section} = $value;
    $opt->{change}++;
    return;
}


sub _opt_choose_a_list {
    my ( $opt, $section, $ref, $keys ) = @_;
    my $available = [];
    my $len_key = max map length, @$keys;
    for my $key ( @$keys ) {
        push @$available, sprintf "%*d => %s", $len_key, $key, $ref->{$key};
    }
    my $current = $opt->{$section} // [];
    my $new     = [];
    my $key_cur = 'Current > ';
    my $key_new = '    New > ';
    my $l_k     = length $key_cur > length $key_new ? length $key_cur : length $key_new;
    my $lf      = Text::LineFold->new( %{$opt->{line_fold}} );
    $lf->config( 'ColMax', ( term_size() )[0] );
    while ( 1 ) {
        my $confirm = 'CONFIRM';
        my $prompt = $key_cur . join( ', ', @$current ) . "\n";
        $prompt   .= $key_new . join( ', ', @$new )     . "\n\n";
        $prompt   .= 'Choose:';
        # Choose
        my $val = choose(
            [ undef, $confirm, map( "  $_", @$available ) ],
            { prompt => $prompt, lf => [0,$l_k], layout => 3, clear_screen => 1, undef => 'BACK' }
        );
        if ( ! defined $val ) {
            if ( @$new ) {
                $new = [];
                next;
            }
            else {
                return;
            }
        }
        if ( $val eq $confirm ) {
            if ( @$new ) {
                $opt->{$section} = $new;
                $opt->{change}++;
            }
            return;
        }
        $val =~ s/^\s+//;
        $val = ( split / => /, $val )[0];
        push @$new, $val;
    }
}


sub _write_config_file {
    my ( $opt, $file, @keys ) = @_;
    return if ! $opt->{change};
    my $tmp = {};
    for my $section ( sort @keys ) {
        $tmp->{$section} = $opt->{$section};
    }
    _write_json( $file, $tmp );
}


sub read_config_file {
    my ( $opt, $file ) = @_;
    my $tmp = _read_json( $file );
    for my $section ( keys %$tmp ) {
        $opt->{$section} = $tmp->{$section};
    }
    return;
}


sub _write_json {
    my ( $file, $h_ref ) = @_;
    my $json = JSON::XS->new->pretty->utf8->encode( $h_ref );
    open my $fh, '>', encode_fs( $file ) or die $!;
    print $fh $json;
    close $fh;
}


sub _read_json {
    my ( $file ) = @_;
    return {} if ! -f encode_fs( $file );
    open my $fh, '<', encode_fs( $file ) or die $!;
    my $json = do { local $/; <$fh> };
    close $fh;
    my $h_ref = JSON::XS->new->pretty->utf8->decode( $json ) if $json;
    return $h_ref;
}


1;


__END__
