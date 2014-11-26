package # hide from PAUSE
App::YTDL::YTConfig;

use warnings;
use strict;
use 5.010000;

use Exporter qw( import );
our @EXPORT_OK = qw( map_fmt_to_quality read_config_file options );

use File::Spec::Functions qw( catfile );
use File::Temp            qw();
use FindBin               qw( $RealBin $RealScript );
use List::Util            qw( max );
use Pod::Usage            qw( pod2usage );

use JSON                   qw();
use Term::Choose           qw( choose );
use Term::ReadLine::Simple qw();
use Text::LineFold         qw();


use App::YTDL::GenericFunc qw( term_size print_hash encode_fs choose_a_dir choose_a_number insert_sep );


sub map_fmt_to_quality {
    return [
        [ 13 => ' 176x144  3GP', ],
        [ 17 => ' 176x144  3GP', ],
        [ 36 => ' 320x240  3GP', ],

         [ 5 => ' 360x240  FLV', ], # 400
         [ 6 => ' 480x270  FLV', ],
        [ 34 => ' 640x360  FLV', ],
        [ 35 => ' 854x480  FLV', ],

        [ 18 => ' 640x360  MP4', ],
        [ 22 => '1280x720  MP4', ],
        [ 37 => '1920x1080 MP4', ],
        [ 38 => '4096x3072 MP4', ],

        [ 43 => ' 640x360  WebM', ],
        [ 44 => ' 854x480  WebM', ],
        [ 45 => '1280x720  WebM', ],
        [ 46 => '1920x1080 WebM', ],

        [ 82 => ' 640x360  MP4_3D', ],
        [ 83 => ' 854x480  MP4_3D', ],
        [ 84 => '1280x720  MP4_3D', ],
        [ 85 => '1920x1080 MP4_3D', ],

        [ 100 => ' 640x360  WebM_3D', ],
        [ 101 => ' 854x480  WebM_3D', ],
        [ 102 => '1280x720  WebM_3D', ],

         [ 92 => 'HLS  240  MP4', ],
         [ 93 => 'HLS  360  MP4', ],
         [ 94 => 'HLS  480  MP4', ],
         [ 95 => 'HLS  720  MP4', ],
         [ 96 => 'HLS 1080  MP4', ],
        [ 132 => 'HLS  240  MP4', ],
        [ 151 => 'HLS   72  MP4', ],

        [ 139 => 'DASH audio   48  M4A', ],
        [ 140 => 'DASH audio  128  M4A', ],
        [ 141 => 'DASH audio  256  M4A', ],

        [ 171 => 'DASH audio  128 WebM', ],
        [ 172 => 'DASH audio  256 WebM', ],

        [ 133 => 'DASH video  240  MP4', ],
        [ 134 => 'DASH video  360  MP4', ],
        [ 135 => 'DASH video  480  MP4', ],
        [ 136 => 'DASH video  720  MP4', ],
        [ 137 => 'DASH video 1080  MP4', ],
        [ 138 => 'DASH video 2160  MP4', ],

        [ 160 => 'DASH video  144  MP4',],
        [ 264 => 'DASH video 1440  MP4',],
        [ 298 => 'DASH video  720  MP4 h264 60fps', ],
        [ 299 => 'DASH video 1080  MP4 h264 60fps', ],
        [ 266 => 'DASH video 2160  MP4 h264', ],

        [ 167 => 'DASH video  360x640  WebM VP8', ],
        [ 168 => 'DASH video  480x854  WebM VP8', ],
        [ 169 => 'DASH video  720x1280 WebM VP8', ],
        [ 170 => 'DASH video 1080x1920 WebM VP8', ],
        [ 218 => 'DASH video  480x854  WebM VP8', ],
        [ 219 => 'DASH video  480x854  WebM VP8', ],

        [ 242 => 'DASH video  240 WebM', ],
        [ 243 => 'DASH video  360 WebM', ],
        [ 244 => 'DASH video  480 WebM', ],
        [ 245 => 'DASH video  480 WebM', ],
        [ 246 => 'DASH video  480 WebM', ],
        [ 247 => 'DASH video  720 WebM', ],
        [ 248 => 'DASH video 1080 WebM', ],
        [ 271 => 'DASH video 1440 WebM', ],
        [ 272 => 'DASH video 2160 WebM', ],

        [ 278 => 'DASH video  144 WebM VP9', ],
        [ 302 => 'DASH video  720 WebM VP9', ],
        [ 303 => 'DASH video 1080 WebM VP9', ],
    ];
}


sub options {
    my ( $opt ) = @_;
    my $help         = "  HELP";
    my $show_path    = "  PATH";
    my $useragent    = "- UserAgent";
    my $overwrite    = "- Overwrite files";
    my $auto_fmt     = "- Set auto quality";
    my $preferred    = "- Preferred qualities";
    my $retries      = "- Download retries";
    my $timeout      = "- Timeout";
    my $logging      = "- Enable logging";
    my $info_width   = "- Max info width";
    my $auto_width   = "- Enable auto width";
    my $filename_len = "- Max filename length";
    my $len_kb_sec   = "- Digits 'k/s'";
    my $yt_video_dir = "- Video directory";
    my $channel_hist = "- Channel history";
    my $new_first    = "- Sort order";
    my %c_hash = (
        $help         => 'show_help_text',
        $show_path    => 'show_path',
        $useragent    => 'useragent',
        $overwrite    => 'overwrite',
        $auto_fmt     => 'auto_quality',
        $preferred    => 'preferred',
        $retries      => 'retries',
        $timeout      => 'timeout',
        $logging      => 'log_info',
        $info_width   => 'max_info_width',
        $auto_width   => 'auto_width',
        $filename_len => 'max_len_f_name',
        $len_kb_sec   => 'kb_sec_len',
        $yt_video_dir => 'yt_video_dir',
        $channel_hist => 'max_channels',
        $new_first    => 'new_first',
    );
    my @choices = (
        $help,
        $show_path,
        $useragent,
        $overwrite,
        $auto_fmt,
        $preferred,
        $retries,
        $timeout,
        $logging,
        $info_width,
        $auto_width,
        $filename_len,
        $len_kb_sec,
        $yt_video_dir,
        $channel_hist,
        $new_first,
    );
    my $continue = '  ' . $opt->{continue};
    my $quit     = '  ' . $opt->{quit};

    OPTION: while ( 1 ) {
        # Choose
        print "\n";
        my $c_key = choose(
            [ undef, $continue, @choices ],
            { prompt => "Options:", layout => 3, clear_screen => 1, undef => $quit }
        );
        if ( ! defined $c_key ) {
            _write_config_file( $opt, $opt->{config_file}, values %c_hash ) if $opt->{change};
            exit();
        }
        if ( $c_key eq $continue ) {
            _write_config_file( $opt, $opt->{config_file}, values %c_hash ) if $opt->{change};
            delete $opt->{change};
            last OPTION;
        }
        my $choice = $c_hash{$c_key};
        if ( $choice eq "show_help_text" ) {
            pod2usage( { -exitval => 'NOEXIT', -verbose => 2 } );
        }
        elsif ( $choice eq "show_path" ) {
            my $version      = '  version  ';
            my $bin          = '    bin    ';
            my $yt_video_dir = ' video dir ';
            my $log_file     = ' log file  ';
            my $config_file  = 'config file';
            my $path = {
                $version      => $main::VERSION,
                $bin          => catfile( $RealBin, $RealScript ),
                $yt_video_dir => $opt->{yt_video_dir},
                $log_file     => $opt->{log_file},
                $config_file  => $opt->{config_file},
            };
            my $keys = [ $version, $bin, $yt_video_dir, $log_file, $config_file ];
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
            my $list = [
                'choose always manually',
                'keep choice for the respective Playlist/Channel if possible',
                'keep choice always if possible',
                'use preferred qualities',
                'use always default (best) quality',
            ];
            _opt_choose_from_list( $opt, $choice, $list );
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
        elsif ( $choice eq "auto_width" ) {
            my $prompt = 'Enable auto width';
            _opt_yes_no( $opt, $choice, $prompt );
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
        elsif ( $choice eq "yt_video_dir" ) {
            my $prompt = 'Video directory';
            _opt_choose_a_directory( $opt, $choice, $prompt );
        }
        elsif ( $choice eq "max_channels" ) {
            my $prompt = 'Channelhistory: save x channels. Disabled if x is 0';
            my $digits = 3;
            _opt_number_range( $opt, $choice, $prompt, 3 )
        }
        elsif ( $choice eq "new_first" ) {
            my $prompt = 'Latest videos on top of the list';
            _opt_yes_no( $opt, $choice, $prompt );
        }
        else { die $choice }
    }
    return $opt;
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
        { prompt => $prompt . ' [' . $current . ']:', layout => 1, undef => $opt->{s_back} }
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
        { prompt => $prompt . ' [' . $current . ']:', layout => 1, justify => 1, order => 0, undef => $opt->{s_back} }
    );
    return if ! defined $choice;
    $opt->{$section} = $choice;
    $opt->{change}++;
    return;
}

sub _opt_choose_from_list {
    my ( $opt, $section, $list ) = @_;
    my @options = ();
    my $len = length( scalar @$list );
    for my $i ( 0 .. $#$list ) {
        push @options, sprintf "%*d => %s", $len, $i, $list->[$i];
    }
    my $prompt = "$section [" . ( $opt->{$section} // '--' ) . "]";
    my $value = choose( [ undef, @options ], { prompt => $prompt, layout => 3, undef => $opt->{s_back} } );
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
        my $prompt = $key_cur . join( ', ', @$current ) . "\n";
        $prompt   .= $key_new . join( ', ', @$new )     . "\n\n";
        $prompt   .= 'Choose:';
        # Choose
        my $val = choose(
            [ undef, $opt->{confirm}, map( "  $_", @$available ) ],
            { prompt => $prompt, lf => [0,$l_k], layout => 3, clear_screen => 1, undef => $opt->{back} }
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
        if ( $val eq $opt->{confirm} ) {
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
    return $opt;
}


sub _write_json {
    my ( $file, $h_ref ) = @_;
    my $json = JSON::XS->new->pretty->encode( $h_ref );
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
    my $h_ref = JSON::XS->new->pretty->decode( $json ) if $json;
    return $h_ref;
}


1;


__END__
